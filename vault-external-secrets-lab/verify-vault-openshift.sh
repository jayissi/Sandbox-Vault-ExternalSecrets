#!/bin/bash
set -euo pipefail
#
# End-to-end smoke test: Vault is serving and configured like post-install, External Secrets Operator
# is running, SecretStore/ExternalSecret reconcile, the AppRole bootstrap Secret exists, and the
# demo Secret reflects Vault → ESO → Kubernetes.
#
# Intended to run wherever `oc` points (admin laptop, jump host, or a container with kubeconfig
# mounted)—behavior is identical; only the filesystem path to credentials differs.
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/logging.sh"

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

# Function to execute Vault commands
function vault_exec() {
    local cmd="${1}"
    debug "Executing Vault command: ${cmd}"

    # Execute the command inside the Vault container and capture output
    "${OC}" exec -n "${VAULT_NAMESPACE}" -i pods/vault-0 -- sh -c "${cmd}"
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

# Fail fast if the Vault route is down—later checks would be noise without a healthy API.
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

# ESO must be scheduled before any ExternalSecret can sync; this catches a missing install early.
function verify_external_secrets_operator() {
    debug "Verifying External Secrets Operator is installed and pods are running..."
    if ! "${OC}" get pods -n "${ESO_NAMESPACE}" -l app.kubernetes.io/name=external-secrets &> /dev/null; then
        log "ERROR" "External Secrets Operator is not installed or pods are not running."
        exit 1
    fi
    log "SUCCESS" "External Secrets Operator is installed and pods are running."
    echo "$ ${OC} get pods -n ${ESO_NAMESPACE} -l app.kubernetes.io/name=external-secrets"
    "${OC}" get pods -n "${ESO_NAMESPACE}" -l app.kubernetes.io/name=external-secrets
}

# Confirms the ExternalSecret CR exists and its status is SecretSynced.
function verify_external_secrets() {
    debug "Verifying External Secrets and Secret Store are working..."
    if ! "${OC}" get externalsecret -n "${DEMO_NAMESPACE}" &> /dev/null; then
        log "ERROR" "External Secrets is not ready."
        exit 1
    fi
    log "SUCCESS" "External Secrets CR exists."
    echo "$ ${OC} get externalsecret -n ${DEMO_NAMESPACE}"
    "${OC}" get externalsecret -n "${DEMO_NAMESPACE}"

    local sync_status
    sync_status=$("${OC}" get externalsecret -n "${DEMO_NAMESPACE}" -o jsonpath='{.items[0].status.conditions[?(@.type=="Ready")].reason}' 2>/dev/null || echo "")
    if [[ "${sync_status}" == "SecretSynced" ]]; then
        log "SUCCESS" "ExternalSecret status is SecretSynced."
    else
        log "WARNING" "ExternalSecret status is '${sync_status:-unknown}' (expected SecretSynced)."
    fi
}

# Confirms the SecretStore CR exists and its status is Valid.
function verify_secret_stores() {
    debug "Verifying Secret Stores..."
    if ! "${OC}" get secretstore -n "${DEMO_NAMESPACE}" &> /dev/null; then
        log "ERROR" "Secret Stores is not ready."
        exit 1
    fi
    log "SUCCESS" "Secret Stores CR exists."
    echo "$ ${OC} get secretstore -n ${DEMO_NAMESPACE}"
    "${OC}" get secretstore -n "${DEMO_NAMESPACE}"

    local store_status
    store_status=$("${OC}" get secretstore -n "${DEMO_NAMESPACE}" -o jsonpath='{.items[0].status.conditions[?(@.type=="Ready")].reason}' 2>/dev/null || echo "")
    if [[ "${store_status}" == "Valid" ]]; then
        log "SUCCESS" "SecretStore status is Valid."
    else
        log "WARNING" "SecretStore status is '${store_status:-unknown}' (expected Valid)."
    fi
}

# Validates post-install wrote the AppRole credential Secret ESO's SecretStore references.
function verify_approle_secret() {
    debug "Verifying the created secret is available..."
    local approle_vault_secret="${APPROLE_SECRET}"
    if ! "${OC}" get secret "${approle_vault_secret}" -n "${DEMO_NAMESPACE}" &> /dev/null; then
        log "ERROR" "Secret '${approle_vault_secret}' is not available."
        exit 1
    fi
    log "SUCCESS" "Secret '${approle_vault_secret}' is available."
    echo "$ ${OC} get secret ${approle_vault_secret} -n ${DEMO_NAMESPACE}"
    "${OC}" get secret "${approle_vault_secret}" -n "${DEMO_NAMESPACE}"

    echo " "

    # Verify secret has expected keys without printing values
    debug "Checking key count for '${approle_vault_secret}'..."
    local key_count
    key_count=$("${OC}" get secret "${approle_vault_secret}" -n "${DEMO_NAMESPACE}" -o jsonpath='{.data}' | "${JQ}" 'keys | length')
    if [[ "${key_count}" -lt 1 ]]; then
        log "ERROR" "Secret '${approle_vault_secret}' has no data keys."
        exit 1
    fi
    log "SUCCESS" "Secret '${approle_vault_secret}' contains ${key_count} key(s)."
    echo "$ ${OC} get secret ${approle_vault_secret} -n ${DEMO_NAMESPACE} -o jsonpath='{.data}' | ${JQ} 'keys'"
    "${OC}" get secret "${approle_vault_secret}" -n "${DEMO_NAMESPACE}" -o jsonpath='{.data}' | "${JQ}" 'keys'
}

# Validates the synced demo Secret—the proof that Vault data reached the cluster via ESO.
function verify_demo_secret() {
    debug "Verifying the created secret is available..."
    local demo_vault_secret="${DEMO_SECRET}"
    if ! "${OC}" get secret "${demo_vault_secret}" -n "${DEMO_NAMESPACE}" &> /dev/null; then
        log "ERROR" "Secret '${demo_vault_secret}' is not available."
        exit 1
    fi
    log "SUCCESS" "Secret '${demo_vault_secret}' is available."
    echo "$ ${OC} get secret ${demo_vault_secret} -n ${DEMO_NAMESPACE}"
    "${OC}" get secret "${demo_vault_secret}" -n "${DEMO_NAMESPACE}"

    echo " "

    # Verify secret has expected keys without printing values
    debug "Checking key count for '${demo_vault_secret}'..."
    local key_count
    key_count=$("${OC}" get secret "${demo_vault_secret}" -n "${DEMO_NAMESPACE}" -o jsonpath='{.data}' | "${JQ}" 'keys | length')
    if [[ "${key_count}" -lt 1 ]]; then
        log "ERROR" "Secret '${demo_vault_secret}' has no data keys."
        exit 1
    fi
    log "SUCCESS" "Secret '${demo_vault_secret}' contains ${key_count} key(s)."
    echo "$ ${OC} get secret ${demo_vault_secret} -n ${DEMO_NAMESPACE} -o jsonpath='{.data}' | ${JQ} 'keys'"
    "${OC}" get secret "${demo_vault_secret}" -n "${DEMO_NAMESPACE}" -o jsonpath='{.data}' | "${JQ}" 'keys'
}

# Cross-checks server-side Vault state (policy, KV path, AppRole) independent of Kubernetes.
function verify_vault_objects() {
    debug "Verifying Vault objects (policy, secret, and auth method)..."

    # Verify policy
    if ! vault_exec "vault policy read demo" &> /dev/null; then
        log "ERROR" "Vault policy 'demo' does not exist."
        exit 1
    fi
    log "SUCCESS" "Vault policy 'demo' exists."
    echo "$ ${OC} exec -n ${VAULT_NAMESPACE} -i pods/vault-0 -- sh -c 'vault policy read demo'"
    vault_exec "vault policy read demo"

    # Verify secret
    if ! vault_exec "vault kv get secret/demo" &> /dev/null; then
        log "ERROR" "Vault secret 'secret/demo' does not exist."
        exit 1
    fi
    log "SUCCESS" "Vault secret 'secret/demo' exists."
    echo "$ ${OC} exec -n ${VAULT_NAMESPACE} -i pods/vault-0 -- sh -c 'vault kv get secret/demo'"
    vault_exec "vault kv get secret/demo"

    # Verify auth method
    if ! vault_exec "vault auth list | grep -q approle" &> /dev/null; then
        log "ERROR" "Vault auth method 'approle' is not enabled."
        exit 1
    fi
    log "SUCCESS" "Vault auth method 'approle' is enabled."
    echo "$ ${OC} exec -n ${VAULT_NAMESPACE} -i pods/vault-0 -- sh -c 'vault auth list | grep -q approle'"
    vault_exec "vault auth list | grep -q approle"
}

# Main function
function main() {
    # Ensure required commands are installed
    check_command "jq"
    check_command "oc"
    check_command "curl"

    # Define variables
    JQ=$(command -v jq)
    readonly JQ
    OC=$(command -v oc)
    readonly OC
    readonly APPROLE_SECRET="approle-vault"
    readonly DEMO_SECRET="demo"
    VAULT_URL="https://$("${OC}" get routes.route.openshift.io vault -n "${VAULT_NAMESPACE}" -o jsonpath='{.spec.host}')"
    readonly VAULT_URL

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
