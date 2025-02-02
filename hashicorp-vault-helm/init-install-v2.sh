#!/bin/bash
set -euo pipefail

# Enable debug mode (true/false)
DEBUG=false

# Enable trace mode (true/false)
TRACE=false

# Enable trace mode only if both DEBUG and TRACE are true
if ${DEBUG} && ${TRACE}; then
    set -x
fi

readonly JQ="$(command -v jq)"
readonly VAULT_KEYS_FILE=".vault-init.txt"
readonly VAULT_INIT_SECRET_NAME="vault-operator-init"
readonly UNSEAL_SHARES=5
readonly UNSEAL_THRESHOLD=3
readonly VAULT_NAMESPACE="vault"
readonly TEMP_DIR=$(mktemp --directory --tmpdir="${PWD}")
readonly FULL_PATH_VAULT_KEYS_FILE="${TEMP_DIR}/${VAULT_KEYS_FILE}"

# Logging colors
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly ORANGE='\033[38;5;214m'
readonly BLUE='\033[0;34m'
readonly WHITE='\033[1;37m'
readonly RESET='\033[0m'  # Reset color (default)

# Functions
function log() {
  local level="${1:-INFO}" # Default to INFO if no level is provided
  local message="${2}"
  local message_length=${#message}
  local timestamp=$(date +"%Y-%m-%d %H:%M:%S")
  local border="---------------------------------------------------------------------------------"
  local border_length=$(( ${#border} - 2 ))
  local padding_length=$(( (border_length - message_length - 2) / 2 )) # Subtract 2 for the "⎈" symbols
  local padding=$(printf '%*s' "${padding_length}" "") # Create padding spaces
  local color=""

  case "${level}" in
    INFO) color="${WHITE}" ;;
    DEBUG) color="${YELLOW}" ;;
    WARNING) color="${ORANGE}" ;;
    ERROR) color="${RED}" ;;
    SUCCESS) color="${GREEN}" ;;
    *) color="${RESET}" ;; # Default color for unknown levels
  esac

  printf "%b%s\n⎈ %s%s%s ⎈\n%s%b\n" "${BLUE}" "${border}" "${padding}" "${message}" "${padding}" "${border}" "${WHITE}" >&2
  printf "%b[%s] [%s]%b\n" "${color}" "${timestamp}" "${level}" "${RESET}" >&2
}

function debug() {
  if [ "${DEBUG}" = true ]; then
    log "DEBUG" "${1}" >&2
  fi
}

# Trace logging function
function trace() {
    local message="${1}"
    if ${DEBUG} && ${TRACE}; then
        log "TRACE" "${message}" >&2
    fi
}

function cleanup() {
  debug "Cleaning up temporary directory: ${TEMP_DIR}"
  rm -rf "${TEMP_DIR}"
  log "SUCCESS" "HashiCorp Vault Deployment Successful"
}

# Reusable function to execute commands in a Vault pod
function exec_in_vault_pod() {
  local pod_index="${1}"
  shift
  local command="${@}"
  oc exec -n "${VAULT_NAMESPACE}" -ti "vault-${pod_index}" -- ${command}
}

# Reusable function to check command status
function check_command_status() {
  local exit_code=${?}
  local command="${1}"
  if [ ${exit_code} -ne 0 ]; then
    log "ERROR" "Command failed: ${command}"
    exit 1
  else
    debug "Command succeeded: ${command}"
  fi
}

# Reusable function to verify dependencies status
function validate_dependencies() {
  local dependencies=("jq" "oc")
  for cmd in "${dependencies[@]}"; do
    if ! command -v "${cmd}" > /dev/null 2>&1; then
      log "ERROR" "Command '${cmd}' not found. Please install it and try again."
      exit 1
    else
      debug "Command '${cmd}' found."
    fi
  done
  log "INFO" "Dependencies Validated"
}

function initialize_vault() {
  log "INFO" "Starting Vault Initialization"
  debug "Initializing Vault with ${UNSEAL_SHARES} unseal shares and a threshold of ${UNSEAL_THRESHOLD}"
  exec_in_vault_pod 0 vault operator init \
    -format=json \
    -key-shares ${UNSEAL_SHARES} \
    -key-threshold ${UNSEAL_THRESHOLD} > "${FULL_PATH_VAULT_KEYS_FILE}"
  
  check_command_status "vault operator init"

  readonly VAULT_KEYS_PAYLOAD=$(cat "${FULL_PATH_VAULT_KEYS_FILE}")
  debug "Creating Kubernetes secret ${VAULT_INIT_SECRET_NAME} in namespace ${VAULT_NAMESPACE}"
  oc create -n "${VAULT_NAMESPACE}" secret generic "${VAULT_INIT_SECRET_NAME}" \
    --from-env-file <(${JQ} -r "to_entries|map(\"\(.key)=\(.value|tostring)\")|.[]" "${FULL_PATH_VAULT_KEYS_FILE}")

  check_command_status "oc create secret"

  # Print the Vault URL and the root token from the FULL_PATH_VAULT_KEYS_FILE
  local VAULT_URL="https://$(oc get routes.route.openshift.io vault -n vault -o jsonpath --template='{.spec.host}{"\n"}')"
  echo "Vault URL: ${VAULT_URL}"
  echo "Vault initialization complete. Root token: $(${JQ} -r '.root_token' ${FULL_PATH_VAULT_KEYS_FILE})"
}

