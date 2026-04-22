#!/bin/bash
set -euo pipefail

# Container initialization script for Vault sidecar
# This script runs inside the sidecar container and executes the Vault initialization
# It can be executed from:
# 1. ConfigMap mount at /scripts/container-init.sh
# 2. Cloned repository at /tmp/vault-init/hashicorp-vault-helm/container-init.sh

readonly SCRIPT_DIR="/tmp/vault-init"
readonly REPO_URL="https://github.com/jayissi/Sandbox-Vault-ExternalSecrets.git"
readonly HELM_VERSION="v3.19.2"
readonly HELM_URL="https://get.helm.sh/helm-${HELM_VERSION}-linux-amd64.tar.gz"
readonly JQ_URL="https://github.com/jqlang/jq/releases/download/jq-1.8.1/jq-linux-amd64"
readonly _OC_URL="https://mirror.openshift.com/pub/openshift-v4/clients/ocp/stable-4.18/openshift-client-linux-amd64-rhel8.tar.gz"
readonly VAULT_NAMESPACE="${VAULT_NAMESPACE:-vault}"

# Logging functions
log() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" >&2
}

error() {
  echo "[ERROR] $*" >&2
  exit 1
}

# Check if we're running on vault-0 (only vault-0 should run initialization)
# Note: When running as a Job, HOSTNAME is set to "vault-0" explicitly
check_pod_name() {
  local pod_name="${HOSTNAME:-}"
  if [[ -z "${pod_name}" ]]; then
    # Try to get pod name from downward API or environment
    pod_name=$(hostname 2>/dev/null || echo "")
  fi
  
  # Extract pod index from pod name (e.g., vault-0, vault-1, vault-2)
  if [[ "${pod_name}" =~ vault-([0-9]+) ]]; then
    local pod_index="${BASH_REMATCH[1]}"
    if [[ "${pod_index}" != "0" ]]; then
      log "Running on vault-${pod_index}, not vault-0. Exiting (this is expected for non-initial pods)."
      exit 0
    fi
  elif [[ "${pod_name}" == "vault-0" ]]; then
    # Explicitly set for Job execution
    log "Initializing vault-0 (Job execution mode)"
  else
    # If we can't determine pod name, assume we're on vault-0 and proceed
    log "Warning: Could not determine pod name from HOSTNAME. Proceeding with initialization."
  fi
}

# Install dependencies
install_dependencies() {
  log "Installing dependencies..."
  
  # Create bin directory in /tmp (writable by non-root users)
  mkdir -p /tmp/bin
  export PATH="/tmp/bin:${PATH}"
  
  # Install jq
  if ! command -v jq > /dev/null 2>&1; then
    log "Installing jq..."
    curl -fsSL -o /tmp/bin/jq "${JQ_URL}" || error "Failed to download jq"
    chmod +x /tmp/bin/jq
    log "jq installed to /tmp/bin/jq"
  else
    log "jq already installed"
  fi
  
  # Install helm
  if ! command -v helm > /dev/null 2>&1; then
    log "Installing helm..."
    curl -fsSL "${HELM_URL}" | tar -xz -C /tmp || error "Failed to download helm"
    mv /tmp/linux-amd64/helm /tmp/bin/helm || error "Failed to install helm"
    chmod +x /tmp/bin/helm
    rm -rf /tmp/linux-amd64
    log "helm installed to /tmp/bin/helm"
  else
    log "helm already installed"
  fi
  
  # Install make (optional - only needed if cloning repo, not needed for ConfigMap approach)
  if ! command -v make > /dev/null 2>&1; then
    log "make not available (not required for initialization)"
  else
    log "make already available"
  fi
  
  # Install git (optional - try to install, but not critical if ConfigMap is used)
  if ! command -v git > /dev/null 2>&1; then
    log "git not available - will use ConfigMap scripts instead of cloning repo"
  else
    log "git already available"
  fi
  
  # Verify oc is available (should be in base image)
  if ! command -v oc > /dev/null 2>&1; then
    error "oc command not found. This script requires the OpenShift CLI image."
  fi
  
  log "All dependencies installed successfully"
}

