# =============================================================================
# Two-phase Makefile: host dispatches to run.sh, container runs real recipes.
# =============================================================================
#
# This file is evaluated twice with different semantics:
#
#   1) Host (no WORKFLOW_IN_CONTAINER)
#      Targets are thin wrappers: each runs run.sh from the repo root with
#      WORKFLOW_TARGET=<target>. run.sh starts a podman container with the repo
#      mounted; workflow.sh then invokes make with WORKFLOW_IN_CONTAINER set — see (2).
#      Rationale: oc/kubectl and cluster credentials stay on the host; heavy work
#      runs in a quay.io/openshift/origin-cli image aligned with the cluster minor.
#
#   2) Inside origin-cli (WORKFLOW_IN_CONTAINER=1 from workflow.sh, invoked by run.sh)
#      The same targets expand to real recipes: $(call run_make,...) into
#      hashicorp-vault-helm, external-secrets-helm, and vault-external-secrets-lab.
#      Rationale: nested container dispatch is impossible here (no podman in
#      origin-cli), so sub-makes must run “bare” on the container filesystem.
#
# Container image: quay.io/openshift/origin-cli:<OCP minor> (see OCP_MINOR_VERSION).
# Prerequisites on host: oc logged in, or OPENSHIFT_* + credentials for run.sh.
#
# Invocation:  make <target>   (from repo root)
#              make <target>                        (from this directory)
# =============================================================================

SHELL := /bin/bash
MAKEFLAGS += --no-print-directory

REPO_ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))

# If unset, derive "4.18"-style minor from the live cluster so run.sh pulls
# origin-cli with matching client/API expectations. Override when offline or when
# you intentionally want a different image than desired.version suggests.
ifndef OCP_MINOR_VERSION
  OCP_MINOR_FROM_OC := $(shell oc get clusterversion version -o jsonpath='{.status.desired.version}' 2>/dev/null | cut -d. -f1,2)
  ifneq ($(strip $(OCP_MINOR_FROM_OC)),)
    export OCP_MINOR_VERSION := $(OCP_MINOR_FROM_OC)
  endif
endif

.PHONY: all test dev lab prod dev-demo lab-demo prod-demo eso demo verify clean clean-demo clean-eso clean-hv help

all: help

test: verify

.DEFAULT_GOAL := help

# ──────────────────────────────────────────────────────────────────────────────
ifdef WORKFLOW_IN_CONTAINER
# Second evaluation: real recipes. workflow.sh exports WORKFLOW_IN_CONTAINER=1
# before calling make; we only see this branch inside origin-cli, not on the host.
# ──────────────────────────────────────────────────────────────────────────────

# WORKFLOW_IN_CONTAINER is already exported by workflow.sh; subdirectory Makefiles
# use the same ifdef guard to detect they are inside origin-cli.

VAULT_DIR := ./hashicorp-vault-helm
EXTERNAL_SECRETS_DIR := ./external-secrets-helm
LAB_DIR := ./vault-external-secrets-lab

dev:
	@echo "Installing HashiCorp Vault (development mode only)..."
	@$(call run_make,dev,$(VAULT_DIR))
	@echo "Development HashiCorp Vault installation completed."

lab:
	@echo "Installing HashiCorp Vault (lab mode only)..."
	@$(call run_make,lab,$(VAULT_DIR))
	@echo "Lab HashiCorp Vault installation completed."

prod:
	@echo "Installing HashiCorp Vault (production mode only)..."
	@$(call run_make,prod,$(VAULT_DIR))
	@echo "Production HashiCorp Vault installation completed."

dev-demo:
	@echo "Setting up development environment (Vault + ESO + demo)..."
	@$(call run_make,dev,$(VAULT_DIR))
	@$(call run_make,install,$(EXTERNAL_SECRETS_DIR))
	@$(call run_make,demo,$(LAB_DIR))
	@$(call run_make,verify,$(LAB_DIR))
	@echo "Development demo environment setup completed."

lab-demo:
	@echo "Setting up lab environment (Vault + ESO + demo)..."
	@$(call run_make,lab,$(VAULT_DIR))
	@$(call run_make,install,$(EXTERNAL_SECRETS_DIR))
	@$(call run_make,demo,$(LAB_DIR))
	@$(call run_make,verify,$(LAB_DIR))
	@echo "Lab demo environment setup completed."

