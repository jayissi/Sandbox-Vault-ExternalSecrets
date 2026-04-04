#!/bin/bash

# Debug mode
DEBUG=false

# Log function to display messages in a consistent format
function log() {
  local border_length=80
  local message="$1"
  local message_length=${#message}
  local padding_length=$(( (border_length - message_length - 2) / 2 )) # Subtract 2 for the "⎈" symbols
  local padding=$(printf '%*s' "$padding_length" "") # Create padding spaces

  # Center the message with padding
  echo "--------------------------------------------------------------------------------"
  echo "⎈${padding}${message}${padding}⎈"
  echo "--------------------------------------------------------------------------------"
}

# Function to check if a command exists and log the result
function check_command() {
  local cmd=$1
  if command -v "$cmd" > /dev/null 2>&1; then
    echo "Command '$cmd' found at $(command -v "$cmd")"
  else
    echo "Command '$cmd' not found. Please install it and try again."
    exit 1
  fi
}

# Check for required commands
check_command "jq"
check_command "oc"

# Define paths and variables
JQ=$(command -v jq)
OC_EXEC_VAULT="oc exec -n vault -i pods/vault-0 --"
APPROLE_SECRET="approle-vault"
VAULT_URL="oc get routes.route.openshift.io vault -n vault -o jsonpath --template='{.spec.host}{\"\n\"}'"

# Debug statement to print variables
if $DEBUG; then
  log "Debug: Variables"
  echo "JQ: $JQ"
  echo "OC_EXEC_VAULT: $OC_EXEC_VAULT"
  echo "APPROLE_SECRET: $APPROLE_SECRET"
  echo "VAULT_URL: $VAULT_URL"
fi

# Create 'secret/demo' secret
log "Create 'secret/demo' secret"
eval ${OC_EXEC_VAULT} vault kv put secret/demo Hello="World!" foo=bar Red_Hat=Linux

# Enable AppRole Auth Method
log "Enable AppRole Auth Method"
eval ${OC_EXEC_VAULT} vault auth enable approle > /dev/null 2>&1
echo "Success! Enabled approle auth method at: approle/"

# Create Vault Policy
log "Create Vault Policy"
eval ${OC_EXEC_VAULT} vault policy write demo -<< EOF > /dev/null 2>&1
# Read-only permission on secrets kv-v2 stored at 'secret/data/demo'
path "secret/data/demo" {
  capabilities = [ "read" ]
}
EOF
echo "Success! Uploaded policy: demo"

# Create Vault Role With Policy Attached
log "Create Vault Role With Policy Attached"
eval ${OC_EXEC_VAULT} vault write auth/approle/role/demo \
  token_policies="demo" \
  token_type="service" \
  token_num_uses=1 \
  token_period="7d" \
  token_ttl="7d" \
  bind_secret_id=true

# More info on Vault Tokens:
# https://developer.hashicorp.com/vault/api-docs/auth/token#create-token

# Create Vault RoleID and SecretID
log "Create Vault RoleID and SecretID"
readonly ROLE_ID_PAYLOAD=$(eval ${OC_EXEC_VAULT} vault read auth/approle/role/demo/role-id -format=json | ${JQ} -r '.')
readonly SECRET_ID_PAYLOAD=$(eval ${OC_EXEC_VAULT} vault write -f auth/approle/role/demo/secret-id -format=json | ${JQ} -r '.')

echo ${ROLE_ID_PAYLOAD} ${SECRET_ID_PAYLOAD} | ${JQ} -a

# Create 'demo' namespace with '${APPROLE_SECRET}' secret
log "Create 'demo' namespace with '${APPROLE_SECRET}' secret"
oc new-project demo > /dev/null 2>&1
echo "namespace/demo created"

# Update secret if ran multiple times
oc delete -n demo secret ${APPROLE_SECRET} > /dev/null 2>&1
oc create secret generic ${APPROLE_SECRET} \
  --from-literal=mount-type=$(echo ${ROLE_ID_PAYLOAD} | ${JQ} -r '.mount_type') \
  --from-literal=role-id=$(echo ${ROLE_ID_PAYLOAD} | ${JQ} -r '.data.role_id') \
  --from-literal=secret-id=$(echo ${SECRET_ID_PAYLOAD} | ${JQ} -r '.data.secret_id') \
  --from-literal=secret-id-accessor=$(echo ${SECRET_ID_PAYLOAD} | ${JQ} -r '.data.secret_id_accessor') \
  --from-literal=secret-id-num-uses=$(echo ${SECRET_ID_PAYLOAD} | ${JQ} -r '.data.secret_id_num_uses') \
  --from-literal=secret-id-ttl=$(echo ${SECRET_ID_PAYLOAD} | ${JQ} -r '.data.secret_id_ttl') \
  -n demo

# Create SecretStore and ExternalSecret with Parameter Values
log "Create SecretStore and ExternalSecret with Parameter Values"
oc process -f manifests/sandbox-vault-external-secrets-template.yaml \
  -p APPROLE_SECRET=${APPROLE_SECRET} \
  -p VAULT_URL=$(eval ${VAULT_URL}) -o yaml | \
  oc apply --wait=true -f -

log "Script execution completed."
