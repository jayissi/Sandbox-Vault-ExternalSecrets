# Use Bash as the shell
SHELL := /bin/bash

# Suppress directory change messages
MAKEFLAGS += --no-print-directory

# Phony targets (targets that are not files)
.PHONY: all test install clean help

all: help

test:
	@echo "No tests available. Use the top-level 'make verify' target."

# Variables
HELM_REPO := external-secrets
HELM_REPO_URL := https://charts.external-secrets.io
CHART := external-secrets/external-secrets
NAMESPACE := external-secrets
VALUES_URL := https://github.com/external-secrets/external-secrets/raw/main/deploy/charts/external-secrets/values.yaml
# Shared OpenShift sandboxes often need several minutes (APIServer churn, image pulls, webhook/cert readiness); 15m
# avoids flaky installs that would pass on a quiet cluster but fail under load.
HELM_TIMEOUT := 15m

# Default target (run when no target is specified)
.DEFAULT_GOAL := help

LIB_MK := $(abspath $(dir $(lastword $(MAKEFILE_LIST)))/../lib/helm.mk)
include $(LIB_MK)

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
	@-helm uninstall $(HELM_REPO) -n $(NAMESPACE) --wait --timeout $(HELM_TIMEOUT) || true
	@-oc delete validatingwebhookconfiguration externalsecret-validate secretstore-validate --ignore-not-found=true 2>/dev/null || true
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

# install_chart(chart_ref, namespace, upstream_values_url): release name is HELM_REPO (e.g. "external-secrets") so
# upgrade/install is stable across runs; upstream values.yaml pins defaults, --wait/--wait-for-jobs block until the
# operator and hook Jobs are actually ready (not just chart applied); timeout uses HELM_TIMEOUT for the same reason.
# NODE_SELECTOR / TOLERATIONS (JSON): optional scheduling for all ESO pods via global.*.
define install_chart
	@echo "Installing Helm chart $(1)..."
	@if [ -n "$(NODE_SELECTOR)" ]; then echo "Node selector: $(NODE_SELECTOR)"; fi
	@if [ -n "$(TOLERATIONS)" ]; then echo "Tolerations: $(TOLERATIONS)"; fi
	@helm upgrade \
		$(HELM_REPO) \
		$(1) \
		--install \
		-f $(3) \
		$(if $(NODE_SELECTOR),--set-json 'global.nodeSelector=$(NODE_SELECTOR)',) \
		$(if $(TOLERATIONS),--set-json 'global.tolerations=$(TOLERATIONS)',) \
		-n $(2) \
		--create-namespace \
		--wait \
		--wait-for-jobs \
		--timeout $(HELM_TIMEOUT) || { echo "Error: Failed to install Helm chart $(1)"; exit 1; }
endef
