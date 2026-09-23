# External Secrets Operator (OLM-managed)

This directory installs the **External Secrets Operator for Red Hat OpenShift** via the Operator Lifecycle Manager (OLM), replacing the previous community Helm chart installation.

## What Gets Installed

| Component | Namespace | Description |
| --- | --- | --- |
| Operator (controller-manager) | `external-secrets-operator` | OLM-managed operator pod |
| Core controller | `external-secrets` | Reconciles ExternalSecret/SecretStore CRs |
| Webhook | `external-secrets` | Validates and converts CRs |
| Cert controller | `external-secrets` | Manages TLS certificates for the webhook |

## Manifests

| File | Resource | Purpose |
| --- | --- | --- |
| `manifests/namespace.yaml` | Namespace | Creates `external-secrets-operator` |
| `manifests/operatorgroup.yaml` | OperatorGroup | Scopes operator to all namespaces |
| `manifests/subscription.yaml` | Subscription | Subscribes to `stable-v1` channel from `redhat-operators` |
| `manifests/externalsecretsconfig.yaml` | ExternalSecretsConfig | Deploys operand pods with permissive egress NetworkPolicy |

## Reference Files (Not Automated)

| File | Purpose |
| --- | --- |
| `references/networkpolicy-egress-tightening.yaml` | Examples for restricting egress to specific services (Vault, AAP, ArgoCD, DNS) |
| `references/metrics-monitoring.yaml` | ServiceMonitor, PrometheusRule, and PromQL examples for monitoring ESO |

These files are provided for administrator review and future implementation. They are not wired into any make target.

## Usage

```bash
# Install via top-level Makefile (recommended)
make eso

# Check status
make eso-status

# Clean up
make clean-eso
```

## Targets

| Target | Description |
| --- | --- |
| `install` | Install ESO via OLM (namespace, OperatorGroup, Subscription, ExternalSecretsConfig) |
| `clean` | Remove all OLM resources, CRDs, webhooks, and namespaces |
| `status` | Show operator CSV, operand pods, and ExternalSecretsConfig conditions |
| `help` | Display help message |
