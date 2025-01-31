# Use Bash as the shell
SHELL := /bin/bash

# Suppress directory change messages
MAKEFLAGS += --no-print-directory

# Phony targets (targets that are not files)
.PHONY: install clean help

# Variables
HELM_REPO := external-secrets
HELM_REPO_URL := https://charts.external-secrets.io
CHART := external-secrets/external-secrets
NAMESPACE := external-secrets
VALUES_URL := https://github.com/external-secrets/external-secrets/raw/main/deploy/charts/external-secrets/values.yaml

# Default target (run when no target is specified)
.DEFAULT_GOAL := help

# Install External Secrets Operator
install:
	@echo "Installing External Secrets Operator..."
	@$(call add_helm_repo,$(HELM_REPO),$(HELM_REPO_URL))
	@$(call update_helm_repo,$(HELM_REPO))
	@$(call install_chart,$(CHART),$(NAMESPACE),$(VALUES_URL))
	@echo "External Secrets Operator installed successfully."

# Clean up the External Secrets Operator
clean:
	@echo "Cleaning up the External Secrets Operator..."
	@-helm uninstall $(HELM_REPO) -n $(NAMESPACE) --wait --timeout 60s || true
	@-oc delete project $(NAMESPACE) || true
	@echo "External Secrets Operator cleaned up."

# Display help information
help:
	@echo "Usage: make <target>"
	@echo ""
	@echo "Targets:"
	@echo "  install  Install the External Secrets Operator"
	@echo "  clean    Clean up the External Secrets Operator"
	@echo "  help     Display this help message"

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

# Function to install a Helm chart
define install_chart
	@echo "Installing Helm chart $(1)..."
	@helm install \
		$(HELM_REPO) \
		$(1) \
		-f $(3) \
		-n $(2) \
		--create-namespace \
		--wait \
		--wait-for-jobs \
		--timeout 60s || { echo "Error: Failed to install Helm chart $(1)"; exit 1; }
endef
