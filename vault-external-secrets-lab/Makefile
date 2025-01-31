# Use Bash as the shell
SHELL := /bin/bash

# Phony targets (targets that are not files)
.PHONY: demo clean verify help

# Variables
PROJECT_NAME := demo

# Default target (run when no target is specified)
.DEFAULT_GOAL := help

# Run the demo setup
demo:
	@echo "Setting up the demo..."
	@if ! source ./post-install-v3.sh; then \
		echo "Error: Failed to run post-install-v3.sh"; \
		exit 1; \
	fi
	@echo "Demo setup completed successfully."

# Clean up the demo environment
clean:
	@echo "Cleaning up the demo environment..."
	@if oc get project $(PROJECT_NAME) &> /dev/null; then \
		oc delete project $(PROJECT_NAME); \
		echo "Project '$(PROJECT_NAME)' deleted."; \
	else \
		echo "Project '$(PROJECT_NAME)' does not exist. Skipping deletion."; \
	fi

# Verify the setup by running the verify-vault-openshift.sh script
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
