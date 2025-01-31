# Use Bash as the shell
SHELL := /bin/bash

# Suppress directory change messages
MAKEFLAGS += --no-print-directory

# Phony targets (targets that are not files)
.PHONY: dev lab prod clean clean-demo clean-es clean-hv help

# Directories
VAULT_DIR := ./hashicorp-vault-helm
EXTERNAL_SECRETS_DIR := ./external-secrets-helm
LAB_DIR := ./vault-external-secrets-lab

# Default target (run when no target is specified)
.DEFAULT_GOAL := help

# Run development environment setup
dev:
	@echo "Setting up development environment..."
	@$(call run_make,dev,$(VAULT_DIR))
	@$(call run_make,install,$(EXTERNAL_SECRETS_DIR))
	@$(call run_make,demo,$(LAB_DIR))
	@echo "Development environment setup completed."

# Run lab environment setup
lab:
	@echo "Setting up lab environment..."
	@$(call run_make,lab,$(VAULT_DIR))
	@$(call run_make,install,$(EXTERNAL_SECRETS_DIR))
	@$(call run_make,demo,$(LAB_DIR))
	@echo "Lab environment setup completed."

# Run production environment setup
prod:
	@echo "Setting up production environment..."
	@$(call run_make,prod,$(VAULT_DIR))
	@$(call run_make,install,$(EXTERNAL_SECRETS_DIR))
	@$(call run_make,demo,$(LAB_DIR))
	@echo "Production environment setup completed."

# Clean all environments
clean: clean-demo clean-es clean-hv
	@echo "All environments cleaned."

# Clean demo environment
clean-demo:
	@echo "Cleaning demo environment..."
	@-$(call run_make,clean,$(LAB_DIR),true)
	@echo "Demo environment cleaned."

# Clean external-secrets environment
clean-es:
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
	@echo "  dev         Set up the development environment"
	@echo "  lab         Set up the lab environment"
	@echo "  prod        Set up the production environment"
	@echo "  clean       Clean all environments (demo, external-secrets, hashicorp-vault)"
	@echo "  clean-demo  Clean the demo environment"
	@echo "  clean-es    Clean the external-secrets environment"
	@echo "  clean-hv    Clean the hashicorp-vault environment"
	@echo "  help        Display this help message"

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
