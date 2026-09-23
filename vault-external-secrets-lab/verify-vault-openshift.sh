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
# shellcheck source=../lib/vault.sh
source "${SCRIPT_DIR}/../lib/vault.sh"

setup_error_trap

readonly VAULT_NAMESPACE="${VAULT_NAMESPACE:-vault}"
readonly DEMO_NAMESPACE="${DEMO_NAMESPACE:-demo}"
readonly ESO_NAMESPACE="${ESO_NAMESPACE:-external-secrets}"
readonly ESO_OPERATOR_NAMESPACE="${ESO_OPERATOR_NAMESPACE:-external-secrets-operator}"

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
    debug "Verifying External Secrets Operator operand pods are running..."
    local pod_count
    pod_count=$("${OC}" get pods -n "${ESO_NAMESPACE}" --no-headers 2>/dev/null | grep -c Running || echo 0)
    if [[ "${pod_count}" -lt 1 ]]; then
        log "ERROR" "External Secrets Operator operand pods are not running in ${ESO_NAMESPACE}."
        exit 1
    fi
    log "SUCCESS" "External Secrets Operator operand pods are running (${pod_count} pods)."
    echo "$ ${OC} get pods -n ${ESO_NAMESPACE}"
    "${OC}" get pods -n "${ESO_NAMESPACE}"
}

# Validates the OLM-managed operator: Subscription, CSV, ExternalSecretsConfig, and operator pod.
function verify_olm_operator() {
    debug "Verifying OLM operator resources..."

    debug "Checking Subscription..."
    if ! "${OC}" get subscription openshift-external-secrets-operator -n "${ESO_OPERATOR_NAMESPACE}" &> /dev/null; then
        log "ERROR" "OLM Subscription not found in ${ESO_OPERATOR_NAMESPACE}."
        exit 1
    fi
    log "SUCCESS" "OLM Subscription exists."
    echo "$ ${OC} get subscription -n ${ESO_OPERATOR_NAMESPACE}"
    "${OC}" get subscription -n "${ESO_OPERATOR_NAMESPACE}"

    debug "Checking CSV phase..."
    local csv_phase
    csv_phase=$("${OC}" get csv -n "${ESO_OPERATOR_NAMESPACE}" \
        -l operators.coreos.com/openshift-external-secrets-operator.external-secrets-operator \
        -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo "")
    if [[ "${csv_phase}" == "Succeeded" ]]; then
        log "SUCCESS" "CSV phase is Succeeded."
    else
        log "WARNING" "CSV phase is '${csv_phase:-unknown}' (expected Succeeded)."
    fi
    echo "$ ${OC} get csv -n ${ESO_OPERATOR_NAMESPACE}"
    "${OC}" get csv -n "${ESO_OPERATOR_NAMESPACE}"

    debug "Checking operator pod..."
    local operator_pod_count
    operator_pod_count=$("${OC}" get pods -n "${ESO_OPERATOR_NAMESPACE}" --no-headers 2>/dev/null | grep -c Running || echo 0)
    if [[ "${operator_pod_count}" -lt 1 ]]; then
        log "ERROR" "Operator pod is not running in ${ESO_OPERATOR_NAMESPACE}."
        exit 1
    fi
    log "SUCCESS" "Operator pod is running in ${ESO_OPERATOR_NAMESPACE}."
    echo "$ ${OC} get pods -n ${ESO_OPERATOR_NAMESPACE}"
    "${OC}" get pods -n "${ESO_OPERATOR_NAMESPACE}"

    debug "Checking ExternalSecretsConfig status..."
    local esc_ready
    esc_ready=$("${OC}" get externalsecretsconfig cluster \
        -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "")
    if [[ "${esc_ready}" == "True" ]]; then
        log "SUCCESS" "ExternalSecretsConfig status is Ready."
    else
        log "WARNING" "ExternalSecretsConfig Ready status is '${esc_ready:-unknown}' (expected True)."
    fi
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
        echo "$ ${OC}" get externalsecret -n "${DEMO_NAMESPACE}" -o jsonpath='{.items[0].status.conditions[?(@.type=="Ready")].reason}{"\n"}'
        "${OC}" get externalsecret -n "${DEMO_NAMESPACE}" -o jsonpath='{.items[0].status.conditions[?(@.type=="Ready")].reason}{"\n"}'
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
        echo "$ ${OC}" get secretstore -n "${DEMO_NAMESPACE}" -o jsonpath='{.items[0].status.conditions[?(@.type=="Ready")].reason}{"]n"}'
        "${OC}" get secretstore -n "${DEMO_NAMESPACE}" -o jsonpath='{.items[0].status.conditions[?(@.type=="Ready")].reason}{"\n"}'
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

    if ! vault_exec "vault policy read demo" &> /dev/null; then
        log "ERROR" "Vault policy 'demo' does not exist."
        exit 1
    fi
    log "SUCCESS" "Vault policy 'demo' exists."
    echo "$ ${OC} exec -n ${VAULT_NAMESPACE} -i pods/vault-0 -- sh -c 'vault policy read demo'"
    vault_exec "vault policy read demo"

    if ! vault_exec "vault kv get secret/demo" &> /dev/null; then
        log "ERROR" "Vault secret 'secret/demo' does not exist."
        exit 1
    fi
    log "SUCCESS" "Vault secret 'secret/demo' exists."
    echo "$ ${OC} exec -n ${VAULT_NAMESPACE} -i pods/vault-0 -- sh -c 'vault kv get secret/demo'"
    vault_exec "vault kv get secret/demo"

    if ! vault_exec "vault auth list | grep -q approle" &> /dev/null; then
        log "ERROR" "Vault auth method 'approle' is not enabled."
        exit 1
    fi
    log "SUCCESS" "Vault auth method 'approle' is enabled."
    echo "$ ${OC} exec -n ${VAULT_NAMESPACE} -i pods/vault-0 -- sh -c 'vault auth list | grep -q approle'"
    vault_exec "vault auth list | grep -q approle"
}

function main() {
    check_command "jq"
    check_command "oc"
    check_command "curl"

    readonly APPROLE_SECRET="approle-vault"
    readonly DEMO_SECRET="demo"
    VAULT_URL="https://$("${OC}" get routes.route.openshift.io vault -n "${VAULT_NAMESPACE}" -o jsonpath='{.spec.host}')"
    readonly VAULT_URL

    debug "JQ path: ${JQ}"
    debug "OC path: ${OC}"
    debug "APPROLE_SECRET: ${APPROLE_SECRET}"
    debug "DEMO_SECRET: ${DEMO_SECRET}"
    debug "VAULT_URL: ${VAULT_URL}"

    validate_env VAULT_URL APPROLE_SECRET

    verify_vault
    verify_vault_objects
    verify_olm_operator
    verify_external_secrets_operator
    verify_external_secrets
    verify_secret_stores
    verify_approle_secret
    verify_demo_secret

    log "SUCCESS" "All verifications completed successfully."
}

main
