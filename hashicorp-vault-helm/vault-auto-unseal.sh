#!/bin/bash
# Sidecar script: monitors Vault seal status and auto-unseals using keys from k8s secret.
# Runs continuously alongside Vault container, checking seal status at regular intervals.
# When Vault is initialized but sealed, reads unseal keys from mounted secret and applies them.
#
# Authentication Strategy (Least Privilege):
# 1. Primary: Kubernetes Auth with vault-ops role (limited to sys/raft, sys/health)
# 2. Fallback: Root token (only used during initial setup before K8s auth is configured)
#
# Note: This script is provided as a reference. The actual sidecar uses an inline version
# in values.auto-unseal.yaml. The sidecar mounts the Vault Helm chart's existing 'home'
# emptyDir volume at /home/vault, sharing it with the Vault container.
set -uo pipefail

VAULT_ADDR="${VAULT_ADDR:-http://127.0.0.1:8200}"
CHECK_INTERVAL="${CHECK_INTERVAL:-10}"
UNSEAL_THRESHOLD="${UNSEAL_THRESHOLD:-3}"
UNSEAL_KEYS_FILE="${UNSEAL_KEYS_FILE:-/vault-unseal/unseal_keys_b64}"
ROOT_TOKEN_FILE="${ROOT_TOKEN_FILE:-/vault-unseal/root_token}"
SHARED_TOKEN_FILE="${SHARED_TOKEN_FILE:-/home/vault/.vault-token}"
SA_TOKEN_PATH="/var/run/secrets/kubernetes.io/serviceaccount/token"
K8S_AUTH_ROLE="${K8S_AUTH_ROLE:-vault-ops}"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [auto-unseal] $1"
}

json_get() {
    python3 -c "import sys,json; print(json.load(sys.stdin).get('$1','${2:-}'))" 2>/dev/null
}

wait_for_vault() {
    local max_wait="${VAULT_READY_TIMEOUT:-300}"
    local elapsed=0
    log "Waiting for Vault to become available (timeout: ${max_wait}s)..."
    while [[ $elapsed -lt $max_wait ]]; do
        if curl -s -o /dev/null -w "%{http_code}" "${VAULT_ADDR}/v1/sys/health" 2>/dev/null | grep -qE "^(200|429|472|473|501|503)$"; then
            log "Vault is available"
            return 0
        fi
        sleep 2
        elapsed=$((elapsed + 2))
    done
    log "ERROR: Vault did not become available within ${max_wait}s"
    return 1
}

login_with_k8s_auth() {
    if [[ ! -f "$SA_TOKEN_PATH" ]]; then
        log "Service account token not found at $SA_TOKEN_PATH"
        return 1
    fi
    
    local jwt_token vault_response vault_token
    jwt_token=$(cat "$SA_TOKEN_PATH")
    
    vault_response=$(curl -s -X POST "${VAULT_ADDR}/v1/auth/kubernetes/login" \
        -H "Content-Type: application/json" \
        -d "{\"role\": \"${K8S_AUTH_ROLE}\", \"jwt\": \"${jwt_token}\"}" 2>/dev/null)
    
    vault_token=$(echo "$vault_response" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('auth',{}).get('client_token',''))" 2>/dev/null || echo "")
    
    if [[ -n "$vault_token" && "$vault_token" != "None" ]]; then
        echo "$vault_token" > "$SHARED_TOKEN_FILE"
        chmod 600 "$SHARED_TOKEN_FILE"
        log "Kubernetes auth successful (vault-ops role), token written for CLI"
        return 0
    else
        local errors
        errors=$(echo "$vault_response" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('errors',[''])[0] if d.get('errors') else '')" 2>/dev/null)
        log "Kubernetes auth failed: ${errors:-unknown error}"
        return 1
    fi
}

write_token_for_cli_fallback() {
    if [[ -f "$ROOT_TOKEN_FILE" ]]; then
        cp "$ROOT_TOKEN_FILE" "$SHARED_TOKEN_FILE"
        chmod 600 "$SHARED_TOKEN_FILE"
        log "FALLBACK: Root token written to $SHARED_TOKEN_FILE for CLI auth"
    else
        log "WARNING: Root token file not found at $ROOT_TOKEN_FILE"
    fi
}

write_token_for_cli() {
    if login_with_k8s_auth; then
        return 0
    fi
    log "Kubernetes auth unavailable, falling back to root token..."
    write_token_for_cli_fallback
}

check_and_unseal() {
    local status
    status=$(curl -s "${VAULT_ADDR}/v1/sys/seal-status" 2>/dev/null)
    
    if [[ -z "$status" ]]; then
        return 1
    fi
    
    local initialized sealed
    initialized=$(echo "$status" | json_get initialized False || echo "false")
    sealed=$(echo "$status" | json_get sealed True || echo "true")
    
    if [[ "$initialized" != "True" ]]; then
        return 0
    fi
    
    if [[ "$sealed" != "True" ]]; then
        if [[ ! -f "$SHARED_TOKEN_FILE" ]]; then
            write_token_for_cli
        fi
        return 0
    fi
    
    log "Vault is sealed, attempting unseal..."
    
    if [[ ! -f "$UNSEAL_KEYS_FILE" ]]; then
        log "WARNING: Unseal keys file not found at $UNSEAL_KEYS_FILE"
        return 1
    fi
    
    local keys_json key_count=0
    keys_json=$(cat "$UNSEAL_KEYS_FILE")
    
    while IFS= read -r key; do
        if [[ -n "$key" ]]; then
            curl -s -X PUT "${VAULT_ADDR}/v1/sys/unseal" \
                -H "Content-Type: application/json" \
                -d "{\"key\": \"$key\"}" >/dev/null 2>&1
            
            key_count=$((key_count + 1))
            
            local check
            check=$(curl -s "${VAULT_ADDR}/v1/sys/seal-status" 2>/dev/null)
            local still_sealed
            still_sealed=$(echo "$check" | json_get sealed True || echo "true")
            
            if [[ "$still_sealed" != "True" ]]; then
                log "Vault successfully unsealed after $key_count key(s)"
                write_token_for_cli
                return 0
            fi
        fi
    done < <(echo "$keys_json" | python3 -c "import sys,json; [print(k) for k in json.load(sys.stdin)]" 2>/dev/null | head -n "$UNSEAL_THRESHOLD")
    
    log "Unseal attempt complete"
}

main() {
    log "Starting Vault auto-unseal sidecar (least privilege mode)"
    log "VAULT_ADDR: $VAULT_ADDR"
    log "CHECK_INTERVAL: ${CHECK_INTERVAL}s"
    log "K8S_AUTH_ROLE: $K8S_AUTH_ROLE"
    
    wait_for_vault
    write_token_for_cli
    
    while true; do
        check_and_unseal
        sleep "$CHECK_INTERVAL"
    done
}

main