# Clone repository or use ConfigMap fallback
setup_scripts() {
  log "Setting up scripts..."
  
  # First, check if scripts are already in current directory (mounted from host)
  if [[ -f "./init-install-v2.sh" ]] && [[ -f "./container-init.sh" ]]; then
    log "Using scripts from current directory (mounted from host)"
    mkdir -p "${SCRIPT_DIR}/hashicorp-vault-helm"
    cp ./init-install-v2.sh "${SCRIPT_DIR}/hashicorp-vault-helm/" || error "Failed to copy init-install-v2.sh"
    cp ./container-init.sh "${SCRIPT_DIR}/hashicorp-vault-helm/" 2>/dev/null || true
    return 0
  fi
  
  # Try to clone repository
  if command -v git > /dev/null 2>&1 && git clone "${REPO_URL}" "${SCRIPT_DIR}" 2>/dev/null; then
    log "Successfully cloned repository"
    # Copy container-init.sh to the cloned directory for consistency
    if [[ -f "/scripts/container-init.sh" ]]; then
      cp /scripts/container-init.sh "${SCRIPT_DIR}/hashicorp-vault-helm/" 2>/dev/null || true
    fi
    return 0
  fi
  
  # Fallback: Check if scripts are available in ConfigMap mount
  if [[ -f "/scripts/init-install-v2.sh" ]]; then
    log "Using scripts from ConfigMap mount"
    mkdir -p "${SCRIPT_DIR}/hashicorp-vault-helm"
    cp /scripts/init-install-v2.sh "${SCRIPT_DIR}/hashicorp-vault-helm/" || error "Failed to copy init-install-v2.sh from ConfigMap"
    if [[ -f "/scripts/container-init.sh" ]]; then
      cp /scripts/container-init.sh "${SCRIPT_DIR}/hashicorp-vault-helm/" || true
    fi
    return 0
  fi
  
  error "Failed to clone repository and no scripts found in current directory or ConfigMap"
}

# Wait for Vault pods to exist and be running (quick check, init script handles the rest)
wait_for_vault_pods() {
  local namespace="${VAULT_NAMESPACE:-vault}"
  local max_wait=60  # 1 minute max
  local elapsed=0
  local interval=2
  
  log "Waiting for Vault pods to be running..."
  
  # Just check if pods exist and are running - init script will handle vault responsiveness
  while [[ ${elapsed} -lt ${max_wait} ]]; do
    local pod_count
    pod_count=$(oc get pods -n "${namespace}" -l app.kubernetes.io/name=vault --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l || echo "0")
    if [[ "${pod_count}" -gt 0 ]]; then
      log "Vault pods are running (${pod_count} pod(s))"
      # Give pods a moment to fully start
      sleep 5
      return 0
    fi
    
    if [[ $((elapsed % 10)) -eq 0 ]]; then
      log "Waiting for Vault pods... (${elapsed}s/${max_wait}s)"
    fi
    sleep ${interval}
    elapsed=$((elapsed + interval))
  done
  
  log "WARNING: Timeout waiting for Vault pods, but proceeding - init script will handle retries"
}

