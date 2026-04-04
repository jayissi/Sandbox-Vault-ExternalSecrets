# Vault External Secrets Lab

This directory contains the demo data setup and end-to-end verification for the Vault + ESO integration.

## Targets

```bash
make help
```

| Target | Description |
|--------|-------------|
| `demo` | Seed Vault with demo data, create AppRole, apply ESO manifests |
| `verify` | Validate the full chain: Vault → ESO → synced OpenShift Secret |
| `clean` | Remove the `demo` namespace and all its resources |

## Demo Setup (`make demo`)

The `post-install-v3.sh` script performs these steps in order:

1. **Create demo secret in Vault:** `vault kv put secret/demo Hello='World!' foo=bar Red_Hat=Linux`
2. **Enable AppRole auth:** `vault auth enable approle`
3. **Create Vault policy:** Grants read access to `secret/data/demo`
4. **Create AppRole role:** `demo` role with the policy attached
5. **Retrieve credentials:** Fetches RoleID and SecretID from Vault
6. **Create OpenShift namespace:** `oc create namespace demo`
7. **Create AppRole secret:** Stores RoleID/SecretID in `approle-vault` Secret
8. **Wait for CRDs:** Ensures ExternalSecret CRD is registered before applying
9. **Apply manifests:** `SecretStore` (points to Vault) and `ExternalSecret` (syncs `secret/demo`)

After completion, ESO automatically syncs the Vault secret into an OpenShift Secret named `demo` in the `demo` namespace.

## Verification (`make verify`)

The `verify-vault-openshift.sh` script checks:

| Check | What It Validates |
|-------|------------------|
| Vault URL | Route is reachable (HTTP 200) |
| Vault policy | `demo` policy exists |
| Vault secret | `secret/demo` exists with expected data |
| AppRole auth | `approle` auth method is enabled |
| ESO pods | External Secrets Operator pods are running |
| ExternalSecret | CR exists and status is `SecretSynced` |
| SecretStore | CR exists and status is `Valid` |
| `approle-vault` | Secret contains role-id and secret-id |
| `demo` | Secret contains `Hello: World!`, `foo: bar`, `Red_Hat: Linux` |

## Example: Verify Demo Secret Manually

```bash
# Decoded secret contents
oc get secret demo -n demo -o jsonpath='{.data}' \
  | jq -r 'to_entries[] | "\(.key): \(.value | @base64d)"'

# Extract to stdout
oc extract secret/demo -n demo --to=-
```

## Files

| File | Purpose |
|------|---------|
| `Makefile` | Thin wrappers for demo/clean/verify |
| `post-install-v3.sh` | Demo data + AppRole + ESO manifest setup |
| `verify-vault-openshift.sh` | End-to-end validation script |
| `manifests/sandbox-vault-external-secrets-template.yaml` | OpenShift template for SecretStore + ExternalSecret |
