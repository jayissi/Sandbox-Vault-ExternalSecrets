# Use Bash as the shell
SHELL := /bin/bash

# Suppress directory change messages
MAKEFLAGS += --no-print-directory

# Phony targets (targets that are not files)
.PHONY: dev lab prod dev-demo lab-demo prod-demo eso demo verify clean clean-demo clean-eso clean-hv help

# Directories
VAULT_DIR := ./hashicorp-vault-helm
EXTERNAL_SECRETS_DIR := ./external-secrets-helm
LAB_DIR := ./vault-external-secrets-lab

# Default target (run when no target is specified)
.DEFAULT_GOAL := help

# Deploy HashiCorp Vault development environment only
dev:
	@echo "Installing HashiCorp Vault (development mode only)..."
	@$(call run_make,dev,$(VAULT_DIR))
	@echo "Development HashiCorp Vault installation completed."

# Deploy HashiCorp Vault lab environment only
lab:
	@echo "Installing HashiCorp Vault (lab mode only)..."
	@$(call run_make,lab,$(VAULT_DIR))
	@echo "Lab HashiCorp Vault installation completed."

# Deploy HashiCorp Vault production environment only
prod:
	@echo "Installing HashiCorp Vault (production mode only)..."
	@$(call run_make,prod,$(VAULT_DIR))
	@echo "Production HashiCorp Vault installation completed."

# Deploy development environment setup w/ demo
dev-demo:
	@echo "Setting up development environment (Vault + ESO + demo)..."
	@$(call run_make,dev,$(VAULT_DIR))
	@$(call run_make,install,$(EXTERNAL_SECRETS_DIR))
	@$(call run_make,demo,$(LAB_DIR))
	@$(call run_make,verify,$(LAB_DIR))
	@echo "Development demo environment setup completed."

# Deploy lab environment setup w/ demo
lab-demo:
	@echo "Setting up lab environment (Vault + ESO + demo)..."
	@$(call run_make,lab,$(VAULT_DIR))
	@$(call run_make,install,$(EXTERNAL_SECRETS_DIR))
	@$(call run_make,demo,$(LAB_DIR))
	@$(call run_make,verify,$(LAB_DIR))
	@echo "Lab demo environment setup completed."

# Deploy production environment setup w/ demo
prod-demo:
	@echo "Setting up production environment (Vault + ESO + demo)..."
	@$(call run_make,prod,$(VAULT_DIR))
	@$(call run_make,install,$(EXTERNAL_SECRETS_DIR))
	@$(call run_make,demo,$(LAB_DIR))
	@$(call run_make,verify,$(LAB_DIR))
	@echo "Production demo environment setup completed."

# Deploy External Secrets Operator only
eso:
	@echo "Installing External Secrets Operator only..."
	@$(call run_make,install,$(EXTERNAL_SECRETS_DIR))
	@echo "External Secrets Operator installation completed."

# Configure Hashicorp Vault + External Secrets Operator with demo data
demo:
	@echo "Configuring Vault + ESO w/ demo data..."
	@$(call run_make,demo,$(LAB_DIR))
	@echo "Demo deployment completed."

# Verify the setup by running the verify-vault-openshift.sh script
verify:
	@echo "Initiate verify script..."
	@$(call run_make,verify,$(LAB_DIR))
	@echo "Verification script completed."

# Clean all environments
clean: clean-demo clean-eso clean-hv
	@echo "All environments cleaned."

# Clean demo environment
clean-demo:
	@echo "Cleaning demo environment..."
	@-$(call run_make,clean,$(LAB_DIR),true)
	@echo "Demo environment cleaned."

# Clean external-secrets environment
clean-eso:
	@echo "Cleaning external-secrets environment..."
	@-$(call run_make,clean,$(EXTERNAL_SECRETS_DIR),true)
	@echo "External-secrets environment cleaned."

# Clean hashicorp-vault environment
clean-hv:
	@echo "Cleaning hashicorp-vault environment..."
	@-$(call run_make,clean,$(VAULT_DIR),true)
	@echo "Hashicorp-vault environment cleaned."

# Display help information
help:
	@echo "Usage: make <target>"
	@echo ""
	@echo "Targets:"
	@echo "  dev           Install HashiCorp Vault (dev mode only)"
	@echo "  lab           Install HashiCorp Vault (lab mode only)"
	@echo "  prod          Install HashiCorp Vault (prod mode only)"
	@echo "  eso           Install ESO only (no Vault/demo)"
	@echo "  demo          Configure Vault + ESO with demo data (dependent on vault)"
	@echo "  verify        Validate (Vault + ESO + demo) configuration"
	@echo "  dev-demo      Deploy full dev setup (Vault + ESO + demo + verify)"
	@echo "  lab-demo      Deploy full lab setup (Vault + ESO + demo + verify)"
	@echo "  prod-demo     Deploy full prod setup (Vault + ESO + demo + verify)"
	@echo "  clean         Clean all environments (demo, external-secrets, hashicorp-vault)"
	@echo "  clean-demo    Clean the demo environment"
	@echo "  clean-eso     Clean the external-secrets environment"
	@echo "  clean-hv      Clean the hashicorp-vault environment"
	@echo "  help          Display this help message"

# Function to run make in a directory
define run_make
	@if [ -d "$(2)" ]; then \
		echo "Running 'make $(1)' in $(2)..."; \
		$(MAKE) $(1) --directory=$(2) || { echo "Error: Failed to run 'make $(1)' in $(2)"; exit 1; }; \
	else \
		echo "Error: Directory $(2) does not exist"; \
		exit 1; \
	fi
endef
