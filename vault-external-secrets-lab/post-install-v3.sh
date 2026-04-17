#!/bin/bash
set -euo pipefail
#
# Post-install for the Vault + External Secrets Operator lab: prepares demo data and wiring so ESO
# can authenticate to Vault and sync into OpenShift. In order: seed KV secrets, enable AppRole and
# bind a policy/role, mint RoleID/SecretID, store those credentials (plus metadata ESO needs) in an
# OpenShift Secret, then apply SecretStore and ExternalSecret manifests.
#

DEBUG="${DEBUG:-false}"
TRACE="${TRACE:-false}"

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

readonly VAULT_NAMESPACE="${VAULT_NAMESPACE:-vault}"
readonly DEMO_NAMESPACE="${DEMO_NAMESPACE:-demo}"
readonly ESO_NAMESPACE="${ESO_NAMESPACE:-external-secrets}"

function vault_exec() {
    local cmd="${1}"
    debug "Executing Vault command: ${cmd}"

    "${OC}" exec -n "${VAULT_NAMESPACE}" -i pods/vault-0 -- sh -c "${cmd}"
}

# Function to check if a command exists
function check_command() {
    local cmd="${1}"
    if ! command -v "${cmd}" &> /dev/null; then
        log "ERROR" "Command '${cmd}' not found. Please install it."
        exit 1
    fi
    debug "Command '${cmd}' is available."
    local UPPER_CMD=$(echo "${cmd}" | sed 's/.*/\U&/')
    readonly "${UPPER_CMD}"=$(command -v "${cmd}")
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
}

# Create the target namespace if it does not already exist.
# Prefer `oc create namespace` over `oc new-project`: the latter updates kubeconfig, which fails when
# the config is read-only (typical in init containers or CI runners).
function create_namespace() {
    local namespace="${1}"
    if ! "${OC}" get namespace "${namespace}" -o jsonpath='{.metadata.name}' &> /dev/null; then
        log "INFO" "Creating namespace: ${namespace}"
        "${OC}" create namespace "${namespace}"
    else
        debug "Namespace '${namespace}' already exists."
    fi
}

# Materialize AppRole responses into a Kubernetes Secret: ESO's Vault provider expects literal keys
# (mount-type, role-id, secret-id, …) matching what the SecretStore references—not raw JSON blobs.
function create_secret() {
    local secret_name="${1}"
    local namespace="${2}"
    local role_id_payload="${3}"
    local secret_id_payload="${4}"

    # From role-id response: mount_type + data.role_id. From secret-id response: data.secret_id and
    # accessor/TTL/num_uses metadata for auditing and optional ESO tuning.
    local mount_type=$(echo "${role_id_payload}" | "${JQ}" -r '.mount_type')
    local role_id=$(echo "${role_id_payload}" | "${JQ}" -r '.data.role_id')
    local secret_id=$(echo "${secret_id_payload}" | "${JQ}" -r '.data.secret_id')
    local secret_id_accessor=$(echo "${secret_id_payload}" | "${JQ}" -r '.data.secret_id_accessor')
    local secret_id_num_uses=$(echo "${secret_id_payload}" | "${JQ}" -r '.data.secret_id_num_uses')
    local secret_id_ttl=$(echo "${secret_id_payload}" | "${JQ}" -r '.data.secret_id_ttl')

    # Debug: Print parsed values
    debug "Parsed Values:"
    debug "Mount Type: ${mount_type}"
    debug "Role ID: ${role_id}"
    debug "Secret ID: ${secret_id}"
    debug "Secret ID Accessor: ${secret_id_accessor}"
    debug "Secret ID Num Uses: ${secret_id_num_uses}"
    debug "Secret ID TTL: ${secret_id_ttl}"

    if [[ -z "${role_id}" || -z "${secret_id}" ]]; then
        log "ERROR" "Failed to extract Role ID or Secret ID. Check Vault response."
        exit 1
    fi

    # Create the secret (use apply to handle existing secrets gracefully)
    log "INFO" "Creating secret '${secret_name}' in namespace '${namespace}'..."
    if "${OC}" get secret "${secret_name}" -n "${namespace}" >/dev/null 2>&1; then
        log "INFO" "Secret '${secret_name}' already exists, updating..."
        "${OC}" delete secret "${secret_name}" -n "${namespace}" || true
    fi
    "${OC}" create secret generic "${secret_name}" \
        --from-literal=mount-type="${mount_type}" \
        --from-literal=role-id="${role_id}" \
        --from-literal=secret-id="${secret_id}" \
        --from-literal=secret-id-accessor="${secret_id_accessor}" \
        --from-literal=secret-id-num-uses="${secret_id_num_uses}" \
        --from-literal=secret-id-ttl="${secret_id_ttl}" \
        -n "${namespace}" || {
            log "ERROR" "Failed to create secret '${secret_name}'."
            exit 1
        }

    debug "Secret '${secret_name}' created successfully."
}

