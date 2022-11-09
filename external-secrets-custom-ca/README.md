# External Secrets Operator with Custom CA

Use External Secrets Operator against a secret store using a TLS certificate
signed by a custom certificate authority (CA).

This method requires that the CA is trusted by OpenShift per the
[Custom PKI Docs]. If you the Vault server is signed by the OpenShift cluster
ingress operator (default certificate on a fresh installed cluster), you will
need to add the ingress-operator TLS certificate to your cluster trust bundle.

**NOTE:** If you do follow the [Custom PKI Docs] steps, you must wait until the
cluster operators reconcile before deploying External Secrets Operator. Watch
the cluster operators status with: `watch -d oc get co`

This was specifically tested with Vault but should work for any secret provider
signed by a custom CA that OpenShift is configured to trust.

## Installing (Manually)

1. Create the external-secrets project:
```bash
oc new-project external-secrets
```

2. Create the ca-bundle config map:
```bash
oc create -f - << EOF
kind: ConfigMap
apiVersion: v1
metadata:
  name: ca-bundle
  namespace: external-secrets
  labels:
    config.openshift.io/inject-trusted-cabundle: 'true'
EOF
```

3. Deploy External Secrets Operator from Helm
```bash
helm repo add external-secrets https://charts.external-secrets.io
helm install \
    external-secrets \
    external-secrets/external-secrets \
    -f values.yaml \
    -n external-secrets \
    --set installCRDs=true
```

[Custom PKI Docs]: https://docs.openshift.com/container-platform/latest/networking/configuring-a-custom-pki.html
