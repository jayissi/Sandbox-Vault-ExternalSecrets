# =============================================================================
# Two-phase Makefile: host delegates to run.sh, container runs real recipes.
# =============================================================================
#
# Same pattern as the top-level Makefile:
#   1) Host (no WORKFLOW_IN_CONTAINER): delegates to ../run.sh which launches
#      an origin-cli container, installs tools, then re-invokes via the
#      top-level Makefile → this Makefile with WORKFLOW_IN_CONTAINER set.
#   2) Inside origin-cli (WORKFLOW_IN_CONTAINER=1): real recipes run here.
#
# Targets that only need oc (create-configmap, verify-init, help) work on
# the host without a container and are defined outside the ifdef/else block.
# =============================================================================

# Use Bash as the shell
SHELL := /bin/bash

# Suppress directory change messages
MAKEFLAGS += --no-print-directory

# Phony targets (targets that are not files)
.PHONY: dev lab prod clean help create-configmap verify-init

# Default target (run when no target is specified)
.DEFAULT_GOAL := help

# ──────────────────────────────────────────────────────────────────────────────
ifdef WORKFLOW_IN_CONTAINER
# Real recipes: tools (helm, jq, make) are available inside the container.
# ──────────────────────────────────────────────────────────────────────────────

# Variables
HELM_REPO := hashicorp
HELM_REPO_URL := https://helm.releases.hashicorp.com
VAULT_CHART := hashicorp/vault
VAULT_NAMESPACE := vault
VAULT_URL := $(shell echo vault.$$(oc get ingresses.config.openshift.io cluster -o jsonpath --template='{.spec.domain}'))
DEFAULT_STORAGE_CLASS := $(shell oc get sc -o=jsonpath='{.items[?(@.metadata.annotations.storageclass\.kubernetes\.io\/is-default-class=="true")].metadata.name}')
VERSION := 0.32.0

# Auto-unseal: false = disabled (default), true = enable auto-unseal sidecar
VAULT_AUTO_UNSEAL ?= false

dev:
	@echo "Setting up development environment..."
	@$(call add_helm_repo,$(HELM_REPO),$(HELM_REPO_URL))
	@$(call update_helm_repo,$(HELM_REPO))
	@$(call install_vault,$(VAULT_CHART),$(VAULT_NAMESPACE),$(VAULT_URL),values.dev.yaml)
	@echo "Development environment setup completed."
	@echo "Note: Dev environment does not require initialization (standalone mode)"

# Lab/prod need create-configmap first so the auto-unseal sidecar (when enabled) can mount
# init-install-v2.sh; Helm alone does not load those into the cluster.
lab: create-configmap
	@echo "Setting up lab environment..."
	@$(call add_helm_repo,$(HELM_REPO),$(HELM_REPO_URL))
	@$(call update_helm_repo,$(HELM_REPO))
	@$(call install_vault,$(VAULT_CHART),$(VAULT_NAMESPACE),$(VAULT_URL),values.lab.yaml)
	@echo "Waiting for Vault pods to start..."
	@/bin/bash -c 'for i in {1..30}; do if oc get pod vault-0 -n $(VAULT_NAMESPACE) -o jsonpath='\''{.status.phase}'\'' 2>/dev/null | grep -q Running; then echo "Vault pods are running"; exit 0; fi; sleep 1; done; echo "ERROR: Vault pod vault-0 did not reach Running state within 30s"; exit 1'
	$(call run_vault_init)
	@echo "Lab environment setup completed."

prod: create-configmap
	@echo "Setting up production environment..."
	@$(call add_helm_repo,$(HELM_REPO),$(HELM_REPO_URL))
	@$(call update_helm_repo,$(HELM_REPO))
	@$(call install_vault,$(VAULT_CHART),$(VAULT_NAMESPACE),$(VAULT_URL),values.lab.yaml values.prod.yaml,$(VERSION))
	@echo "Waiting for Vault pods to start..."
	@/bin/bash -c 'for i in {1..60}; do running=$$(oc get pods -n $(VAULT_NAMESPACE) -l app.kubernetes.io/name=vault --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l || echo 0); if [ $$running -ge 3 ]; then echo "All 3 Vault pods are running"; exit 0; fi; sleep 1; done; echo "ERROR: Not all Vault pods reached Running state within 60s"; exit 1'
	$(call run_vault_init)
	@echo "Production environment setup completed."

clean:
	@echo "Cleaning up the Vault environment..."
	@-helm uninstall vault -n $(VAULT_NAMESPACE) --wait --timeout 60s || true
	@-oc delete pvc --all -n $(VAULT_NAMESPACE) || true
	@-oc delete project $(VAULT_NAMESPACE) || true
	@echo "Vault environment cleaned."

# Function to add a Helm repository
define add_helm_repo
	@echo "Adding Helm repository $(1)..."
	@helm repo add $(1) $(2) || { echo "Error: Failed to add Helm repository $(1)"; exit 1; }
endef

# Function to update a Helm repository
define update_helm_repo
	@echo "Updating Helm repository $(1)..."
	@helm repo update $(1) || { echo "Error: Failed to update Helm repository $(1)"; exit 1; }
endef

