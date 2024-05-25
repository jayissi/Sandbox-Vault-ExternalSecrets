SHELL := /bin/bash
VAULT_URL := $$(oc get routes.route.openshift.io vault -n vault -o jsonpath --template='{.spec.host}')
VAULT_SHELL := oc exec -n vault -ti vault-0 --
ROLE_ID := $$(/usr/bin/jq -s '.[0].data.role_id' .approle-creds.txt | tr -d ='"'=)
SECRET_ID := $$(/usr/bin/jq -s '.[1].data.secret_id' .approle-creds.txt | tr -d ='"'=)

.PHONY: demo clean-up

demo:
	source demo-vault-policy.sh
	$(VAULT_SHELL) vault kv put secret/demo \
	  Hello="World!" foo=bar Red_Hat=Linux
	-$(VAULT_SHELL) vault auth enable approle
	$(VAULT_SHELL) vault write auth/approle/role/demo \
	  token_policies="demo" period=0	
	$(VAULT_SHELL) vault read auth/approle/role/demo/role-id -format=json > .approle-creds.txt
	$(VAULT_SHELL) vault write -f auth/approle/role/demo/secret-id -format=json >> .approle-creds.txt
	-oc new-project demo
	-oc create secret generic approle-secret --from-literal=secret-id=$(SECRET_ID) -n demo
	oc process -f demo-secret-store-template.yaml -p ROLE_ID=$(ROLE_ID) -p VAULT_URL=$(VAULT_URL) -o yaml | oc apply --wait=true -f -
	oc apply --wait=true -f demo-external-secrets.yaml
.PHONY: demo

clean-up:
	oc delete project demo
.PHONY: clean-up
