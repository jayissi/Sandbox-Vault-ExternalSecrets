SHELL := /bin/bash

.PHONY: install uninstall 

install:
	helm install \
	  external-secrets \
	  external-secrets/external-secrets \
	  -n external-secrets \
	  --create-namespace \
	  --wait \
	  --wait-for-jobs \
	  --timeout 60s

uninstall:
	-helm uninstall \
	  external-secrets \
	  -n external-secrets
	-oc delete project external-secrets