prod-demo:
	@echo "Setting up production environment (Vault + ESO + demo)..."
	@$(call run_make,prod,$(VAULT_DIR))
	@$(call run_make,install,$(EXTERNAL_SECRETS_DIR))
	@$(call run_make,demo,$(LAB_DIR))
	@$(call run_make,verify,$(LAB_DIR))
	@echo "Production demo environment setup completed."

eso:
	@echo "Installing External Secrets Operator only..."
	@$(call run_make,install,$(EXTERNAL_SECRETS_DIR))
	@echo "External Secrets Operator installation completed."

demo:
	@echo "Configuring Vault + ESO w/ demo data..."
	@$(call run_make,demo,$(LAB_DIR))
	@echo "Demo deployment completed."

verify:
	@echo "Initiate verify script..."
	@$(call run_make,verify,$(LAB_DIR))
	@echo "Verification script completed."

clean: clean-demo clean-eso clean-hv
	@echo "All environments cleaned."

clean-demo:
	@echo "Cleaning demo environment..."
	@-$(call run_make,clean,$(LAB_DIR))
	@echo "Demo environment cleaned."

clean-eso:
	@echo "Cleaning external-secrets environment..."
	@-$(call run_make,clean,$(EXTERNAL_SECRETS_DIR))
	@echo "External-secrets environment cleaned."

clean-hv:
	@echo "Cleaning hashicorp-vault environment..."
	@-$(call run_make,clean,$(VAULT_DIR))
	@echo "Hashicorp-vault environment cleaned."

# Delegate to component Makefiles. WORKFLOW_IN_CONTAINER is inherited from workflow.sh
# so subdirectory Makefiles know to run real recipes (not re-enter run.sh).
define run_make
	@if [ -d "$(2)" ]; then \
		echo "Running 'make $(1)' in $(2)..."; \
		$(MAKE) $(1) --directory=$(2) || { echo "Error: Failed to run 'make $(1)' in $(2)"; exit 1; }; \
	else \
		echo "Error: Directory $(2) does not exist"; \
		exit 1; \
	fi
endef

# ──────────────────────────────────────────────────────────────────────────────
else
# First evaluation (host): no real recipes here — only hand off to run.sh, which
# will re-invoke make with WORKFLOW_IN_CONTAINER for the branch above.
# ──────────────────────────────────────────────────────────────────────────────

# Repo-relative path to run.sh is fixed from REPO_ROOT so it works whether you
# WORKFLOW_TARGET selects the inner make goal.
define launch_container
	cd $(REPO_ROOT) && WORKFLOW_TARGET=$(1) ./run.sh
endef

dev:
	@$(call launch_container,dev)

lab:
	@$(call launch_container,lab)

prod:
	@$(call launch_container,prod)

dev-demo:
	@$(call launch_container,dev-demo)

lab-demo:
	@$(call launch_container,lab-demo)

prod-demo:
	@$(call launch_container,prod-demo)

eso:
	@$(call launch_container,eso)

demo:
	@$(call launch_container,demo)

verify:
	@$(call launch_container,verify)

clean:
	@$(call launch_container,clean)

clean-demo:
	@$(call launch_container,clean-demo)

clean-eso:
	@$(call launch_container,clean-eso)

clean-hv:
	@$(call launch_container,clean-hv)

endif

# ──────────────────────────────────────────────────────────────────────────────
# help stays outside ifdef/else: one definition, works on the host without
# podman/origin-cli (quick discovery) and inside the container without duplicating
# text or accidentally routing help through launch_container.
# ──────────────────────────────────────────────────────────────────────────────
help:
	@echo "Usage: make <target>"
	@echo ""
	@echo "All targets run inside a version-matched origin-cli container via run.sh."
	@echo "Requires: oc logged in on the host, or OPENSHIFT_API_URL + CLUSTER_ADMIN_* env vars."
	@echo "Optional: OCP_MINOR_VERSION to skip auto-detection."
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
	@echo ""
	@echo "Examples:"
	@echo "  make lab-demo                              # Full lab deploy in container"
	@echo "  OCP_MINOR_VERSION=4.18 make lab-demo        # Pin OCP version explicitly"
