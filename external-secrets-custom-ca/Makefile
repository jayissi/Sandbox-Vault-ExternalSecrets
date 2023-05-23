SHELL := /bin/bash

.PHONY: install uninstall

install:
	@oc new-project external-secrets
	@oc get secret -n openshift-ingress router-certs-default \
	    -o go-template='{{index .data "tls.crt"}}' | \
	    base64 -d | sudo tee /etc/pki/ca-trust/source/anchors/$${HOST}.crt > ./ca-bundle.crt
	@oc create configmap ca-bundle \
	    --from-file=./ca-bundle.crt \
	    -n external-secrets
	@rm ./ca-bundle.crt
	helm repo add external-secrets https://charts.external-secrets.io
	helm install \
	  external-secrets \
	    external-secrets/external-secrets \
	    -f values.yaml \
	    -n external-secrets \
	    --version v0.8.1 \
	    --set installCRDs=true

uninstall:
	helm uninstall \
	  external-secrets \
	    --namespace external-secrets
	@oc delete \
	    configmap ca-bundle \
	    -n external-secrets
	@oc delete \
	    ns external-secrets
