SHELL := /bin/bash

.PHONY: install install-ha uninstall

install:
	helm dependency update
	@printf vault.server.route.host=vault.$$(oc get ingresses.config.openshift.io cluster -o jsonpath'={.spec.domain}') | \
	xargs \
	helm install \
	    vault-server . \
	    --create-namespace \
	    --namespace vault-server \
	    --set 

install-ha:
	helm dependency update
	@printf vault.server.route.host=vault.$$(oc get ingresses.config.openshift.io cluster -o jsonpath'={.spec.domain}') | \
	xargs \
	helm install \
	    vault-server . \
	    --create-namespace \
	    --namespace vault-server \
	    --values values.yaml \
	    --values values.ha.yaml \
	    --set 

uninstall:
	helm uninstall \
	    --namespace vault-server \
	    vault-server
	oc delete project vault-server
