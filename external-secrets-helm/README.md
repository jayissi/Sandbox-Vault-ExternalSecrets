# External Secrets Operator Helm Deployment

This directory manages the [External Secrets Operator (ESO)](https://external-secrets.io/) deployment on OpenShift via Helm.

## Targets

```bash
make help
```

| Target | Description |
|--------|-------------|
| `install` | Install ESO via Helm into the `external-secrets` namespace |
| `clean` | Uninstall ESO Helm release, remove webhooks and namespace |

## How It Works

```bash
make install
```

1. Adds the `external-secrets` Helm repository
2. Updates the repo index
3. Installs (or upgrades) the `external-secrets/external-secrets` chart
4. Waits for all pods and jobs to be ready (timeout: 15 minutes)

The 15-minute timeout accounts for shared OpenShift sandbox clusters where webhook certificate generation and CRD registration can be slow.

## Cleanup

```bash
make clean
```

1. Uninstalls the Helm release
2. Removes leftover validating webhooks (`externalsecret-validate`, `secretstore-validate`)
3. Deletes the `external-secrets` namespace

The webhook cleanup step prevents stuck `Terminating` namespaces when the operator is removed before its CRs.
