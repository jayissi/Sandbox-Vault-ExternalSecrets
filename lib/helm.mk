# Shared Helm repository helpers and scheduling variables.
# Component Makefiles include this file.

# Optional JSON scheduling applied to all Helm installs.
# Edit these values to pin pods to labeled/tainted nodes.
# Example:
#   NODE_SELECTOR := {"node-role.kubernetes.io/infra":""}
#   TOLERATIONS   := [{"key":"node-role.kubernetes.io/infra","operator":"Exists","effect":"NoSchedule"}]
NODE_SELECTOR ?=
TOLERATIONS ?=

define add_helm_repo
	@echo "Adding Helm repository $(1)..."
	@helm repo add $(1) $(2) || { echo "Error: Failed to add Helm repository $(1)"; exit 1; }
endef

define update_helm_repo
	@echo "Updating Helm repository $(1)..."
	@helm repo update $(1) || { echo "Error: Failed to update Helm repository $(1)"; exit 1; }
endef
