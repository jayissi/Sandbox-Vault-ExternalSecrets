# =============================================================================
# Two-phase Makefile: host dispatches to run.sh, container runs real recipes.
# =============================================================================
#
# Same pattern as the top-level Makefile:
#   1) Host (no WORKFLOW_IN_CONTAINER): delegates to ../run.sh which launches
#      an origin-cli container, installs tools, then re-invokes via the
#      top-level Makefile → this Makefile with WORKFLOW_IN_CONTAINER set.
#   2) Inside origin-cli (WORKFLOW_IN_CONTAINER=1): real recipes run here.
#
# Targets that only need oc work on the host without a container and are
# defined outside the ifdef/else block.
# =============================================================================

# Use Bash as the shell
SHELL := /bin/bash

# Suppress directory change messages
MAKEFLAGS += --no-print-directory

# Phony targets (targets that are not files)
.PHONY: all test install clean status help

all: help

test:
	@echo "No tests available. Use the top-level 'make verify' target."

# Variables
OPERATOR_NAMESPACE := external-secrets-operator
OPERAND_NAMESPACE := external-secrets
MANIFESTS_DIR := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))/manifests
CSV_TIMEOUT := 10m
OPERAND_TIMEOUT := 5m

# Default target (run when no target is specified)
.DEFAULT_GOAL := help

# ──────────────────────────────────────────────────────────────────────────────
ifdef WORKFLOW_IN_CONTAINER
# Second evaluation: real recipes. workflow.sh exports WORKFLOW_IN_CONTAINER=1
# before calling make; we only see this branch inside origin-cli, not on the host.
# ──────────────────────────────────────────────────────────────────────────────

# Install External Secrets Operator via OLM
install:
	@echo "Installing External Secrets Operator via OLM..."
	@echo "Creating operator namespace..."
	@oc apply -f $(MANIFESTS_DIR)/namespace.yaml
	@echo "Creating OperatorGroup..."
	@oc apply -f $(MANIFESTS_DIR)/operatorgroup.yaml
	@echo "Creating Subscription..."
	@oc apply -f $(MANIFESTS_DIR)/subscription.yaml
	@echo "Waiting for CSV to succeed (timeout $(CSV_TIMEOUT))..."
	@for i in $$(seq 1 30); do \
		csv=$$(oc get csv -n $(OPERATOR_NAMESPACE) -l operators.coreos.com/openshift-external-secrets-operator.external-secrets-operator -o jsonpath='{.items[0].metadata.name}' 2>/dev/null) && \
		[ -n "$$csv" ] && break; \
		echo "  Waiting for CSV to appear... ($$i/30)"; \
		sleep 10; \
	done; \
	if [ -z "$$csv" ]; then \
		echo "Error: CSV did not appear within 5 minutes"; \
		exit 1; \
	fi; \
	echo "  Found CSV: $$csv"; \
	oc wait --for=jsonpath='{.status.phase}'=Succeeded csv/$$csv \
		-n $(OPERATOR_NAMESPACE) --timeout=$(CSV_TIMEOUT) || \
		{ echo "Error: CSV did not reach Succeeded phase"; exit 1; }
	@echo "Verifying operator pod is running..."
	@oc wait --for=condition=Available deployment -l app.kubernetes.io/name=external-secrets-operator \
		-n $(OPERATOR_NAMESPACE) --timeout=$(CSV_TIMEOUT) 2>/dev/null || \
		oc wait --for=condition=Ready pod -l name=external-secrets-operator \
		-n $(OPERATOR_NAMESPACE) --timeout=$(CSV_TIMEOUT) 2>/dev/null || true
	@echo "Applying ExternalSecretsConfig (operand deployment)..."
	@oc apply -f $(MANIFESTS_DIR)/externalsecretsconfig.yaml
	@echo "Waiting for operand pods in $(OPERAND_NAMESPACE) (timeout $(OPERAND_TIMEOUT))..."
	@for i in $$(seq 1 60); do \
		count=$$(oc get pods -n $(OPERAND_NAMESPACE) --no-headers 2>/dev/null | grep -c Running 2>/dev/null || true); \
		count=$${count:-0}; \
		if [ "$$count" -ge 3 ]; then \
			echo "  All operand pods are running ($$count pods)"; \
			break; \
		fi; \
		echo "  Waiting for operand pods... ($$count running, $$i/60)"; \
		sleep 5; \
	done
	@echo "Waiting for webhook endpoints to become available..."
	@for i in $$(seq 1 60); do \
		endpoints=$$(oc get endpoints external-secrets-webhook -n $(OPERAND_NAMESPACE) -o jsonpath='{.subsets[0].addresses[0].ip}' 2>/dev/null || echo ""); \
		if [ -n "$$endpoints" ]; then \
			echo "  Webhook endpoints are ready"; \
			break; \
		fi; \
		echo "  Waiting for webhook endpoints... ($$i/60)"; \
		sleep 5; \
	done
	@echo "External Secrets Operator installed successfully via OLM."

