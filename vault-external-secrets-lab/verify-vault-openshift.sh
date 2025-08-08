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
    TRACE) color="${BLUE}" ;;
    *) color="${RESET}" ;; # Default color for unknown levels
  esac

  printf "%b%s\n⎈ %s%s%s ⎈\n%s%b\n" "${BLUE}" "${border}" "${padding}" "${message}" "${padding}" "${border}" "${WHITE}" >&2
  printf "%b[%s] [%s]%b\n" "${color}" "${timestamp}" "${level}" "${RESET}" >&2
}

# Debug logging function
function debug() {
    local message="${1}"
    if ${DEBUG}; then
        log "DEBUG" "${message}" >&2
    fi
}

# Trace logging function
function trace() {
    local message="${1}"
    if ${DEBUG} && ${TRACE}; then
        log "TRACE" "${message}" >&2
    fi
}

# Function to handle errors and exit gracefully
function trap_handler() {
    local exit_code=${?}
    local line_number="${1}"
    local command="${2}"
    if [[ ${exit_code} -ne 0 ]]; then
        log "ERROR" "Script failed at line ${line_number}: '${command}' with exit code ${exit_code}."
        exit ${exit_code}
    fi
}

# Set trap for error handling
trap 'trap_handler ${LINENO} "$BASH_COMMAND"' ERR

# Function to execute Vault commands
function vault_exec() {
    local cmd="${1}"
    debug "Executing Vault command: ${cmd}"

    # Execute the command inside the Vault container and capture output
    "${OC}" exec -n vault -i pods/vault-0 -- sh -c "${cmd}"
}

# Function to check if a command exists
function check_command() {
    local cmd="${1}"
    if ! command -v "${cmd}" &> /dev/null; then
        log "ERROR" "Command '${cmd}' not found. Please install it."
        exit 1
    fi
    log "SUCCESS" "Command '${cmd}' is available."
    echo "$ command -v ${cmd}"
    command -v "${cmd}"
}

# Function to validate environment variables
function validate_env() {
    local required_vars=("VAULT_URL" "APPROLE_SECRET")
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            log "ERROR" "Environment variable ${var} is not set."
            exit 1
        fi
    done
    log "SUCCESS" "All required environment variables are set."
    echo "${required_vars[@]}"
}

# Function to verify Vault is running and its URL is responding
function verify_vault() {
    debug "Verifying Vault is running and its URL is responding..."
    if ! curl -k -s --head --fail "${VAULT_URL}" &> /dev/null; then
        log "ERROR" "Vault URL '${VAULT_URL}' is not responding."
        exit 1
    fi
    log "SUCCESS" "Vault is running and its URL is responding."
    echo "$ curl -k -s -L -o /dev/null -w \"%{http_code}\n\"--head --fail ${VAULT_URL}"
    curl -k -s -L -o /dev/null -w "%{http_code}\n" --head --fail "${VAULT_URL}"

}

# Function to verify External Secrets Operator is installed and pods are running
function verify_external_secrets_operator() {
    debug "Verifying External Secrets Operator is installed and pods are running..."
    if ! "${OC}" get pods -n external-secrets -l app.kubernetes.io/name=external-secrets &> /dev/null; then
        log "ERROR" "External Secrets Operator is not installed or pods are not running."
        exit 1
    fi
    log "SUCCESS" "External Secrets Operator is installed and pods are running."
    echo "$ ${OC} get pods -n external-secrets -l app.kubernetes.io/name=external-secrets"
    "${OC}" get pods -n external-secrets -l app.kubernetes.io/name=external-secrets
}

# Function to verify External Secrets
function verify_external_secrets() {
    debug "Verifying External Secrets and Secret Store are working..."
    if ! "${OC}" get externalsecret -n demo &> /dev/null; then
        log "ERROR" "External Secrets is not ready."
        exit 1
    fi
    log "SUCCESS" "External Secrets is Ready."
    echo "$ ${OC} get externalsecret -n demo"
    "${OC}" get externalsecret -n demo
}

# Function to verify Secret Stores
function verify_secret_stores() {
    debug "Verifying Secret Stores..."
    if ! "${OC}" get secretstore -n demo &> /dev/null; then
        log "ERROR" "Secret Stores is not ready."
        exit 1
    fi
    log "SUCCESS" "Secret Stores is Ready."
    echo "$ ${OC} get secretstore -n demo"
    "${OC}" get secretstore -n demo
}

