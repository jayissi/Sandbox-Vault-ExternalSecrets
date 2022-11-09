#!/bin/bash
#
# This script is idempotent. Should be able to re-run it if something fails
# without manually cleaning up anything.
#

RECOVERY_JSON=$(oc get secret vault-recovery-keys -n vault-server -o jsonpath="{.data.recovery-keys\.json}" | base64 -d)
VAULT_ROOT_TOKEN=$(echo "$RECOVERY_JSON" | jq -r '.["root_token"]')
VAULT_URL=$(oc get routes vault-server -n vault-server -o jsonpath='{.spec.host}')

echo "Logging into Vault..."
oc exec -it -n vault-server vault-server-0 -- \
            vault login "$VAULT_ROOT_TOKEN"

echo "Creating Role in Vault for Kubernetes 'my-app' namespace..."
oc exec -it -n vault-server vault-server-0 -- \
            vault write \
            "auth/kubernetes/role/my-app" \
            bound_service_account_names="default" \
            bound_service_account_namespaces="my-app" \
            policies="kubernetes-read" \
            ttl=60m

echo "Creating 'my-app/message' secret in Vault..."
oc exec -it -n vault-server vault-server-0 -- \
            vault kv put \
            -mount=kubernetes \
            my-app/message \
            message="Hello world!"

echo "Deleting Kubernetes objects under './manifests'... (if they exist)"
oc delete -f ./manifests --wait

echo "Creating Kubernetes objects under './manifests'..."
oc create -f ./manifests/00-namespace.yaml
# SecretStore requires the Vault URL in it's spec. This command replaces the
# URL with the VAULT_URL pulled from OpenShift.
sed "s/replace\.me/$VAULT_URL/" ./manifests/01-secret-store.yaml | oc create -f -
oc create -f ./manifests/02-external-secret.yaml

cat << EOF

-----

If everything was successful, External Secrets should have created an OpenShift
Secret named *message* in the *my-app* namespace. Validate the secret exists
with:

$ oc get secrets -n my-app message

Print the contents of the secret with:

$ oc get secrets -n my-app message -o jsonpath="{.data.message}" | base64 -d

EOF