# Clean up the External Secrets Operator (OLM-managed)
clean:
	@echo "Cleaning up the External Secrets Operator (OLM)..."
	@echo "Deleting ExternalSecretsConfig..."
	@-oc delete externalsecretsconfig cluster --ignore-not-found=true 2>/dev/null || true
	@echo "Waiting for operand pods to terminate..."
	@-oc delete deployment -n $(OPERAND_NAMESPACE) -l app=external-secrets --ignore-not-found=true 2>/dev/null || true
	@sleep 5
	@echo "Deleting Subscription..."
	@-oc delete subscription openshift-external-secrets-operator -n $(OPERATOR_NAMESPACE) --ignore-not-found=true 2>/dev/null || true
	@echo "Deleting CSV..."
	@-oc delete csv -n $(OPERATOR_NAMESPACE) -l operators.coreos.com/openshift-external-secrets-operator.external-secrets-operator --ignore-not-found=true 2>/dev/null || true
	@echo "Deleting OperatorGroup..."
	@-oc delete operatorgroup openshift-external-secrets-operator -n $(OPERATOR_NAMESPACE) --ignore-not-found=true 2>/dev/null || true
	@echo "Deleting validating webhooks..."
	@-oc delete validatingwebhookconfiguration externalsecret-validate secretstore-validate --ignore-not-found=true 2>/dev/null || true
	@echo "Deleting CRDs..."
	@-oc delete customresourcedefinitions.apiextensions.k8s.io -l external-secrets.io/component=controller --ignore-not-found=true 2>/dev/null || true
	@echo "Deleting operand namespace resources..."
	@-oc delete svc --all -n $(OPERAND_NAMESPACE) --ignore-not-found=true 2>/dev/null || true
	@echo "Deleting operand namespace..."
	@-oc delete project $(OPERAND_NAMESPACE) --ignore-not-found=true 2>/dev/null || true
	@echo "Deleting operator namespace..."
	@-oc delete project $(OPERATOR_NAMESPACE) --ignore-not-found=true 2>/dev/null || true
	@echo "External Secrets Operator cleaned up."

# Show operator and operand status
status:
	@echo "=== External Secrets Operator Status ==="
	@echo ""
	@echo "--- Subscription ---"
	@oc get subscription -n $(OPERATOR_NAMESPACE) 2>/dev/null || echo "  No subscription found"
	@echo ""
	@echo "--- ClusterServiceVersion ---"
	@oc get csv -n $(OPERATOR_NAMESPACE) 2>/dev/null || echo "  No CSV found"
	@echo ""
	@echo "--- Operator Pod ---"
	@oc get pods -n $(OPERATOR_NAMESPACE) 2>/dev/null || echo "  No operator pods found"
	@echo ""
	@echo "--- ExternalSecretsConfig ---"
	@oc get externalsecretsconfig cluster -o wide 2>/dev/null || echo "  No ExternalSecretsConfig found"
	@echo ""
	@echo "--- ExternalSecretsConfig Conditions ---"
	@oc get externalsecretsconfig cluster -o jsonpath='{.status.conditions}' 2>/dev/null | \
		python3 -m json.tool 2>/dev/null || \
		oc get externalsecretsconfig cluster -o jsonpath='{.status.conditions}' 2>/dev/null || \
		echo "  No conditions available"
	@echo ""
	@echo "--- Operand Pods ---"
	@oc get pods -n $(OPERAND_NAMESPACE) 2>/dev/null || echo "  No operand pods found"

# ──────────────────────────────────────────────────────────────────────────────
else
# First evaluation (host): no real recipes here — only hand off to run.sh, which
# will re-invoke make with WORKFLOW_IN_CONTAINER for the branch above.
# ──────────────────────────────────────────────────────────────────────────────

REPO_ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST)))/..)

define launch_container
	cd $(REPO_ROOT) && WORKFLOW_TARGET=$(1) ./run.sh
endef

install:
	@$(call launch_container,eso)

clean:
	@$(call launch_container,clean-eso)

status:
	@$(call launch_container,eso-status)

endif

# ──────────────────────────────────────────────────────────────────────────────
# help stays outside ifdef/else: works on both host and container.
# ──────────────────────────────────────────────────────────────────────────────
help:
	@echo "Usage: make <target>"
	@echo ""
	@echo "External Secrets Operator (OLM-managed) targets:"
	@echo ""
	@echo "Targets:"
	@echo "  install  Install the External Secrets Operator via OLM"
	@echo "  clean    Clean up the External Secrets Operator (OLM resources)"
	@echo "  status   Show operator and operand status"
	@echo "  help     Display this help message"
