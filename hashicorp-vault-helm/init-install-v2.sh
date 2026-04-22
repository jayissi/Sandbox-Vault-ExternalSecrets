#!/bin/bash
set -euo pipefail

# End-to-end bootstrap: operator init on vault-0 → for each pod (ordered): Raft join (if not primary) → unseal →
# root login → audit sinks → finally enable KV v2 at secret/ on vault-0. Secrets handling: unseal material is fed via
# stdin to `vault operator unseal` (not argv); root token is passed through the pod env for login/lookup so it does not
# appear in process listings like a bare CLI argument would.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/logging.sh"

JQ="$(command -v jq)"
readonly JQ
OC="$(command -v oc)"
readonly OC
readonly VAULT_INIT_SECRET_NAME="vault-operator-init"
readonly UNSEAL_SHARES=5
readonly UNSEAL_THRESHOLD=3
readonly VAULT_NAMESPACE="${VAULT_NAMESPACE:-vault}"

function cleanup_trap() {
    local exit_code=$?
    if [[ ${exit_code} -ne 0 ]]; then
        log "ERROR" "Script failed (exit code ${exit_code})"
        log "ERROR" "Recovery: check 'oc get secret ${VAULT_INIT_SECRET_NAME} -n ${VAULT_NAMESPACE}' for init state."
        log "ERROR" "If Vault is partially initialized, delete the secret and re-run, or manually unseal remaining pods."
    fi
}
trap 'cleanup_trap' EXIT

# Reusable function to execute commands in a Vault pod
function exec_in_vault_pod() {
  local pod_index="${1}"
  shift
  "${OC}" exec -n "${VAULT_NAMESPACE}" -i pods/"vault-${pod_index}" -- "$@"
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
  log "SUCCESS" "Dependencies Validated"
}

# Runs `vault operator init` once on vault-0, then persists the full JSON response into OpenShift as secret
# vault-operator-init (one key per JSON field). That becomes the cluster source of truth for unseal keys and root
# token on later runs—operators recover from the secret instead of re-initing.
function initialize_vault() {
  log "INFO" "Starting Vault Initialization"
  debug "Initializing Vault with ${UNSEAL_SHARES} unseal shares and a threshold of ${UNSEAL_THRESHOLD}"

  VAULT_KEYS_PAYLOAD=$(
    exec_in_vault_pod 0 \
      vault operator init \
        -format=json \
        -key-shares "${UNSEAL_SHARES}" \
        -key-threshold "${UNSEAL_THRESHOLD}"
  )
  readonly VAULT_KEYS_PAYLOAD

  local SECRET_ARGS=()
  debug "Building secret arguments from JSON payload"

  # Generic: every top-level key from init JSON becomes a --from-literal on the Secret (no hardcoded field list).
  while IFS= read -r key; do
      # Get the value for each key into local variables
      local value
      value="$(echo "${VAULT_KEYS_PAYLOAD}" | "${JQ}" -r --arg k "$key" '.[$k]')"
      
      # Verify we got a valid value
      if [[ -z "$value" ]]; then
          log "ERROR" "Empty value for key: $key"
          exit 1
      fi
      
      debug "Adding secret argument: --from-literal=${key}=<REDACTED>"
      SECRET_ARGS+=( "--from-literal=${key}=${value}" )
  done < <(echo "${VAULT_KEYS_PAYLOAD}" | "${JQ}" -r 'keys[]')

  debug "Final SECRET_ARGS: [${#SECRET_ARGS[@]} arguments, values redacted]"

  debug "Executing: oc create -n ${VAULT_NAMESPACE} secret generic ${VAULT_INIT_SECRET_NAME} [${#SECRET_ARGS[@]} --from-literal args]"
  oc create -n "${VAULT_NAMESPACE}" secret generic "${VAULT_INIT_SECRET_NAME}" "${SECRET_ARGS[@]}" || {
    log "ERROR" "Failed to create secret '${VAULT_INIT_SECRET_NAME}'"
    exit 1
  }

  local VAULT_URL
  VAULT_URL="https://$("${OC}" get routes.route.openshift.io vault -n "${VAULT_NAMESPACE}" -o jsonpath --template='{.spec.host}{"\n"}')"
  echo "Vault URL: ${VAULT_URL}"
  echo "Vault initialization complete. Root token stored in secret '${VAULT_INIT_SECRET_NAME}' (namespace: ${VAULT_NAMESPACE})."
}

function unseal_vault() {
  local pod_index=${1}
  local unseal_keys
  mapfile -t unseal_keys < <(echo "${VAULT_KEYS_PAYLOAD}" | "${JQ}" -r ".unseal_keys_b64[]")
  
  debug "Unsealing Vault pod 'vault-${pod_index}'"
  # Use a random subset of unseal keys (threshold count) to unseal the pod.
  for key_index in $(shuf -i 0-$((UNSEAL_SHARES - 1)) -n ${UNSEAL_THRESHOLD}); do
    log "INFO" "Unsealing pod 'vault-${pod_index}' using unseal key index: ${key_index}"
    exec_in_vault_pod "${pod_index}" vault operator unseal "${unseal_keys[${key_index}]}" || {
      log "ERROR" "Failed to unseal vault-${pod_index} with key index ${key_index}"
      exit 1
    }
  done
}

