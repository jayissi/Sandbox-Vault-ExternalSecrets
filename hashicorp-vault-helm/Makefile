SHELL := /bin/bash

.PHONY: dev lab prod uninstall 

dev:
	helm install \
	  vault \
	  hashicorp/vault \
	  -f https://github.com/hashicorp/vault-helm/raw/main/values.openshift.yaml \
	  -f values.dev.yaml \
	  -n vault \
	  --create-namespace

lab:
	helm install \
	  vault \
	  hashicorp/vault \
	  -f https://github.com/hashicorp/vault-helm/raw/main/values.openshift.yaml \
	  -f values.lab.yaml \
	  -n vault \
	  --create-namespace

prod:
	helm install \
	  vault \
	  hashicorp/vault \
	  -f https://github.com/hashicorp/vault-helm/raw/main/values.openshift.yaml \
	  -f values.lab.yaml \
	  -f values.prod.yaml \
	  -n vault \
	  --create-namespace

uninstall:
	-helm uninstall vault -n vault
	-oc delete pvc --all -n vault 
	-oc delete project vault