# install_vault(chart, namespace, route_host, value_files..., optional chart version):
#   --install: idempotent install or upgrade.
#   --set server.route.host: OpenShift Route hostname (must match cluster DNS; see VAULT_URL).
#   --set server.*Storage.storageClass: bind data/audit PVCs to the cluster default SC (see DEFAULT_STORAGE_CLASS).
#   -f upstream values + openshift overlay + env-specific files: HashiCorp base, then OCP tweaks, then lab/prod overrides.
#   -n / --create-namespace: target vault and create it if missing.
#   --wait / --wait-for-jobs: block until pods (and hook Jobs) are ready so init does not race a half-ready release.
#   --timeout 60s: fail fast if the chart cannot schedule; shorter than long operator installs by design here.
#   --version: pin chart when passed (prod) for repeatable upgrades.
#   VAULT_AUTO_UNSEAL=true: adds values.auto-unseal.yaml for auto-unseal sidecar.
define install_vault
	@echo "Installing Vault from chart $(1)..."
	@if [ "$(VAULT_AUTO_UNSEAL)" = "true" ]; then echo "Auto-unseal sidecar: ENABLED"; else echo "Auto-unseal sidecar: DISABLED"; fi
	@helm upgrade \
		vault \
		$(1) \
		--install \
		--set server.route.host=$(3) \
		--set server.dataStorage.storageClass=$(DEFAULT_STORAGE_CLASS) \
		--set server.auditStorage.storageClass=$(DEFAULT_STORAGE_CLASS) \
		-f https://github.com/hashicorp/vault-helm/raw/main/values.yaml \
		-f https://github.com/hashicorp/vault-helm/raw/main/values.openshift.yaml \
		$(foreach file,$(4),-f $(file)) \
		$(if $(filter true,$(VAULT_AUTO_UNSEAL)),-f values.auto-unseal.yaml,) \
		-n $(2) \
		--create-namespace \
		--wait \
		--wait-for-jobs \
		--timeout 60s \
		$(if $(5),--version $(5),) || { echo "Error: Failed to install Vault"; exit 1; }
endef

define run_vault_init
	@echo "Running Vault initialization..."
	@export HOSTNAME="vault-0"; \
	bash init-install-v2.sh
endef

# Function to verify Vault initialization completed
define verify_init
	@echo "Verifying Vault initialization..."
	@if oc get secret vault-operator-init -n $(1) >/dev/null 2>&1; then \
		echo "✓ Vault initialization secret exists"; \
		if oc exec -n $(1) vault-0 -c vault -- vault status 2>/dev/null | grep -q "Initialized.*true"; then \
			echo "✓ Vault is initialized"; \
			if oc exec -n $(1) vault-0 -c vault -- vault status 2>/dev/null | grep -q "Sealed.*false"; then \
				echo "✓ Vault is unsealed"; \
				echo "Success: Vault initialization completed successfully"; \
			else \
				echo "Warning: Vault is initialized but may still be sealed"; \
			fi; \
		else \
			echo "Warning: Vault initialization secret exists but Vault may not be fully initialized"; \
		fi; \
	else \
		echo "Error: Vault initialization secret not found. Initialization may have failed."; \
		exit 1; \
	fi
endef

# ──────────────────────────────────────────────────────────────────────────────
else
# Host: delegate to the top-level run.sh which launches an origin-cli container.
# dev/lab/prod map 1:1; clean maps to clean-hv at the top level.
# ──────────────────────────────────────────────────────────────────────────────

REPO_ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST)))/..)

define launch_container
	cd $(REPO_ROOT) && WORKFLOW_TARGET=$(1) ./run.sh
endef

dev:
	@$(call launch_container,dev)

lab:
	@$(call launch_container,lab)

prod:
	@$(call launch_container,prod)

clean:
	@$(call launch_container,clean-hv)

endif

# ──────────────────────────────────────────────────────────────────────────────
# Targets below work on both host and container (only need oc, not helm/jq).
# ──────────────────────────────────────────────────────────────────────────────

VAULT_NAMESPACE ?= vault
VAULT_AUTO_UNSEAL ?= false

# Create ConfigMap for scripts
create-configmap:
	@echo "Creating ConfigMap for initialization scripts..."
	@oc create namespace $(VAULT_NAMESPACE) --dry-run=client -o yaml | oc apply -f - || true
	@oc create configmap vault-init-scripts \
		--from-file=init-install-v2.sh=./init-install-v2.sh \
		-n $(VAULT_NAMESPACE) \
		--dry-run=client -o yaml | oc apply -f - || { echo "Warning: Failed to create ConfigMap"; }
	@if [ "$(VAULT_AUTO_UNSEAL)" = "true" ]; then \
		echo "Creating ConfigMap for auto-unseal script..."; \
		oc create configmap vault-auto-unseal-script \
			--from-file=vault-auto-unseal.sh=./vault-auto-unseal.sh \
			-n $(VAULT_NAMESPACE) \
			--dry-run=client -o yaml | oc apply -f - || { echo "Warning: Failed to create auto-unseal ConfigMap"; }; \
	fi

verify-init:
	@$(call verify_init,$(VAULT_NAMESPACE))

# Display help information
help:
	@echo "Usage: make <target>"
	@echo ""
	@echo "Targets:"
	@echo "  dev                Set up the development environment"
	@echo "  lab                Set up the lab environment"
	@echo "  prod               Set up the production environment (3 instances, HA)"
	@echo "  clean              Clean up the Vault environment"
	@echo "  create-configmap   Create ConfigMap for initialization scripts"
	@echo "  verify-init        Verify Vault initialization completed successfully"
	@echo "  help               Display this help message"
	@echo ""
	@echo "Auto-Unseal:"
	@echo "  VAULT_AUTO_UNSEAL=false (default) - Manual unseal required after pod restart"
	@echo "  VAULT_AUTO_UNSEAL=true            - Auto-unseal sidecar enabled"
	@echo ""
	@echo "Note: dev/lab/prod/clean run inside a version-matched origin-cli container"
	@echo "via run.sh. Use the top-level Makefile for full stack (Vault + ESO + demo)."