function unseal_vault() {
  local pod_index=${1}
  local unseal_keys=($(echo "${VAULT_KEYS_PAYLOAD}" | ${JQ} -r ".unseal_keys_b64[]"))
  
  debug "Unsealing Vault pod 'vault-${pod_index}'"
  for key_index in $(shuf -i 0-$((UNSEAL_SHARES - 1)) -n ${UNSEAL_THRESHOLD}); do
    log "INFO" "Unsealing pod 'vault-${pod_index}' using unseal key index: ${key_index}"
    exec_in_vault_pod "${pod_index}" vault operator unseal "${unseal_keys[${key_index}]}"
    check_command_status "vault operator unseal"
  done
}

function first_vault_login_with_root_token() {
  local pod_index="${1}"
  local max_attempts=5
  local attempt=1
  local delay=5

  debug "First login via Root Token on 'vault-${pod_index}'"

  while [ ${attempt} -le ${max_attempts} ]; do
    log "INFO" "Attempt ${attempt} of ${max_attempts} to login via Root Token on 'vault-${pod_index}'"
    
    # Check if Vault pod is ready
    if ! exec_in_vault_pod "${pod_index}" vault status > /dev/null 2>&1; then
      log "WARNING" "Vault pod 'vault-${pod_index}' is not ready. Retrying in ${delay} seconds..."
      $(command -v sleep) ${delay}
      attempt=$((attempt + 1))
      continue
    fi

    # Attempt to login with the root token
    exec_in_vault_pod "${pod_index}" vault login "$(echo "${VAULT_KEYS_PAYLOAD}" | "${JQ}" -r '.root_token')"
    
    # Check if the command was successful
    if [ ${?} -eq 0 ]; then
      debug "Successfully logged in via Root Token on 'vault-${pod_index}'"
      return 0
    else
      log "WARNING" "Failed to login via Root Token on 'vault-${pod_index}' (Attempt ${attempt} of ${max_attempts})"
      attempt=$((attempt + 1))
      sleep ${delay}
    fi
  done

  # If all attempts fail, log an error and exit
  log "ERROR" "Failed to login via Root Token on 'vault-${pod_index}' after ${max_attempts} attempts"
  exit 1
}

function enable_audit_logging() {
  local pod_index=${1}
  log "INFO" "Enabling Audit Logging on 'vault-${pod_index}'"
  exec_in_vault_pod "${pod_index}" vault audit enable -path="vault-${pod_index}_file_audit_" file \
    format=json \
    prefix="ocp_vault-${pod_index}_" \
    file_path="/vault/audit/vault-${pod_index}_audit.log"
  
  check_command_status "vault audit enable file"

  exec_in_vault_pod "${pod_index}" vault audit enable -path="vault-${pod_index}_socket_audit_" socket \
    address="127.0.0.1:8200" \
    socket_type=tcp

  check_command_status "vault audit enable socket"
}

function join_cluster() {
  local pod_index=${1}
  log "INFO" "Joining server 'vault-${pod_index}' to the cluster"
  exec_in_vault_pod "${pod_index}" vault operator raft join http://vault-0.vault-internal:8200
  check_command_status "vault operator raft join"
}

# Main function
function main() {
clear
trap cleanup EXIT
validate_dependencies

initialize_vault

for pod_index in $(oc get pods -n "${VAULT_NAMESPACE}" -o=jsonpath='{.items[?(@.metadata.labels.app\.kubernetes\.io\/name=="vault")].metadata.labels.apps\.kubernetes\.io\/pod-index}'); do
  if [[ "${pod_index}" -gt 0 ]]; then
    join_cluster "${pod_index}"
  fi
  unseal_vault "${pod_index}"
  first_vault_login_with_root_token "${pod_index}"
  enable_audit_logging "${pod_index}"
done

log "INFO" "Enabling 'secret/' KV-V2 Secret Engine"
exec_in_vault_pod 0 vault secrets enable --version=2 --path=secret kv
check_command_status "vault secrets enable"
}

# Execute main function
main
