SHELL := /bin/bash
VAULT_URL := $(shell echo vault.$$(oc get ingresses.config.openshift.io cluster -o jsonpath --template='{.spec.domain}'))
DEFAULT_STORAGE_CLASS := $$(oc get sc -o=jsonpath='{.items[?(@.metadata.annotations.storageclass\.kubernetes\.io\/is-default-class=="true")].metadata.name}')

.PHONY: dev lab prod uninstall 

dev:
	helm install \
	  vault \
	  hashicorp/vault \
          --set server.route.host=$(VAULT_URL) \
	  -f https://github.com/hashicorp/vault-helm/raw/main/values.openshift.yaml \
	  -f values.dev.yaml \
	  -n vault \
	  --create-namespace \
	  --wait \
	  --wait-for-jobs \
	  --timeout 60s

lab:
	helm install \
	  vault \
	  hashicorp/vault \
	  --set server.route.host=$(VAULT_URL) \
	  --set server.dataStorage.storageClass=$(DEFAULT_STORAGE_CLASS) \
	  --set server.auditStorage.storageClass=$(DEFAULT_STORAGE_CLASS) \
	  -f https://github.com/hashicorp/vault-helm/raw/main/values.openshift.yaml \
	  -f values.lab.yaml \
	  -n vault \
	  --create-namespace \
	  --wait \
	  --wait-for-jobs \
	  --timeout 60s
	source vault-init-install.sh

prod:
	helm install \
	  vault \
	  hashicorp/vault \
	  --set server.route.host=$(VAULT_URL) \
	  --set server.dataStorage.storageClass=$(DEFAULT_STORAGE_CLASS) \
	  --set server.auditStorage.storageClass=$(DEFAULT_STORAGE_CLASS) \
	  -f https://github.com/hashicorp/vault-helm/raw/main/values.openshift.yaml \
	  -f values.lab.yaml \
	  -f values.prod.yaml \
	  -n vault \
	  --create-namespace \
	  --wait \
	  --wait-for-jobs \
	  --timeout 60s
	source vault-init-install.sh

uninstall:
	-helm uninstall vault -n vault
	-oc delete pvc --all -n vault 
	-oc delete project vault
