# Use Bash as the shell
SHELL := /bin/bash

# Suppress directory change messages
MAKEFLAGS += --no-print-directory

# Phony targets (targets that are not files)
.PHONY: dev lab prod clean help create-configmap verify-init create-vault-init-job wait-for-vault-init-job

# Variables
HELM_REPO := hashicorp
HELM_REPO_URL := https://helm.releases.hashicorp.com
VAULT_CHART := hashicorp/vault
VAULT_NAMESPACE := vault
# Resolved at make parse time from the live cluster (not hardcoded): cluster ingress domain and default StorageClass.
VAULT_URL := $(shell echo vault.$$(oc get ingresses.config.openshift.io cluster -o jsonpath --template='{.spec.domain}'))
DEFAULT_STORAGE_CLASS := $(shell oc get sc -o=jsonpath='{.items[?(@.metadata.annotations.storageclass\.kubernetes\.io\/is-default-class=="true")].metadata.name}')
VERSION := 0.32.0

# Execution method: true = containerized (default), false = localhost/bastion
USE_CONTAINER ?= true

# Default target (run when no target is specified)
.DEFAULT_GOAL := help

# Run development environment setup
dev:
	@echo "Setting up development environment..."
	@$(call add_helm_repo,$(HELM_REPO),$(HELM_REPO_URL))
	@$(call update_helm_repo,$(HELM_REPO))
	@$(call install_vault,$(VAULT_CHART),$(VAULT_NAMESPACE),$(VAULT_URL),values.dev.yaml)
	@echo "Development environment setup completed."
	@echo "Note: Dev environment does not require initialization (standalone mode)"

# Lab/prod need create-configmap first so the init Job (or a manual apply path) can mount current copies of
# vault-init-job-entrypoint.sh and init-install-v2.sh; Helm alone does not load those into the cluster.
# Run lab environment setup
lab: create-configmap
	@echo "Setting up lab environment..."
	@$(call add_helm_repo,$(HELM_REPO),$(HELM_REPO_URL))
	@$(call update_helm_repo,$(HELM_REPO))
	@$(call install_vault,$(VAULT_CHART),$(VAULT_NAMESPACE),$(VAULT_URL),values.lab.yaml)
	@echo "Waiting for Vault pods to start..."
	@/bin/bash -c 'for i in {1..30}; do if oc get pod vault-0 -n $(VAULT_NAMESPACE) -o jsonpath='\''{.status.phase}'\'' 2>/dev/null | grep -q Running; then echo "Vault pods are running"; break; fi; sleep 1; done'
	@echo "Running Vault initialization via OpenShift Job..."
	# USE_CONTAINER=true: run init in-cluster (no kubeconfig/credentials on admin laptops). USE_CONTAINER=false: run
	# init-install-v2.sh on the bastion with oc exec to pods (same script, different execution context).
	@if [ "$(USE_CONTAINER)" = "true" ]; then \
		$(MAKE) create-vault-init-job || { echo "Error: Failed to create Vault init Job"; exit 1; }; \
		$(MAKE) wait-for-vault-init-job || { echo "Error: Vault init Job failed"; exit 1; }; \
	else \
		echo "Running initialization on localhost..."; \
		export HOSTNAME="vault-0"; \
		bash init-install-v2.sh; \
	fi
	@echo "Lab environment setup completed."

# Run production environment setup
prod: create-configmap
	@echo "Setting up production environment..."
	@$(call add_helm_repo,$(HELM_REPO),$(HELM_REPO_URL))
	@$(call update_helm_repo,$(HELM_REPO))
	@$(call install_vault,$(VAULT_CHART),$(VAULT_NAMESPACE),$(VAULT_URL),values.lab.yaml values.prod.yaml,$(VERSION))
	@echo "Waiting for Vault pods to start..."
	@/bin/bash -c 'for i in {1..60}; do running=$$(oc get pods -n $(VAULT_NAMESPACE) -l app.kubernetes.io/name=vault --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l || echo 0); if [ $$running -ge 3 ]; then echo "All 3 Vault pods are running"; break; fi; sleep 1; done'
	# Init path: same USE_CONTAINER semantics as lab (Job in-cluster vs init-install-v2.sh on bastion).
	@echo "Running Vault initialization via OpenShift Job..."
	@if [ "$(USE_CONTAINER)" = "true" ]; then \
		$(MAKE) create-vault-init-job || { echo "Error: Failed to create Vault init Job"; exit 1; }; \
		$(MAKE) wait-for-vault-init-job || { echo "Error: Vault init Job failed"; exit 1; }; \
	else \
		echo "Running initialization on localhost..."; \
		export HOSTNAME="vault-0"; \
		bash init-install-v2.sh; \
	fi
	@echo "Production environment setup completed."