# Parameterize the OpenShift template with the Vault route and Secret name, then apply so the
# cluster reconciles SecretStore/ExternalSecret without hand-editing YAML per environment.
function apply_manifests() {
    local approle_secret="${1}"
    local vault_url="${2}"

    log "INFO" "Applying SecretStore and ExternalSecret manifests..."
    # Check if SecretStore/ExternalSecret already exist (informational)
    if "${OC}" get secretstore -n "${DEMO_NAMESPACE}" 2>/dev/null | grep -q vault; then
        log "INFO" "SecretStore already exists, will be updated..."
    fi
    if "${OC}" get externalsecret -n "${DEMO_NAMESPACE}" 2>/dev/null | grep -q demo; then
        log "INFO" "ExternalSecret already exists, will be updated..."
    fi
    # Use oc apply which is idempotent
    # Explicitly target the demo namespace (oc create namespace does not switch context)
    if "${OC}" process -f manifests/sandbox-vault-external-secrets-template.yaml \
        -p APPROLE_SECRET="${approle_secret}" \
        -p VAULT_URL="${vault_url}" -o yaml | "${OC}" apply -n "${DEMO_NAMESPACE}" --wait=true -f -; then
        debug "Manifests applied successfully."
    else
        log "ERROR" "Failed to apply manifests."
        exit 1
    fi
}

# Flow: prerequisites → KV + AppRole + policy/role → fetch JSON from Vault (CLI in pod) → jq on host
# → namespace + credential Secret → template apply for ESO CRs.
function main() {
    # Ensure required commands are installed
    check_command "jq"
    check_command "oc"

    # Define variables
    readonly APPROLE_SECRET="approle-vault"
    readonly VAULT_URL=$("${OC}" get routes.route.openshift.io vault -n "${VAULT_NAMESPACE}" -o jsonpath='{.spec.host}')

    # Debugging information
    debug "JQ path: ${JQ}"
    debug "OC path: ${OC}"
    debug "APPROLE_SECRET: ${APPROLE_SECRET}"
    debug "VAULT_URL: ${VAULT_URL}"

    # Validate environment variables
    validate_env

    # Create 'secret/demo' secret
    log "INFO" "Creating 'secret/demo' secret..."
    vault_exec "vault kv put secret/demo Hello='World!' foo=bar Red_Hat=Linux"

    # Enable AppRole Auth Method (idempotent - won't fail if already enabled)
    log "INFO" "Enabling AppRole authentication..."
    vault_exec "vault auth enable approle" 2>/dev/null || {
        if vault_exec "vault auth list" | grep -q "approle/"; then
            log "INFO" "AppRole authentication method already enabled"
        else
            log "ERROR" "Failed to enable AppRole authentication"
            exit 1
        fi
    }

    # Create Vault Policy
    log "INFO" "Creating Vault Policy..."
    vault_exec "vault policy write demo -" <<EOF
path "secret/data/demo" {
    capabilities = ["read"]
}
EOF

    # Create Vault Role
    log "INFO" "Creating Vault Role..."
    # token_num_uses=0 allows unlimited token uses so ESO can refresh on its schedule.
    vault_exec "vault write auth/approle/role/demo \
        token_policies=demo \
        token_type=service \
        token_num_uses=0 \
        token_period=7d \
        token_ttl=7d \
        bind_secret_id=true"

    # Retrieve RoleID and SecretID Payload (without jq inside the container)
    debug "Retrieving RoleID and SecretID Payload..."
    readonly RAW_ROLE_ID_PAYLOAD=$(vault_exec "vault read -format=json auth/approle/role/demo/role-id")
    readonly RAW_SECRET_ID_PAYLOAD=$(vault_exec "vault write -f -format=json auth/approle/role/demo/secret-id")

    # Debug: Print raw JSON payloads
    debug "Raw Role ID Payload: ${RAW_ROLE_ID_PAYLOAD}"
    debug "Raw Secret ID Payload: ${RAW_SECRET_ID_PAYLOAD}"

    # Parse JSON payloads using jq (outside the Vault container)
    readonly ROLE_ID_PAYLOAD=$(echo "${RAW_ROLE_ID_PAYLOAD}" | "${JQ}" -rc '.')
    readonly SECRET_ID_PAYLOAD=$(echo "${RAW_SECRET_ID_PAYLOAD}" | "${JQ}" -rc '.')

    # Debug: Print parsed payloads
    debug "Role ID Payload: ${ROLE_ID_PAYLOAD}"
    debug "Secret ID Payload: ${SECRET_ID_PAYLOAD}"

    # Create 'demo' namespace and secret
    create_namespace "${DEMO_NAMESPACE}"
    create_secret "${APPROLE_SECRET}" "${DEMO_NAMESPACE}" "${ROLE_ID_PAYLOAD}" "${SECRET_ID_PAYLOAD}"

    # Wait for ESO CRDs to be fully available before applying manifests.
    # The ESO operator may still be registering its CRDs after helm install --wait.
    log "INFO" "Waiting for ExternalSecret CRD to be available..."
    local crd_wait=0
    while ! "${OC}" get crd externalsecrets.external-secrets.io &>/dev/null; do
        if (( crd_wait >= 120 )); then
            log "ERROR" "Timeout waiting for ExternalSecret CRD"
            exit 1
        fi
        sleep 3
        crd_wait=$((crd_wait + 3))
    done

    # Apply SecretStore and ExternalSecret manifests
    apply_manifests "${APPROLE_SECRET}" "${VAULT_URL}"

    log "SUCCESS" "Script execution completed."
}

# Execute main function
main
