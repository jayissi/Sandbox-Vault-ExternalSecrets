#!/usr/bin/env bash
# Shared helpers sourced by Vault and lab scripts. Sources logging.sh so callers
# only need to source this file (or lib/vault.sh, which sources this file).

if [[ -n "${_LIB_COMMON_SH:-}" ]]; then
  return 0
fi
_LIB_COMMON_SH=1

_LIB_COMMON_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./logging.sh
source "${_LIB_COMMON_DIR}/logging.sh"

# Validate that a command exists and set an uppercase readonly path variable
# (e.g. check_command jq sets JQ). Skips the assignment if the variable is already set.
function check_command() {
  local cmd="${1}"
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    log "ERROR" "Command '${cmd}' not found. Please install it."
    exit 1
  fi
  debug "Command '${cmd}' is available."
  local upper_cmd
  upper_cmd="$(echo "${cmd}" | tr '[:lower:]' '[:upper:]')"
  if [[ -z "${!upper_cmd:-}" ]]; then
    readonly "${upper_cmd}"="$(command -v "${cmd}")"
  fi
}

# Fail if any named environment variable is unset or empty.
function validate_env() {
  local var
  for var in "$@"; do
    if [[ -z "${!var:-}" ]]; then
      log "ERROR" "Environment variable ${var} is not set."
      exit 1
    fi
  done
  log "SUCCESS" "All required environment variables are set."
}

# ERR trap with line/command context. Optional first argument is extra recovery text.
function setup_error_trap() {
  ERROR_TRAP_RECOVERY="${1:-}"
  # shellcheck disable=SC2064
  trap '_common_err_trap ${LINENO} "$BASH_COMMAND"' ERR
}

function _common_err_trap() {
  local exit_code=${?}
  local line_number="${1}"
  local command="${2}"
  if [[ ${exit_code} -ne 0 ]]; then
    log "ERROR" "Script failed at line ${line_number}: '${command}' with exit code ${exit_code}."
    if [[ -n "${ERROR_TRAP_RECOVERY:-}" ]]; then
      log "ERROR" "${ERROR_TRAP_RECOVERY}"
    fi
    exit "${exit_code}"
  fi
}