# Create Vault initialization Job
create-vault-init-job:
	@echo "Creating Vault initialization Job..."
	@oc create namespace $(VAULT_NAMESPACE) --dry-run=client -o yaml | oc apply -f - || true
	@oc apply -f vault-init-job.yaml || { echo "Error: Failed to create Job resources"; exit 1; }
	@echo "Vault initialization Job created successfully."

# Wait for Vault initialization Job to complete
wait-for-vault-init-job:
	@echo "Waiting for Vault initialization Job to complete..."
	@/bin/bash -c ' \
		max_wait=1800; \
		elapsed=0; \
		interval=5; \
		while [ $$elapsed -lt $$max_wait ]; do \
			status=$$(oc get job vault-init-job -n $(VAULT_NAMESPACE) -o jsonpath="{.status.conditions[?(@.type==\"Complete\")].status}" 2>/dev/null || echo ""); \
			if [ "$$status" = "True" ]; then \
				echo "Vault initialization Job completed successfully"; \
				oc logs job/vault-init-job -n $(VAULT_NAMESPACE) --tail=50 || true; \
				exit 0; \
			fi; \
			failed=$$(oc get job vault-init-job -n $(VAULT_NAMESPACE) -o jsonpath="{.status.conditions[?(@.type==\"Failed\")].status}" 2>/dev/null || echo ""); \
			if [ "$$failed" = "True" ]; then \
				echo "ERROR: Vault initialization Job failed"; \
				oc logs job/vault-init-job -n $(VAULT_NAMESPACE) --tail=100 || true; \
				exit 1; \
			fi; \
			if [ $$((elapsed % 30)) -eq 0 ]; then \
				echo "Waiting for Job... ($$elapsed s / $$max_wait s)"; \
			fi; \
			sleep $$interval; \
			elapsed=$$((elapsed + interval)); \
		done; \
		echo "ERROR: Timeout waiting for Vault initialization Job"; \
		oc logs job/vault-init-job -n $(VAULT_NAMESPACE) --tail=100 || true; \
		exit 1 \
	'

# Clean order: init Job and its RBAC first (so nothing still references the SA), then Helm release (stops workloads),
# PVCs (released after StatefulSet goes), then project. Deleting the namespace before uninstall would strand resources
# or leave finalizers; removing the Job/RBAC first avoids permission errors during teardown.
# Clean up the Vault environment
clean:
	@echo "Cleaning up the Vault environment..."
	@-oc delete job vault-init-job -n $(VAULT_NAMESPACE) --ignore-not-found=true || true
	@-oc delete rolebinding vault-init-job vault-init-job-external-secrets -n $(VAULT_NAMESPACE) --ignore-not-found=true || true
	@-oc delete rolebinding vault-init-job-external-secrets -n external-secrets --ignore-not-found=true || true
	@-oc delete role vault-init-job -n $(VAULT_NAMESPACE) --ignore-not-found=true || true
	@-oc delete role vault-init-job-external-secrets -n external-secrets --ignore-not-found=true || true
	@-oc delete serviceaccount vault-init-job -n $(VAULT_NAMESPACE) --ignore-not-found=true || true
	@-helm uninstall vault -n $(VAULT_NAMESPACE) --wait --timeout 60s || true
	@-oc delete pvc --all -n $(VAULT_NAMESPACE) || true
	@-oc delete project $(VAULT_NAMESPACE) || true
	@echo "Vault environment cleaned."

# Bundles the same shell the Job (or docs) expect into the vault namespace so cluster-side init always matches repo
# contents without baking scripts into the Helm chart.
# Create ConfigMap for scripts (backup method)
create-configmap:
	@echo "Creating ConfigMap for initialization scripts..."
	@oc create namespace $(VAULT_NAMESPACE) --dry-run=client -o yaml | oc apply -f - || true
	@oc create configmap vault-init-scripts \
		--from-file=init-install-v2.sh=./init-install-v2.sh \
		-n $(VAULT_NAMESPACE) \
		--dry-run=client -o yaml | oc apply -f - || { echo "Warning: Failed to create ConfigMap"; }

# Note: Vault initialization can run either:
# - Containerized (default): Uses OpenShift Job (vault-init-job.yaml) which runs in-cluster
# - Localhost: Runs init-install-v2.sh directly on localhost/bastion

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
	@echo "  create-configmap   Create ConfigMap for initialization scripts (backup method)"
	@echo "  verify-init        Verify Vault initialization completed successfully"
	@echo "  help               Display this help message"
	@echo ""
	@echo "Execution Method:"
	@echo "  USE_CONTAINER=true  (default) - Run in podman container"
	@echo "  USE_CONTAINER=false           - Run on localhost/bastion"

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
define install_vault
	@echo "Installing Vault from chart $(1)..."
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
		-n $(2) \
		--create-namespace \
		--wait \
		--wait-for-jobs \
		--timeout 60s \
		$(if $(5),--version $(5),) || { echo "Error: Failed to install Vault"; exit 1; }
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