# Function to verify the created secret is available
function verify_approle_secret() {
    debug "Verifying the created secret is available..."
    local approle_vault_secret="${APPROLE_SECRET}"
    if ! "${OC}" get secret "${approle_vault_secret}" -n demo &> /dev/null; then
        log "ERROR" "Secret '${approle_vault_secret}' is not available."
        exit 1
    fi
    log "SUCCESS" "Secret '${approle_vault_secret}' is available."
    echo "$ ${OC} get secret ${approle_vault_secret} -n demo"
    "${OC}" get secret "${approle_vault_secret}" -n demo

    # Base64 decode the secret content
    debug "Decoding the '${approle_vault_secret}' secret content..."
    local secret_content
    secret_content=$("${OC}" get secret "${approle_vault_secret}" -n demo -o jsonpath='{.data}' | "${JQ}" -r 'to_entries[] | "\(.key): \(.value | @base64d)"')
    debug "Decoded secret content: ${secret_content}"
    echo "$ ${OC} get secret ${approle_vault_secret} -n demo -o jsonpath='{.data}' | ${JQ} -r 'to_entries[] | \"\(.key): \(.value | @base64d)\"'"
    echo "${secret_content}"
}

# Function to verify the created secret is available
function verify_demo_secret() {
    debug "Verifying the created secret is available..."
    local demo_vault_secret="${DEMO_SECRET}"
    if ! "${OC}" get secret "${demo_vault_secret}" -n demo &> /dev/null; then
        log "ERROR" "Secret '${demo_vault_secret}' is not available."
        exit 1
    fi
    log "SUCCESS" "Secret '${demo_vault_secret}' is available."
    echo "$ ${OC} get secret ${demo_vault_secret} -n demo"
    "${OC}" get secret "${demo_vault_secret}" -n demo

    # Base64 decode the secret content
    debug "Decoding the ${demo_vault_secret}' secret content..."
    local secret_content
    secret_content=$("${OC}" get secret "${demo_vault_secret}" -n demo -o jsonpath='{.data}' | "${JQ}" -r 'to_entries[] | "\(.key): \(.value | @base64d)"')
    debug "Decoded secret content: ${secret_content}"
    echo "$ ${OC} get secret ${demo_vault_secret} -n demo -o jsonpath='{.data}' | ${JQ} -r 'to_entries[] | \"\(.key): \(.value | @base64d)\"'"
    echo "${secret_content}"
}

# Function to verify Vault objects (policy, secret, and auth method)
function verify_vault_objects() {
    debug "Verifying Vault objects (policy, secret, and auth method)..."

    # Verify policy
    if ! vault_exec "vault policy read demo" &> /dev/null; then
        log "ERROR" "Vault policy 'demo' does not exist."
        exit 1
    fi
    log "SUCCESS" "Vault policy 'demo' exists."
    echo "$ ${OC} exec -n vault -i pods/vault-0 -- sh -c 'vault policy read demo'"
    vault_exec "vault policy read demo"

    # Verify secret
    if ! vault_exec "vault kv get secret/demo" &> /dev/null; then
        log "ERROR" "Vault secret 'secret/demo' does not exist."
        exit 1
    fi
    log "SUCCESS" "Vault secret 'secret/demo' exists."
    echo "$ ${OC} exec -n vault -i pods/vault-0 -- sh -c 'vault kv get secret/demo'"
    vault_exec "vault kv get secret/demo"

    # Verify auth method
    if ! vault_exec "vault auth list | grep -q approle" &> /dev/null; then
        log "ERROR" "Vault auth method 'approle' is not enabled."
        exit 1
    fi
    log "SUCCESS" "Vault auth method 'approle' is enabled."
    echo "$ ${OC} exec -n vault -i pods/vault-0 -- sh -c 'vault auth list | grep -q approle'"
    vault_exec "vault auth list | grep -q approle"
}

# Main function
function main() {
    # Ensure required commands are installed
    check_command "jq"
    check_command "oc"
    check_command "curl"

    # Define variables
    readonly JQ=$(command -v jq)
    readonly OC=$(command -v oc)
    readonly APPROLE_SECRET="approle-vault"
    readonly DEMO_SECRET="demo"
    readonly VAULT_URL="https://$("${OC}" get routes.route.openshift.io vault -n vault -o jsonpath='{.spec.host}')"

    # Debugging information
    debug "JQ path: ${JQ}"
    debug "OC path: ${OC}"
    debug "APPROLE_SECRET: ${APPROLE_SECRET}"
    debug "DEMO_SECRET: ${DEMO_SECRET}"
    debug "VAULT_URL: ${VAULT_URL}"

    # Validate environment variables
    validate_env

    # Verify Vault is running and its URL is responding
    verify_vault

    # Verify Vault objects (policy, secret, and auth method)
    verify_vault_objects

    # Verify External Secrets Operator is installed and pods are running
    verify_external_secrets_operator

    # Verify External Secrets
    verify_external_secrets

    # Verify Secret Stores
    verify_secret_stores

    # Verify the created approle secret
    verify_approle_secret

    # Verify the created demo secret
    verify_demo_secret

    log "SUCCESS" "All verifications completed successfully."
}

# Execute main function
main
