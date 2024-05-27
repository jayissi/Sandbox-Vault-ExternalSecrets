#
#!/bin/bash
#

JQ="/usr/bin/jq"
OC_EXEC_VAULT="oc exec -n vault -ti vault-0 --"
APPROLE_CREDS_FILE="$PWD/.approle-creds.txt"
APPROLE_SECRET="approle-vault"
ROLE_ID="${JQ} -s -r '.[0].data.role_id' ${APPROLE_CREDS_FILE}"
SECRET_ID="${JQ} -s -r '.[1].data.secret_id' ${APPROLE_CREDS_FILE}"
VAULT_URL="oc get routes.route.openshift.io vault -n vault -o jsonpath --template='{.spec.host}{\"\n\"}'"



printf "\n\n\n"


echo "-------------------------------------------------------------------------------"
echo "⎈                          Create 'secret/demo' secret                       ⎈"
echo "-------------------------------------------------------------------------------"

eval ${OC_EXEC_VAULT} vault kv put secret/demo \
  Hello="World!" foo=bar Red_Hat=Linux


printf "\n\n\n"


echo "-------------------------------------------------------------------------------"
echo "⎈                         Enable AppRole Auth Method                         ⎈"
echo "-------------------------------------------------------------------------------"

eval ${OC_EXEC_VAULT} vault auth enable approle > /dev/null 2>&1
echo "Success! Enabled approle auth method at: approle/"


printf "\n\n\n"


echo "-------------------------------------------------------------------------------"
echo "⎈                             Create Vault Policy                            ⎈"
echo "-------------------------------------------------------------------------------"

eval ${OC_EXEC_VAULT} vault policy write demo -<< EOF > /dev/null 2>&1
# Read-only permission on secrets kv-v2 stored at 'secret/data/demo'
path "secret/data/demo" {
  capabilities = [ "read" ]
}
EOF
echo "Success! Uploaded policy: demo"


printf "\n\n\n"


echo "-------------------------------------------------------------------------------"
echo "⎈                    Create Vault Role With Policy Attached                  ⎈"
echo "-------------------------------------------------------------------------------"

eval ${OC_EXEC_VAULT} vault write auth/approle/role/demo \
  token_policies="demo" \
  token_type="service" \
  token_num_uses=1 \
  token_period="7d" \
  token_ttl="7d" \
  bind_secret_id=true

#
# More info on Vault Tokens:
# https://developer.hashicorp.com/vault/api-docs/auth/token#create-token
#


printf "\n\n\n"


echo "-------------------------------------------------------------------------------"
echo "⎈                       Create Vault RoleID and SecretID                     ⎈"
echo "-------------------------------------------------------------------------------"

eval ${OC_EXEC_VAULT} vault read auth/approle/role/demo/role-id -format=json | /usr/bin/tee ${APPROLE_CREDS_FILE}
eval ${OC_EXEC_VAULT} vault write -f auth/approle/role/demo/secret-id -format=json | /usr/bin/tee -a ${APPROLE_CREDS_FILE}


printf "\n\n\n"


echo "-------------------------------------------------------------------------------"
echo "⎈             Create 'demo' namespace with '${APPROLE_SECRET}' secret            ⎈"
echo "-------------------------------------------------------------------------------"

# stdout consistency
oc new-project demo > /dev/null 2>&1
echo "namespace/demo created"

# Update secret if ran multiple times
oc delete -n demo secret ${APPROLE_SECRET} > /dev/null 2>&1
oc create secret generic ${APPROLE_SECRET} \
  --from-literal=role-id=$(eval ${ROLE_ID}) \
  --from-literal=secret-id=$(eval ${SECRET_ID}) \
  -n demo


printf "\n\n\n"


echo "-------------------------------------------------------------------------------"
echo "⎈                   Create SecretStore with Parameter Values                 ⎈"
echo "-------------------------------------------------------------------------------"

oc process -f manifests/demo-secret-store-template.yaml \
  -p APPROLE_SECRET=${APPROLE_SECRET} \
  -p VAULT_URL=$(eval ${VAULT_URL}) -o yaml | \
  oc apply --wait=true -f -


printf "\n\n\n"


echo "-------------------------------------------------------------------------------"
echo "⎈                            Create ExternalSecret                           ⎈"
echo "-------------------------------------------------------------------------------"

oc apply --wait=true -f manifests/demo-external-secrets.yaml

printf "\n\n"
