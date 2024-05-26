SHELL := /bin/bash

.PHONY: install uninstall 

install:
	helm install \
	  external-secrets \
	  external-secrets/external-secrets \
	  -f https://github.com/external-secrets/external-secrets/raw/main/deploy/charts/external-secrets/values.yaml \
	  -n external-secrets \
	  --create-namespace \
	  --wait \
	  --wait-for-jobs \
	  --timeout 60s

uninstall:
	-helm uninstall \
	  external-secrets \
	  -n external-secrets
	  --wait \
	  --timeout 60s
	-oc delete project external-secrets
