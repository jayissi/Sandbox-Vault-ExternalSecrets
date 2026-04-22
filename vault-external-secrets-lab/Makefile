# Lab automation: thin wrappers so admins run one command for setup, teardown, or validation
# without memorizing script paths or flags.
#
# Use Bash as the shell
SHELL := /bin/bash

# Suppress directory change messages
MAKEFLAGS += --no-print-directory

# Phony targets (targets that are not files)
.PHONY: all test demo clean verify help

all: help

test: verify

# Variables
PROJECT_NAME := demo

# Default target (run when no target is specified)
.DEFAULT_GOAL := help

# demo: single entry point for the full lab. Invokes post-install-v3.sh, which seeds KV data in
# Vault, enables AppRole and a demo policy/role, materializes AppRole credentials into an
# OpenShift Secret, then applies the SecretStore and ExternalSecret so ESO can sync Vault into the cluster.
demo:
	@echo "Setting up the demo..."
	@if ! bash ./post-install-v3.sh; then \
		echo "Error: Failed to run post-install-v3.sh"; \
		exit 1; \
	fi
	@echo "Demo setup completed successfully."

# clean: removes the demo namespace/project so the next demo run starts from a known empty state
# (avoids stale Secrets or CRs confusing operators or the next operator).
clean:
	@echo "Cleaning up the demo environment..."
	@-oc delete secretstore,externalsecret --all -n $(PROJECT_NAME) --force --grace-period=0 2>/dev/null || true
	@if oc get project $(PROJECT_NAME) &> /dev/null; then \
		oc delete project $(PROJECT_NAME); \
		echo "Project '$(PROJECT_NAME)' deleted."; \
	else \
		echo "Project '$(PROJECT_NAME)' does not exist. Skipping deletion."; \
	fi

# verify: runs the end-to-end checker (Vault reachable, ESO, SecretStore/ExternalSecret, synced secrets)
# — use after demo or when troubleshooting “secrets not appearing” reports.
verify:
	@echo "Verifying the setup..."
	@if ! ./verify-vault-openshift.sh; then \
		echo "Error: Failed to run verify-vault-openshift.sh"; \
		exit 1; \
	fi
	@echo "Verification completed successfully."

# Display help information
help:
	@echo "Usage: make <target>"
	@echo ""
	@echo "Targets:"
	@echo "  demo    Set up the demo environment by running post-install-v3.sh"
	@echo "  clean   Clean up the demo environment by deleting the '$(PROJECT_NAME)' project"
	@echo "  verify  Verify the setup by running verify-vault-openshift.sh"
	@echo "  help    Display this help message"
