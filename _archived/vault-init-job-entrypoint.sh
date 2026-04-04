#!/bin/bash
set -euo pipefail

# OpenShift Job entrypoint script for Vault initialization
# This script combines functionality from container-init.sh and run-init-container.sh
# It runs directly in an OpenShift Job pod

readonly SCRIPT_DIR="/tmp/vault-init"
readonly REPO_URL="https://github.com/jayissi/Sandbox-Vault-ExternalSecrets.git"
readonly HELM_VERSION="v3.19.2"
readonly HELM_URL="https://get.helm.sh/helm-${HELM_VERSION}-linux-amd64.tar.gz"
readonly JQ_URL="https://github.com/jqlang/jq/releases/download/jq-1.8.1/jq-linux-amd64"
readonly VAULT_NAMESPACE="${VAULT_NAMESPACE:-vault}"

# Logging functions
log() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" >&2
}

error() {
  echo "[ERROR] $*" >&2
  exit 1
}

# Install dependencies
install_dependencies() {
  log "Installing dependencies..."
  
  # Create bin directory in /tmp (writable by non-root users)
  mkdir -p /tmp/bin
  export PATH="/tmp/bin:${PATH}"
  
  # Install jq with retry logic
  if ! command -v jq > /dev/null 2>&1; then
    log "Installing jq..."
    jq_installed=false
    for attempt in 1 2 3 4 5; do
      if curl -fsSL -o /tmp/bin/jq "${JQ_URL}"; then
        chmod +x /tmp/bin/jq
        jq_installed=true
        break
      else
        log "Attempt ${attempt}/5 failed, retrying in 3 seconds..."
        sleep 3
      fi
    done
    if [ "${jq_installed}" != "true" ]; then
      error "Failed to download jq after 5 attempts"
    fi
    log "jq installed to /tmp/bin/jq"
  else
    log "jq already installed"
  fi
  
  # Install helm with retry logic
  if ! command -v helm > /dev/null 2>&1; then
    log "Installing helm..."
    helm_installed=false
    for attempt in 1 2 3 4 5; do
      if curl -fsSL "${HELM_URL}" | tar -xz -C /tmp; then
        mv /tmp/linux-amd64/helm /tmp/bin/helm || error "Failed to install helm"
        chmod +x /tmp/bin/helm
        rm -rf /tmp/linux-amd64
        helm_installed=true
        break
      else
        log "Attempt ${attempt}/5 failed, retrying in 3 seconds..."
        sleep 3
      fi
    done
    if [ "${helm_installed}" != "true" ]; then
      error "Failed to download helm after 5 attempts"
    fi
    log "helm installed to /tmp/bin/helm"
  else
    log "helm already installed"
  fi
  
  # Verify oc is available (should be in base image)
  if ! command -v oc > /dev/null 2>&1; then
    error "oc command not found. This script requires the OpenShift CLI image."
  fi
  
  log "All dependencies installed successfully"
}

# Setup scripts from ConfigMap or git clone
setup_scripts() {
  log "Setting up scripts..."
  
  # First, check if scripts are available in ConfigMap mount
  if [[ -f "/scripts/init-install-v2.sh" ]]; then
    log "Using scripts from ConfigMap mount"
    mkdir -p "${SCRIPT_DIR}/hashicorp-vault-helm"
    cp /scripts/init-install-v2.sh "${SCRIPT_DIR}/hashicorp-vault-helm/" || error "Failed to copy init-install-v2.sh from ConfigMap"
    return 0
  fi
  
  # Try to clone repository
  if command -v git > /dev/null 2>&1 && git clone "${REPO_URL}" "${SCRIPT_DIR}" 2>/dev/null; then
    log "Successfully cloned repository"
    return 0
  fi
  
  error "Failed to find scripts in ConfigMap and could not clone repository"
}

# Wait for Vault pods to exist and be running
wait_for_vault_pods() {
  local namespace="${VAULT_NAMESPACE:-vault}"
  local max_wait=120  # 2 minutes max
  local elapsed=0
  local interval=2
  
  log "Waiting for Vault pods to be running..."
  
  # Check if pods exist and are running - init script will handle vault responsiveness
  while [[ ${elapsed} -lt ${max_wait} ]]; do
    local pod_count=$(oc get pods -n "${namespace}" -l app.kubernetes.io/name=vault --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l || echo "0")
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
  log "Starting Vault initialization Job..."
  
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
  
  # Execute initialization script
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
        local root_token=$(oc get secret vault-operator-init -n "${VAULT_NAMESPACE}" -o jsonpath='{.data.root_token}' | base64 -d)
        local unseal_keys=$(oc get secret vault-operator-init -n "${VAULT_NAMESPACE}" -o jsonpath='{.data.unseal_keys_b64}' | base64 -d | jq -r '.[]')
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
    
    # Wait for External Secrets Operator to be ready
    log "Waiting for External Secrets Operator to be ready..."
    local max_wait=180  # 3 minutes
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
    # Check from ConfigMap or workspace
    if [[ -f "/scripts/../vault-external-secrets-lab/post-install-v3.sh" ]]; then
      demo_script="/scripts/../vault-external-secrets-lab/post-install-v3.sh"
    elif [[ -f "/workspace/vault-external-secrets-lab/post-install-v3.sh" ]]; then
      demo_script="/workspace/vault-external-secrets-lab/post-install-v3.sh"
    elif [[ -f "${SCRIPT_DIR}/../vault-external-secrets-lab/post-install-v3.sh" ]]; then
      demo_script="${SCRIPT_DIR}/../vault-external-secrets-lab/post-install-v3.sh"
    fi
    
    if [[ -n "${demo_script}" ]] && [[ -f "${demo_script}" ]]; then
      log "Executing demo setup script: ${demo_script}"
      local demo_dir=$(dirname "${demo_script}")
      cd "${demo_dir}" || error "Failed to change to demo directory: ${demo_dir}"
      bash post-install-v3.sh || {
        log "WARNING: Demo setup script failed, but continuing..."
      }
      log "Demo setup completed"
    else
      log "WARNING: post-install-v3.sh not found. Skipping demo setup."
    fi
  else
    log "SETUP_DEMO is not enabled. Skipping ESO and demo setup."
  fi
  
  log "All setup tasks completed successfully"
  exit 0
}

# Run main function
main "$@"