# Main execution
main() {
  log "Starting Vault initialization container..."
  
  # Check if we're on vault-0
  check_pod_name
  
  # Install dependencies
  install_dependencies
  
  # Setup scripts
  setup_scripts
  
  # Wait for Vault pods to be ready
  wait_for_vault_pods
  
  # Change to script directory
  if [[ -d "${SCRIPT_DIR}/hashicorp-vault-helm" ]]; then
    cd "${SCRIPT_DIR}/hashicorp-vault-helm" || error "Failed to change to script directory"
  elif [[ -f "${SCRIPT_DIR}/init-install-v2.sh" ]]; then
    cd "${SCRIPT_DIR}" || error "Failed to change to script directory"
  else
    error "Could not find init-install-v2.sh script"
  fi
  
  # Execute initialization script (scripts are mounted read-only, use bash directly)
  if [[ ! -f "init-install-v2.sh" ]]; then
    error "init-install-v2.sh not found in current directory"
  fi
  
  log "Executing Vault initialization script..."
  bash init-install-v2.sh || {
    # Check if error is due to already initialized
    if oc get secret vault-operator-init -n "${VAULT_NAMESPACE}" >/dev/null 2>&1; then
      log "Vault is already initialized, checking if unsealed..."
      # Check if vault is unsealed
      if oc exec -n "${VAULT_NAMESPACE}" vault-0 -c vault -- vault status 2>/dev/null | grep -q "Sealed.*false"; then
        log "Vault is already initialized and unsealed - skipping initialization"
      else
        log "Vault is initialized but sealed - attempting to unseal..."
        # Extract unseal keys from secret and unseal
        local _root_token
        _root_token=$(oc get secret vault-operator-init -n "${VAULT_NAMESPACE}" -o jsonpath='{.data.root_token}' | base64 -d)
        local _unseal_keys
        _unseal_keys=$(oc get secret vault-operator-init -n "${VAULT_NAMESPACE}" -o jsonpath='{.data.unseal_keys_b64}' | base64 -d | jq -r '.[]')
        # Unseal logic would go here if needed
        log "WARNING: Vault is sealed but initialization already exists"
      fi
    else
      error "Vault initialization failed"
    fi
  }
  log "Vault initialization completed successfully"
  
  # Check if we should also setup External Secrets Operator and demo
  # This is controlled by environment variable SETUP_DEMO
  if [[ "${SETUP_DEMO:-false}" == "true" ]]; then
    log "SETUP_DEMO is enabled, proceeding with ESO and demo setup..."
    
    # Check if External Secrets Operator namespace exists, if not, install it
    if ! oc get namespace external-secrets >/dev/null 2>&1; then
      log "External Secrets Operator namespace not found. Installing ESO..."
      # Install External Secrets Operator via Helm
      if ! helm repo list | grep -q external-secrets; then
        helm repo add external-secrets https://charts.external-secrets.io
        helm repo update external-secrets
      fi
      helm install external-secrets external-secrets/external-secrets -n external-secrets --create-namespace --wait --timeout 5m || {
        log "WARNING: Failed to install External Secrets Operator. Demo setup may fail."
      }
    fi
    
    # Wait for External Secrets Operator to be ready (optimized)
    log "Waiting for External Secrets Operator to be ready..."
    local max_wait=180  # 3 minutes (reduced from 5)
    local elapsed=0
    local interval=5  # Check every 5 seconds
    
    while [[ ${elapsed} -lt ${max_wait} ]]; do
      if oc get pods -n external-secrets -l app.kubernetes.io/name=external-secrets --field-selector=status.phase=Running 2>/dev/null | grep -q external-secrets; then
        log "External Secrets Operator is ready"
        break
      fi
      if [[ $((elapsed % 15)) -eq 0 ]]; then
        log "Waiting for External Secrets Operator... (${elapsed}s/${max_wait}s)"
      fi
      sleep ${interval}
      elapsed=$((elapsed + interval))
    done
    
    if [[ ${elapsed} -ge ${max_wait} ]]; then
      log "WARNING: Timeout waiting for External Secrets Operator. Demo setup may fail."
    fi
    
    # Run demo setup script - check multiple locations
    local demo_script=""
    # Check from workspace-parent (where parent directory is mounted)
    if [[ -f "/workspace-parent/vault-external-secrets-lab/post-install-v3.sh" ]]; then
      demo_script="/workspace-parent/vault-external-secrets-lab/post-install-v3.sh"
    elif [[ -f "/workspace/vault-external-secrets-lab/post-install-v3.sh" ]]; then
      demo_script="/workspace/vault-external-secrets-lab/post-install-v3.sh"
    elif [[ -f "/workspace/../vault-external-secrets-lab/post-install-v3.sh" ]]; then
      demo_script="/workspace/../vault-external-secrets-lab/post-install-v3.sh"
    elif [[ -f "${SCRIPT_DIR}/../vault-external-secrets-lab/post-install-v3.sh" ]]; then
      demo_script="${SCRIPT_DIR}/../vault-external-secrets-lab/post-install-v3.sh"
    elif [[ -f "../vault-external-secrets-lab/post-install-v3.sh" ]]; then
      demo_script="../vault-external-secrets-lab/post-install-v3.sh"
    elif [[ -f "./vault-external-secrets-lab/post-install-v3.sh" ]]; then
      demo_script="./vault-external-secrets-lab/post-install-v3.sh"
    fi
    
    if [[ -n "${demo_script}" ]] && [[ -f "${demo_script}" ]]; then
      log "Executing demo setup script: ${demo_script}"
      local demo_dir
      demo_dir=$(dirname "${demo_script}")
      cd "${demo_dir}" || error "Failed to change to demo directory: ${demo_dir}"
      bash post-install-v3.sh || {
        log "WARNING: Demo setup script failed, but continuing..."
      }
      log "Demo setup completed"
    else
      log "WARNING: post-install-v3.sh not found. Skipping demo setup."
      log "Searched in: /workspace-parent/vault-external-secrets-lab, /workspace/vault-external-secrets-lab, ${SCRIPT_DIR}, ../vault-external-secrets-lab, ./vault-external-secrets-lab"
    fi
  else
    log "SETUP_DEMO is not enabled. Skipping ESO and demo setup."
  fi
  
  log "All setup tasks completed successfully"
  exit 0
}

# Run main function
main "$@"

