# Sandbox Vault ExternalSecrets

[![RHEL 9+](https://img.shields.io/badge/RHEL-9+-ee0000?logo=redhat&logoColor=ee0000&labelColor=black)](https://www.redhat.com/en/technologies/linux-platforms/enterprise-linux)
[![Kubernetes](https://img.shields.io/badge/Kubernetes-v1.31+-326CE5?logo=kubernetes&logoColor=326CE5&labelColor=white)](https://kubernetes.io/)
[![Openshift](https://img.shields.io/badge/Openshift-v4.16+-EE0000?logo=redhatopenshift&logoColor=EE0000&labelColor=black)](https://www.redhat.com/en/technologies/linux-platforms/enterprise-linux)
[![Helm](https://img.shields.io/badge/Helm-v3.12+-0F1689?logo=helm&logoColor=0F1689&labelColor=white)](https://helm.sh/docs)
[![GNU GPL v3.0](https://img.shields.io/badge/GNU%20GPL-v3.0-A42E2B?logo=gnu&logoColor=A42E2B&labelColor=white)](https://www.gnu.org/licenses)

---

Welcome to the **Sandbox Vault External Secrets** project! This project provides an automated deployment and integration of [HashiCorp Vault](https://github.com/hashicorp/vault-helm) and [External Secrets Operator](https://github.com/external-secrets/external-secrets) on OpenShift. It serves as a hands-on platform to explore secure secrets management, whether you're new to Vault or integrating it into existing infrastructure.

---

## Table of Contents

- [How It Works](#how-it-works)
- [Requirements](#requirements)
- [Quick Start](#quick-start)
- [Available Targets](#available-targets)
- [Workflow: Start to Finish](#workflow-start-to-finish)
- [Architecture Overview](#architecture-overview)
- [Project Structure](#project-structure)
- [Uninstall](#uninstall)
- [Configuration Reference](#configuration-reference)
- [License](#license)

---

## How It Works

Every `make` target runs inside a version-matched `quay.io/openshift/origin-cli` container, so the only host dependency is `oc` (logged in) and `podman`. The workflow is:

```
Host                            Container (origin-cli)
────                            ──────────────────────
make lab-demo
  └─ run.sh                     ← discovers OCP minor, launches container
       └─ workflow.sh           ← installs make/jq/helm, validates versions
            └─ make lab-demo    ← re-enters Makefile with WORKFLOW_IN_CONTAINER=1
                 ├─ make lab      (hashicorp-vault-helm/)
                 ├─ make install  (external-secrets-helm/)
                 ├─ make demo     (vault-external-secrets-lab/)
                 └─ make verify   (vault-external-secrets-lab/)
```

The Makefile uses `ifdef WORKFLOW_IN_CONTAINER` to split behavior:
- **Host side (default):** thin wrappers that dispatch to `run.sh`
- **Container side:** real orchestration calling sub-directory Makefiles

---

## Requirements

| Tool | Version | Purpose |
|------|---------|---------|
| OpenShift cluster | 4.16+ | Target platform |
| `oc` CLI | Matching cluster | Cluster interactions |
| `podman` (or Docker) | Any recent | Container execution |

> **Note:** `make`, `jq`, and `helm` are installed automatically inside the container — no host installation needed.

---

## Quick Start

```bash
# 1. Clone and enter the repo
git clone https://github.com/jayissi/Sandbox-Vault-ExternalSecrets.git
cd Sandbox-Vault-ExternalSecrets

# 2. Log in to your OpenShift cluster
oc login --server=https://api.your-cluster.example.com:6443

# 3. Deploy a full lab environment with demo secrets
make lab-demo

# 4. Verify everything is working
make verify

# 5. Check the synced demo secret
oc get secret demo -n demo -o jsonpath='{.data}' | jq -r 'to_entries[] | "\(.key): \(.value | @base64d)"'
# Output:
#   Hello: World!
#   Red_Hat: Linux
#   foo: bar

# 6. Clean up when done
make clean
```

---

## Available Targets

```
make help
```

| Target | Description |
|--------|-------------|
| `dev` | Install HashiCorp Vault in dev mode (standalone, no init required) |
| `lab` | Install HashiCorp Vault in lab mode (single instance, auto-init + unseal) |
| `prod` | Install HashiCorp Vault in prod mode (3-node HA Raft cluster, auto-init + unseal) |
| `eso` | Install External Secrets Operator only |
| `demo` | Configure Vault with demo data + AppRole + ESO manifests (requires Vault) |
| `verify` | Validate the full chain: Vault → ESO → demo secret |
| `dev-demo` | Full dev setup: Vault (dev) + ESO + demo + verify |
| `lab-demo` | Full lab setup: Vault (lab) + ESO + demo + verify |
| `prod-demo` | Full prod setup: Vault (prod HA) + ESO + demo + verify |
| `clean` | Remove all environments (demo, external-secrets, vault) |
| `clean-demo` | Remove demo namespace only |
| `clean-eso` | Remove External Secrets Operator only |
| `clean-hv` | Remove HashiCorp Vault only |

**Examples:**

```bash
# Deploy production HA Vault + ESO + demo secrets
make prod-demo

# Override OCP version (skip auto-detection)
OCP_MINOR_VERSION=4.18 make lab-demo

# Use Docker instead of Podman
CONTAINER_ENGINE=docker make lab-demo

# Run init scripts on localhost instead of in-container
USE_CONTAINER=false make lab-demo

# Deploy only Vault (no ESO/demo)
make lab
```

---

## Workflow: Start to Finish

### 1. Deploy Vault

Vault is installed via its official Helm chart. The environment determines the topology:

| Environment | Instances | Storage | Init Required |
|-------------|-----------|---------|---------------|
| `dev` | 1 (dev server mode) | In-memory | No |
| `lab` | 1 (standalone) | PVC (10Gi data + 10Gi audit) | Yes (auto) |
| `prod` | 3 (HA Raft) | PVC (10Gi data + 10Gi audit per node) | Yes (auto) |

### 2. Initialize & Unseal (lab/prod only)

The `init-install-v2.sh` script:
1. Initializes Vault with 5 unseal shares and a threshold of 3
2. Stores the root token and unseal keys in an OpenShift Secret (`vault-operator-init`)
3. Unseals each pod with a random subset of 3 keys
4. Logs in with the root token
5. Enables audit logging (file + socket)
6. For prod: joins standby nodes to the Raft cluster before unsealing
7. Enables the KV-V2 secret engine at `secret/`
8. Enables Kubernetes authentication and creates a least-privilege `vault-ops` policy/role

### 2a. Auto-Unseal Sidecar (optional)

When `VAULT_AUTO_UNSEAL=true`, an auto-unseal sidecar container is added to each Vault pod. This sidecar:
- Monitors Vault's seal status at regular intervals
- Automatically unseals Vault pods when they restart (using keys from `vault-operator-init` secret)
- Authenticates the Vault CLI using **Kubernetes Auth** (least privilege) with fallback to root token

**Authentication Strategy:**
1. **Primary:** Kubernetes Auth with `vault-ops` role (limited to `sys/storage/raft/configuration`, `sys/seal-status`, `sys/health`, `sys/auth`)
2. **Fallback:** Root token (only during initial setup before Kubernetes Auth is configured)

This ensures operational commands like `vault operator raft list-peers` work after pod restarts, while administrative commands like `vault secrets list` are denied (confirming least privilege).

### 3. Install External Secrets Operator

ESO is installed via Helm chart into the `external-secrets` namespace. The operator watches for `SecretStore` and `ExternalSecret` resources.

### 4. Configure Demo Data

The `post-install-v3.sh` script:
1. Creates a demo secret in Vault: `secret/demo` with `Hello=World!`, `foo=bar`, `Red_Hat=Linux`
2. Enables AppRole authentication
3. Creates a Vault policy granting read access to `secret/data/demo`
4. Creates an AppRole role (`demo`) with the policy attached
5. Retrieves the RoleID and SecretID
6. Creates the `demo` namespace and an OpenShift Secret (`approle-vault`) with the AppRole credentials
7. Applies the `SecretStore` and `ExternalSecret` manifests

### 5. Verify

The `verify-vault-openshift.sh` script validates:
- Vault is reachable via its route (HTTPS)
- Vault policy, secret, and AppRole auth exist
- ESO pods are running
- `SecretStore` and `ExternalSecret` are synced
- The `demo` secret in OpenShift contains the expected values

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                     OpenShift Cluster                           │
│                                                                 │
│  ┌──────────────────┐  ┌─────────────────────────────────────┐  │
│  │  vault namespace  │  │   external-secrets namespace        │  │
│  │                    │  │                                     │  │
│  │  vault-0 (active)  │  │  external-secrets-controller       │  │
│  │  vault-1 (standby) │  │  external-secrets-webhook          │  │
│  │  vault-2 (standby) │  │  external-secrets-cert-controller  │  │
│  │                    │  │                                     │  │
│  │  Secret:           │  └──────────────┬──────────────────────┘  │
│  │  vault-operator-   │                 │                         │
│  │  init (root token  │                 │ watches                 │
│  │  + unseal keys)    │                 ▼                         │
│  └────────┬───────────┘  ┌─────────────────────────────────────┐  │
│           │               │   demo namespace                    │  │
│           │ KV-V2         │                                     │  │
│           │ secret/demo   │   SecretStore (vault)               │  │
│           │               │     └─ AppRole auth → vault:8200    │  │
│           │               │                                     │  │
│           └───────────────│── ExternalSecret (vault)            │  │
│                           │     └─ pulls secret/demo            │  │
│                           │                                     │  │
│                           │   Secret: demo ← synced by ESO     │  │
│                           │     Hello=World!, foo=bar,          │  │
│                           │     Red_Hat=Linux                   │  │
│                           │                                     │  │
│                           │   Secret: approle-vault             │  │
│                           │     (role-id, secret-id for ESO)    │  │
│                           └─────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

> **Note:** The diagram above reflects the **prod (HA)** topology with 3 Vault pods. In **dev** and **lab** modes, a single `vault-0` instance is deployed instead.

---

## Project Structure

```
.
├── Makefile                          # Main orchestrator (host ↔ container dispatch)
├── run.sh                           # Host entrypoint: OCP version detection, container launch
├── workflow.sh                      # In-container bootstrap: install tools, validate, run make
├── lib/                             # Shared shell libraries
│   └── logging.sh                  # Common log/debug/trace functions (sourced by scripts)
├── hashicorp-vault-helm/            # Vault Helm chart deployment
│   ├── Makefile                     # dev/lab/prod targets + init orchestration
│   ├── init-install-v2.sh           # Vault init, unseal, audit, KV engine, K8s auth setup
│   ├── values.dev.yaml              # Helm overrides for dev (standalone, dev server mode)
│   ├── values.lab.yaml              # Helm overrides for lab (standalone, PVC storage)
│   ├── values.prod.yaml             # Helm overrides for prod (HA Raft, 3 replicas)
│   ├── values.auto-unseal.yaml      # Helm overrides for auto-unseal sidecar
│   ├── vault-auto-unseal.sh         # Auto-unseal sidecar script (reference)
│   └── run-init-container.sh        # Run tooling inside an origin-cli container
├── external-secrets-helm/           # External Secrets Operator Helm chart deployment
│   ├── Makefile                     # install/clean targets
│   └── README.md
├── vault-external-secrets-lab/      # Demo data + verification
│   ├── Makefile                     # demo/clean/verify targets
│   ├── post-install-v3.sh           # Vault demo data + AppRole + ESO manifests
│   ├── verify-vault-openshift.sh    # End-to-end validation script
│   ├── README.md
│   └── manifests/                   # OpenShift templates
│       └── sandbox-vault-external-secrets-template.yaml
├── vault-odf/                       # ODF (OpenShift Data Foundation) Vault integration notes
│   ├── ODF-Vault.txt
│   ├── odf-vault-kube-auth
│   └── odf-vault-token-auth
├── images/                          # Screenshots and diagrams
├── _archived/                       # Legacy scripts (kept for reference)
├── .gitignore
├── LICENSE
└── README.md
```

---

## Uninstall

```bash
make clean
```

This removes, in order:
1. Demo namespace (SecretStore, ExternalSecret, Secrets)
2. External Secrets Operator (Helm release, namespace, webhooks)
3. HashiCorp Vault (Helm release, PVCs, RBAC, namespace)

---

## Configuration Reference

| Environment Variable | Default | Description |
|---------------------|---------|-------------|
| `USE_CONTAINER` | `true` | Handled automatically by the two-phase Makefile pattern; set to `false` to bypass `run.sh` and execute targets directly on the host (requires `make`, `helm`, and `jq` installed locally) |
| `OCP_MINOR_VERSION` | Auto-detected | Override OCP minor version (e.g. `4.18`) |
| `CONTAINER_ENGINE` | `podman` | Container runtime (`podman` or `docker`) |
| `OC_INSECURE_TLS` | `true` | Skip TLS verification for `oc login` |
| `VAULT_AUTO_UNSEAL` | `false` | Enable auto-unseal sidecar; when `true`, Vault pods automatically unseal on restart using keys from `vault-operator-init` secret |
| `OPENSHIFT_API_URL` | — | API URL when not using host kubeconfig |
| `CLUSTER_ADMIN_USERNAME` | — | Admin username for `oc login` |
| `CLUSTER_ADMIN_PASSWORD` | — | Admin password for `oc login` |

---

## License

This project is licensed under the **GNU General Public License v3.0** — see the [LICENSE](LICENSE) file for details.
