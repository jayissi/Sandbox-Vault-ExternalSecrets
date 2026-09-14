#!/usr/bin/env bash
# Vault pod helpers. Expects OC and VAULT_NAMESPACE to be set at call time.
# Sources lib/common.sh (and therefore lib/logging.sh).

if [[ -n "${_LIB_VAULT_SH:-}" ]]; then
  return 0
fi
_LIB_VAULT_SH=1

_LIB_VAULT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./common.sh
source "${_LIB_VAULT_DIR}/common.sh"

# Run a shell command on vault-0. -c vault avoids "Defaulted container" when the
# auto-unseal sidecar is present; with a single-container pod it is a no-op.
function vault_exec() {
  local cmd="${1}"
  debug "Executing Vault command: ${cmd}"
  "${OC}" exec -n "${VAULT_NAMESPACE}" -c vault -i pods/vault-0 -- sh -c "${cmd}"
}

# Run a command on vault-<index>. Extra arguments are passed to oc exec unchanged.
# Use -i (already set) so callers can pipe stdin (unseal keys, policy HCL, tokens).
function vault_exec_pod() {
  local pod_index="${1}"
  shift
  "${OC}" exec -n "${VAULT_NAMESPACE}" -c vault -i pods/"vault-${pod_index}" -- "$@"
}
