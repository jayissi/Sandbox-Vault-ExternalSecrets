SHELL := /bin/bash
HELM_UPDATE_ESO := helm repo update external-secrets

.PHONY: install clean

install:
	helm repo add external-secrets https://charts.external-secrets.io
	eval "$(HELM_UPDATE_ESO)"
	helm install \
	  external-secrets \
	  external-secrets/external-secrets \
	  -f https://github.com/external-secrets/external-secrets/raw/main/deploy/charts/external-secrets/values.yaml \
	  -n external-secrets \
	  --create-namespace \
	  --wait \
	  --wait-for-jobs \
	  --timeout 60s

clean:
	-helm uninstall \
	  external-secrets \
	  -n external-secrets \
	  --wait \
	  --timeout 60s
	-oc delete project external-secrets
