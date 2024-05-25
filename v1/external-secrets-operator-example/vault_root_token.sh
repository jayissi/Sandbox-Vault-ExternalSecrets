#!/bin/bash

RECOVERY_JSON=$(oc get secret vault-recovery-keys -n vault-server -o jsonpath="{.data.recovery-keys\.json}" | base64 -d)
VAULT_ROOT_TOKEN=$(echo "$RECOVERY_JSON" | jq -r '.["root_token"]')
VAULT_URL=$(oc get routes vault-server -n vault-server -o jsonpath='{.spec.host}')

echo "Vault_URL: https://$VAULT_URL"
echo "Vault_Root_Token: $VAULT_ROOT_TOKEN"
