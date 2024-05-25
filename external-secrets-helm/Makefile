SHELL := /bin/bash

.PHONY: install uninstall 

install:
	helm install \
	  external-secrets \
	  external-secrets/external-secrets \
	  -n external-secrets \
	  --create-namespace

uninstall:
	-helm uninstall \
	  external-secrets \
	  -n external-secrets
	-oc delete project external-secrets
