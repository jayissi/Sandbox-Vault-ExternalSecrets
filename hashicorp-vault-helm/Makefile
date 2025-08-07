# Use Bash as the shell
SHELL := /bin/bash

# Suppress directory change messages
MAKEFLAGS += --no-print-directory

# Phony targets (targets that are not files)
.PHONY: dev lab prod clean help

# Variables
HELM_REPO := hashicorp
HELM_REPO_URL := https://helm.releases.hashicorp.com
VAULT_CHART := hashicorp/vault
VAULT_NAMESPACE := vault
VAULT_URL := $(shell echo vault.$$(oc get ingresses.config.openshift.io cluster -o jsonpath --template='{.spec.domain}'))
DEFAULT_STORAGE_CLASS := $(shell oc get sc -o=jsonpath='{.items[?(@.metadata.annotations.storageclass\.kubernetes\.io\/is-default-class=="true")].metadata.name}')
VERSION := 0.30.1

# Default target (run when no target is specified)
.DEFAULT_GOAL := help

# Run development environment setup
dev:
	@echo "Setting up development environment..."
	@$(call add_helm_repo,$(HELM_REPO),$(HELM_REPO_URL))
	@$(call update_helm_repo,$(HELM_REPO))
	@$(call install_vault,$(VAULT_CHART),$(VAULT_NAMESPACE),$(VAULT_URL),values.dev.yaml)
	@echo "Development environment setup completed."

# Run lab environment setup
lab:
	@echo "Setting up lab environment..."
	@$(call add_helm_repo,$(HELM_REPO),$(HELM_REPO_URL))
	@$(call update_helm_repo,$(HELM_REPO))
	@$(call install_vault,$(VAULT_CHART),$(VAULT_NAMESPACE),$(VAULT_URL),values.lab.yaml)
	@/bin/bash -c 'sleep 15s'
	@source ./init-install-v2.sh
	@echo "Lab environment setup completed."

# Run production environment setup
prod:
	@echo "Setting up production environment..."
	@$(call add_helm_repo,$(HELM_REPO),$(HELM_REPO_URL))
	@$(call update_helm_repo,$(HELM_REPO))
	@$(call install_vault,$(VAULT_CHART),$(VAULT_NAMESPACE),$(VAULT_URL),values.lab.yaml values.prod.yaml,$(VERSION))
	@/bin/bash -c 'sleep 15s'
	@source ./init-install-v2.sh
	@echo "Production environment setup completed."

# Clean up the Vault environment
clean:
	@echo "Cleaning up the Vault environment..."
	@-helm uninstall vault -n $(VAULT_NAMESPACE) --wait --timeout 60s || true
	@-oc delete pvc --all -n $(VAULT_NAMESPACE) || true
	@-oc delete project $(VAULT_NAMESPACE) || true
	@echo "Vault environment cleaned."

# Display help information
help:
	@echo "Usage: make <target>"
	@echo ""
	@echo "Targets:"
	@echo "  dev    Set up the development environment"
	@echo "  lab    Set up the lab environment"
	@echo "  prod   Set up the production environment"
	@echo "  clean  Clean up the Vault environment"
	@echo "  help   Display this help message"

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

# Function to install Vault
define install_vault
	@echo "Installing Vault from chart $(1)..."
	@helm install \
		vault \
		$(1) \
		--set server.route.host=$(3) \
		--set server.dataStorage.storageClass=$(DEFAULT_STORAGE_CLASS) \
		--set server.auditStorage.storageClass=$(DEFAULT_STORAGE_CLASS) \
		-f https://raw.githubusercontent.com/hashicorp/vault-helm/refs/heads/main/values.yaml \
		-f https://github.com/hashicorp/vault-helm/raw/main/values.openshift.yaml \
		$(foreach file,$(4),-f $(file)) \
		-n $(2) \
		--create-namespace \
		--wait \
		--wait-for-jobs \
		--timeout 60s \
		$(if $(5),--version $(5),) || { echo "Error: Failed to install Vault"; exit 1; }
endef
