# External Secrets Operator with OpenShift Example

This repo contains example code that integrates [Hashicorp Vault] and
[OpenShift Container Platform] to deploy secrets from Vault using
[External Secrets Operator].

This is meant for demoing and lab use. It requires an OpenShift cluster with
persistent storage (for Vault).

## Step 1: Install Vault

Use [vault-init] to install a pre-configured Vault server.

**NOTE:** If you install Vault through different process you will probably need
to make modifications to the deploy script.

## Step 2: Install External Secrets Operator

**IMPORTANT: I could only get External Secrets Operator working using the
Helm chart installation method.** I tried to install the operator directly from
OperatorHub but the operator would not respond to CR creation (e.g. SecretStore
would create but the status would never populate).

To install the Operator with with Helm:

```
helm repo add external-secrets https://charts.external-secrets.io
helm install \
    external-secrets \
    external-secrets/external-secrets \
    -n external-secrets \
    --create-namespace \
    --set installCRDs=true
```

**NOTE:** If the Vault TLS certificate is not signed by a public CA (e.g.
signed by a third party CA **OR signed by the OpenShift Ingress Operator**) you
will need to customize the external-secrets installation. See
[external-secrets-custom-ca].

## Step 3: Deploy Example Resources

Before deploying, make sure that all pods in the `external-secrets` and
`vault-server` namespaces are "Ready".

```bash
oc get pods -n external-secrets && oc get pods -n vault-server
```

Once all command above shows all pods are "Ready", run this script to deploy
example resources:

```bash
./deploy.sh
```

## Validate Synced Secret

If everything was successful, External Secrets should have created an OpenShift
Secret named *message* in the *my-app* namespace. Validate the secret exists
with:

```bash
oc get secrets -n my-app message
```

Print the contents of the secret with:

```bash
oc get secrets -n my-app message -o jsonpath="{.data.message}" | base64 -d
```

[Argo CD]: https://github.com/argoproj/argo-cd
[External Secrets Operator]: https://github.com/external-secrets/external-secrets
[Hashicorp Vault]: https://github.com/hashicorp/vault
[OpenShift Container Platform]: https://docs.openshift.com/container-platform/latest
[OpenShift GitOps]: https://docs.openshift.com/container-platform/4.10/cicd/gitops/understanding-openshift-gitops.html
[Vault Config Operator]: https://github.com/redhat-cop/vault-config-operator
[external-secrets-custom-ca]: https://github.com/hello-openshift-vault/external-secrets-custom-ca
[vault-init]: https://github.com/hello-openshift-vault/vault-init
