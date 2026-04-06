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

### Auto-Unseal Sidecar (Optional)

When `VAULT_AUTO_UNSEAL=true`, a sidecar container is added to each Vault pod that:
- Monitors Vault's seal status every 10 seconds
- Automatically unseals Vault when pods restart using keys from `vault-operator-init` secret
- Authenticates the Vault CLI using Kubernetes Auth (least privilege)

```bash
VAULT_AUTO_UNSEAL=true make lab
VAULT_AUTO_UNSEAL=true make prod
```

**Least Privilege Authentication:**

The sidecar uses a two-tier authentication strategy:
1. **Primary:** Kubernetes Auth with `vault-ops` role (15-minute TTL)
2. **Fallback:** Root token (only during initial setup before K8s Auth is configured)

The `vault-ops` policy grants minimal permissions:
| Path | Capabilities |
|------|--------------|
| `sys/storage/raft/configuration` | read |
| `sys/seal-status` | read |
| `sys/health` | read, sudo |
| `sys/auth` | read |

This means operational commands like `vault operator raft list-peers` work, but administrative commands like `vault secrets list` are denied.

## Files

| File | Purpose |
|------|---------|
| `Makefile` | Orchestrates Helm install, init, and cleanup |
| `init-install-v2.sh` | Vault initialization, unsealing, audit, KV engine, and Kubernetes Auth setup |
| `values.dev.yaml` | Helm values for dev (dev server mode, edge TLS route) |
| `values.lab.yaml` | Helm values for lab (standalone, PVC storage, edge TLS route) |
| `values.prod.yaml` | Helm values for prod (HA Raft, 3 replicas) |
| `values.auto-unseal.yaml` | Helm values overlay for auto-unseal sidecar (K8s Auth + fallback) |
| `vault-auto-unseal.sh` | Standalone reference script for auto-unseal sidecar logic |
| `run-in-podman.sh` | Helper: run a make target inside an origin-cli container |
| `run-init-container.sh` | Helper: run init inside a container (standalone mode) |

## Key Variables (Makefile)

| Variable | Source | Description |
|----------|--------|-------------|
| `VAULT_URL` | `oc get ingresses.config` | Dynamically resolved Vault route hostname |
| `DEFAULT_STORAGE_CLASS` | `oc get sc` | Cluster's default StorageClass |
| `VERSION` | Hardcoded (`0.30.1`) | Vault Helm chart version (prod only) |
| `USE_CONTAINER` | Default `true` | `true` = use OpenShift Job for init, `false` = run locally |
| `VAULT_AUTO_UNSEAL` | Default `false` | `true` = add auto-unseal sidecar with K8s Auth |
