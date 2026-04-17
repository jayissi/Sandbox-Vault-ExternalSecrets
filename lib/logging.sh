#!/usr/bin/env bash
# Shared logging functions sourced by init-install-v2.sh, post-install-v3.sh,
# and verify-vault-openshift.sh.  Expects DEBUG and TRACE to be set by the caller
# (defaults provided below).

DEBUG="${DEBUG:-false}"
TRACE="${TRACE:-false}"

# Enable trace mode only if both DEBUG and TRACE are true
if [[ "${DEBUG}" == true && "${TRACE}" == true ]]; then
    set -x
fi

# Logging colors
readonly LOG_RED='\033[0;31m'
readonly LOG_GREEN='\033[0;32m'
readonly LOG_YELLOW='\033[1;33m'
readonly LOG_ORANGE='\033[38;5;214m'
readonly LOG_BLUE='\033[0;34m'
readonly LOG_WHITE='\033[1;37m'
readonly LOG_RESET='\033[0m'

function log() {
  local level="${1:-INFO}"
  local message="${2}"
  local message_length=${#message}
  local timestamp
  timestamp=$(date +"%Y-%m-%d %H:%M:%S")
  local border="---------------------------------------------------------------------------------"
  local border_length=$(( ${#border} - 2 ))
  local padding_length=$(( (border_length - message_length - 2) / 2 ))
  local padding
  padding=$(printf '%*s' "${padding_length}" "")
  local color=""

  case "${level}" in
    INFO)    color="${LOG_WHITE}" ;;
    DEBUG)   color="${LOG_YELLOW}" ;;
    WARNING) color="${LOG_ORANGE}" ;;
    ERROR)   color="${LOG_RED}" ;;
    SUCCESS) color="${LOG_GREEN}" ;;
    TRACE)   color="${LOG_BLUE}" ;;
    *)       color="${LOG_RESET}" ;;
  esac

  printf "%b%s\n⎈ %s%s%s ⎈\n%s%b\n" "${LOG_BLUE}" "${border}" "${padding}" "${message}" "${padding}" "${border}" "${LOG_WHITE}" >&2
  printf "%b[%s] [%s]%b\n" "${color}" "${timestamp}" "${level}" "${LOG_RESET}" >&2
}

function debug() {
  local message="${1}"
  if [[ "${DEBUG}" == true ]]; then
    log "DEBUG" "${message}" >&2
  fi
}

function trace() {
  local message="${1}"
  if [[ "${DEBUG}" == true && "${TRACE}" == true ]]; then
    log "TRACE" "${message}" >&2
  fi
}
