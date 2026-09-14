# Shared Helm repository helpers. Component Makefiles include this file.

define add_helm_repo
	@echo "Adding Helm repository $(1)..."
	@helm repo add $(1) $(2) || { echo "Error: Failed to add Helm repository $(1)"; exit 1; }
endef

define update_helm_repo
	@echo "Updating Helm repository $(1)..."
	@helm repo update $(1) || { echo "Error: Failed to update Helm repository $(1)"; exit 1; }
endef
