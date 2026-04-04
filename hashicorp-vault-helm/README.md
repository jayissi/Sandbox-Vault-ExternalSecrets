# HashiCorp Vault Helm Deployment

This directory manages the HashiCorp Vault deployment on OpenShift via Helm.

## Targets

```bash
make help
```

| Target | Description |
|--------|-------------|
| `dev` | Deploy Vault in dev server mode (single instance, no init required) |
| `lab` | Deploy Vault in lab mode (single instance, auto-init + unseal) |
| `prod` | Deploy Vault in prod mode (3-node HA Raft, auto-init + unseal) |
| `clean` | Remove Vault (Helm release, PVCs, RBAC, namespace) |
| `create-configmap` | Create ConfigMap with init scripts (used by lab/prod) |
| `verify-init` | Verify Vault is initialized and unsealed |

## How It Works

### Dev Mode

Vault starts in [dev server mode](https://developer.hashicorp.com/vault/docs/concepts/dev-server) — automatically initialized and unsealed with an in-memory backend. No persistent storage.

```bash
make dev
```

### Lab Mode

Single-instance Vault with persistent storage (10Gi data + 10Gi audit). After Helm install, `init-install-v2.sh` runs to:

1. Initialize Vault (5 unseal shares, threshold of 3)
2. Store root token + unseal keys in an OpenShift Secret (`vault-operator-init`)
3. Unseal with 3 randomly selected keys
4. Authenticate with root token
5. Enable audit logging (file + socket)
6. Enable KV-V2 secret engine at `secret/`

```bash
make lab
```

### Prod Mode

Three-node HA Raft cluster. Same initialization as lab, plus:
- Standby nodes join the Raft cluster via `vault operator raft join`
- Each standby is unsealed and authenticated individually

```bash
make prod
```

## Files

| File | Purpose |
|------|---------|
| `Makefile` | Orchestrates Helm install, init, and cleanup |
| `init-install-v2.sh` | Vault initialization, unsealing, audit, and KV engine setup |
| `values.dev.yaml` | Helm values for dev (dev server mode, edge TLS route) |
| `values.lab.yaml` | Helm values for lab (standalone, PVC storage, edge TLS route) |
| `values.prod.yaml` | Helm values for prod (HA Raft, 3 replicas) |
| `run-in-podman.sh` | Helper: run a make target inside an origin-cli container |
| `run-init-container.sh` | Helper: run init inside a container (standalone mode) |

## Key Variables (Makefile)

| Variable | Source | Description |
|----------|--------|-------------|
| `VAULT_URL` | `oc get ingresses.config` | Dynamically resolved Vault route hostname |
| `DEFAULT_STORAGE_CLASS` | `oc get sc` | Cluster's default StorageClass |
| `VERSION` | Hardcoded (`0.30.1`) | Vault Helm chart version (prod only) |
| `USE_CONTAINER` | Default `true` | `true` = use OpenShift Job for init, `false` = run locally |