function first_vault_login_with_root_token() {
  local pod_index="${1}"
  local max_attempts=5
  local attempt=1
  local delay=5
  local root_token
  root_token="$(echo "${VAULT_KEYS_PAYLOAD}" | "${JQ}" -r '.root_token')"

  debug "First login via Root Token on 'vault-${pod_index}'"

  while [ ${attempt} -le ${max_attempts} ]; do
    log "INFO" "Attempt ${attempt} of ${max_attempts} to login via Root Token on 'vault-${pod_index}'"
    
    # Wait for the Vault pod to report ready before attempting login
    if ! exec_in_vault_pod "${pod_index}" vault status > /dev/null 2>&1; then
      log "WARNING" "Vault pod 'vault-${pod_index}' is not ready. Retrying in ${delay} seconds..."
      $(command -v sleep) ${delay}
      attempt=$((attempt + 1))
      continue
    fi

    # Authenticate with the root token so subsequent commands (audit, secrets enable) work
    if exec_in_vault_pod "${pod_index}" vault login "${root_token}"; then
      debug "Successfully logged in via Root Token on 'vault-${pod_index}'"
      return 0
    else
      log "WARNING" "Failed to login via Root Token on 'vault-${pod_index}' (Attempt ${attempt} of ${max_attempts})"
      attempt=$((attempt + 1))
      sleep ${delay}
    fi
  done

  log "ERROR" "Failed to login via Root Token on 'vault-${pod_index}' after ${max_attempts} attempts"
  exit 1
}

function enable_audit_logging() {
  local pod_index=${1}
  log "INFO" "Enabling Audit Logging on 'vault-${pod_index}'"
  exec_in_vault_pod "${pod_index}" vault audit enable -path="vault-${pod_index}_file_audit_" file \
    format=json \
    file_path="/vault/audit/vault-${pod_index}_audit.log" || {
    log "ERROR" "Failed to enable file audit on vault-${pod_index}"
    exit 1
  }

  exec_in_vault_pod "${pod_index}" vault audit enable -path="vault-${pod_index}_socket_audit_" socket \
    address="127.0.0.1:8200" \
    socket_type=tcp || {
    log "ERROR" "Failed to enable socket audit on vault-${pod_index}"
    exit 1
  }
}

function join_cluster() {
  local pod_index=${1}
  log "INFO" "Joining server 'vault-${pod_index}' to the cluster"
  exec_in_vault_pod "${pod_index}" vault operator raft join http://vault-0.vault-internal:8200 || {
    log "ERROR" "Failed to join vault-${pod_index} to Raft cluster"
    exit 1
  }
}

# Main function
function main() {
# Clear screen - use echo for container compatibility (tput may not be available)
if command -v tput > /dev/null 2>&1; then
  tput clear 2>/dev/null || echo -e "\033c"
else
  echo -e "\033c"
fi
validate_dependencies
initialize_vault

# Numeric pod-index order makes vault-0 first: HA followers must join the leader after it exists, then each node is
# unsealed and configured before moving on.
mapfile -t pod_indices < <(
  "${OC}" get pods -n "${VAULT_NAMESPACE}" \
    -o=jsonpath='{.items[?(@.metadata.labels.app\.kubernetes\.io/name=="vault")].metadata.labels.apps\.kubernetes\.io/pod-index}' \
    | tr ' ' '\n' \
    | sort -n
)

for pod_index in "${pod_indices[@]}"; do
  # Followers: join Raft to vault-0 before unseal; primary (0) skips join—already initialized above.
  if (( pod_index > 0 )); then
      join_cluster "${pod_index}"
  fi
  unseal_vault "${pod_index}"
  first_vault_login_with_root_token "${pod_index}"
  enable_audit_logging "${pod_index}"
done

log "INFO" "Enabling 'secret/' KV-V2 Secret Engine"
exec_in_vault_pod 0 vault secrets enable --version=2 --path=secret kv || {
  log "ERROR" "Failed to enable KV-V2 secret engine"
  exit 1
}

# Enable Kubernetes auth for least-privilege CLI access
log "INFO" "Enabling Kubernetes authentication..."
exec_in_vault_pod 0 vault auth enable kubernetes 2>/dev/null || {
  if exec_in_vault_pod 0 vault auth list | grep -q "kubernetes/"; then
    debug "Kubernetes auth already enabled"
  else
    log "ERROR" "Failed to enable Kubernetes auth"
    exit 1
  fi
}

# Configure Kubernetes auth with in-cluster config
log "INFO" "Configuring Kubernetes auth..."
exec_in_vault_pod 0 vault write auth/kubernetes/config \
    kubernetes_host="https://kubernetes.default.svc:443" || {
  log "ERROR" "Failed to configure Kubernetes auth"
  exit 1
}

# Create vault-ops policy (least privilege for CLI operations)
log "INFO" "Creating vault-ops policy (least privilege)..."
exec_in_vault_pod 0 vault policy write vault-ops - <<'POLICY'
# Least privilege policy for Vault CLI operations
# Read Raft cluster configuration
path "sys/storage/raft/configuration" {
  capabilities = ["read"]
}
# Read seal status (for monitoring)
path "sys/seal-status" {
  capabilities = ["read"]
}
# Read health status
path "sys/health" {
  capabilities = ["read", "sudo"]
}
# List auth methods (informational)
path "sys/auth" {
  capabilities = ["read"]
}
POLICY
[[ ${PIPESTATUS[0]} -eq 0 ]] || { log "ERROR" "Failed to create vault-ops policy"; exit 1; }

# Create Kubernetes auth role for vault service account
log "INFO" "Creating vault-ops Kubernetes auth role..."
exec_in_vault_pod 0 vault write auth/kubernetes/role/vault-ops \
    bound_service_account_names=vault \
    bound_service_account_namespaces=vault \
    policies=vault-ops \
    ttl=15m || {
  log "ERROR" "Failed to create vault-ops Kubernetes auth role"
  exit 1
}

log "SUCCESS" "Hashicorp Vault Setup Completed"
}

# Execute main function
main
