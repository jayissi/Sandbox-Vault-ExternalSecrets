SHELL := /bin/bash
VAULT_URL := $(shell echo vault.$$(oc get ingresses.config.openshift.io cluster -o jsonpath --template='{.spec.domain}'))
DEFAULT_STORAGE_CLASS := $$(oc get sc -o=jsonpath='{.items[?(@.metadata.annotations.storageclass\.kubernetes\.io\/is-default-class=="true")].metadata.name}')

.PHONY: dev lab prod clean

dev:
	helm install \
	  vault \
	  hashicorp/vault \
          --set server.route.host=$(VAULT_URL) \
	  -f values.dev.yaml \
	  -n vault \
	  --create-namespace \
	  --wait \
	  --wait-for-jobs \
	  --timeout 60s
	  #-f https://github.com/hashicorp/vault-helm/raw/main/values.openshift.yaml \

lab:
	helm install \
	  vault \
	  hashicorp/vault \
	  --set server.route.host=$(VAULT_URL) \
	  --set server.dataStorage.storageClass=$(DEFAULT_STORAGE_CLASS) \
	  --set server.auditStorage.storageClass=$(DEFAULT_STORAGE_CLASS) \
	  -f values.lab.yaml \
	  -n vault \
	  --create-namespace \
	  --wait \
	  --wait-for-jobs \
	  --timeout 60s
	@/bin/bash -c 'sleep 15s'
	source ./init-install.sh
	  #-f https://github.com/hashicorp/vault-helm/raw/main/values.openshift.yaml \

prod:
	helm install \
	  vault \
	  hashicorp/vault \
	  --set server.route.host=$(VAULT_URL) \
	  --set server.dataStorage.storageClass=$(DEFAULT_STORAGE_CLASS) \
	  --set server.auditStorage.storageClass=$(DEFAULT_STORAGE_CLASS) \
	  -f values.lab.yaml \
	  -f values.prod.yaml \
	  -n vault \
	  --create-namespace \
	  --wait \
	  --wait-for-jobs \
	  --timeout 60s
	@/bin/bash -c 'sleep 15s'
	source ./init-install.sh
	  #-f https://github.com/hashicorp/vault-helm/raw/main/values.openshift.yaml \

clean:
	-helm uninstall vault \
	  -n vault \
	  --wait \
	  --timeout 60s
	-oc delete pvc --all -n vault 
	-oc delete project vault
