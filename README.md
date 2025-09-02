# Sandbox Vault ExternalSecrets

[![RHEL 9+](https://img.shields.io/badge/RHEL-9+-ee0000?logo=redhat&logoColor=ee0000)](https://www.redhat.com/en/technologies/linux-platforms/enterprise-linux) <!-- https://www.redhat.com/en/about/brand/standards/color -->
[![Kubernetes](https://img.shields.io/badge/Kubernetes-v1.31+-326CE5?logo=kubernetes&logoColor=326CE5)](https://kubernetes.io/)
[![Openshift](https://img.shields.io/badge/Openshift-v4.16+-EE0000?logo=redhatopenshift&logoColor=EE0000)](https://www.redhat.com/en/technologies/linux-platforms/enterprise-linux) <!-- https://www.redhat.com/en/about/brand/standards/color -->
[![Helm](https://img.shields.io/badge/Helm-v3.12+-0F1689?logo=helm&logoColor=0F1689)](https://helm.sh/docs)
[![GNU GPL v3.0](https://img.shields.io/badge/GNU%20GPL-v3.0-A42E2B?logo=gnu&logoColor=A42E2B)](https://www.gnu.org/licenses)

---

Welcome to the **Sandbox Vault External Secrets** project! This project serves as a robust sandbox environment for an automated deployment and integration of [HashiCorp Vault](https://github.com/hashicorp/vault-helm) and [External Secrets Operator](https://github.com/external-secrets/external-secrets). Whether you're new to HashiCorp Vault or an experienced user, this project serves as a hands-on, experimental platform to explore and integrate secure secrets management with OpenShift.

---

## Table of Contents
- [Sandbox Vault ExternalSecrets](#sandbox-vault-externalsecrets)
  - [Table of Contents](#table-of-contents)
  - [Summary](#summary)
  - [Requirements](#requirements)
  - [Recently Tested](#recently-tested)
  - [Installation and Configuration](#installation-and-configuration)
    - [Prerequisites](#prerequisites)
    - [Clone the Repository](#clone-the-repository)
    - [Define the environment](#define-the-environment)
    - [Execute Makefile](#execute-makefile)
    - [Trust, but verify](#trust-but-verify)
    - [Verify HashiCorp Vault](#verify-hashicorp-vault)
    - [Verify External Secrets Operator](#verify-external-secrets-operator)
    - [Validate demo secret content in OpenShift](#validate-demo-secret-content-in-openshift)
  - [How It All Comes Together](#how-it-all-comes-together)
  - [Architecture Overview](#architecture-overview)
    - [**Vault Deployment**:](#vault-deployment)
    - [**Vault Unsealing**:](#vault-unsealing)
    - [**External Secrets Operator**:](#external-secrets-operator)
    - [**Demo secret Creation in Vault**:](#demo-secret-creation-in-vault)
    - [**Syncing Vault Secrets to OpenShift**:](#syncing-vault-secrets-to-openshift)
  - [Uninstall](#uninstall)
  - [License](#license)

---

## Summary

In modern DevOps practices, managing sensitive information such as API keys, passwords, and certificates securely is critical. This project provides a hands-on example of the deployment and configuration of HashiCorp Vault and External Secrets Operator (ESO) within an OpenShift cluster. By automating these processes, users can securely manage secrets and synchronize them seamlessly with OpenShift. Key features include:

- Deploying HashiCorp Vault via Helm.  
- Initializing and unsealing HashiCorp Vault automatically based on specific environments (`lab` or `prod`).  
- Installing External Secrets Operator to enable secret synchronization from HashiCorp Vault to OpenShift.  
- Demonstrating real-world scenarios with a pre-configured demo secret.

This setup is ideal for developers, DevOps engineers, and platform teams looking to implement secure and scalable secrets management in their infrastructure.

---

## Requirements

Before proceeding, ensure the following prerequisites are met:

- **OpenShift Cluster**: A functional OpenShift cluster.  
- **Helm**: Version 3.6 or later. [Install Helm](https://helm.sh/docs/intro/install/).  
- **OpenShift CLI (oc)**: Required for cluster interactions. [Install OpenShift CLI](https://docs.openshift.com/container-platform/latest/cli_reference/openshift_cli/getting-started-cli.html).  
- **Make**: Required to run `Makefile` tasks. [Install Make](https://www.gnu.org/software/make/).  
- **jq**: A command-line JSON processor. [Install jq](https://stedolan.github.io/jq/download/).  
- **Git**: Required for repository cloning. [Install Git](https://git-scm.com/book/en/v2/Getting-Started-Installing-Git).  
- **Access to Helm Repositories**: Ensure network access to [HashiCorp](https://helm.releases.hashicorp.com) and [External-Secrets](https://charts.external-secrets.io) repositories.  

---

## Recently Tested

Date: Saturday 2025-08-09 22:08:57

- Openshift: v4.18.21
- Kubernetes: v1.31.10
- Git: v2.50.1
- Helm: v3.18.4
- JQ: v1.7.1
- GNU Make: v4.4.1
- Vault App: v1.20.1
- Vault Helm: v0.30.1
- External Secrets: v0.19.1

---

## Installation and Configuration

For advanced configurations, refer to:  
- [HashiCorp Vault Documentation](https://developer.hashicorp.com/vault/docs)  
- [External Secrets Operator Documentation](https://external-secrets.io/) 

<br>

> [!IMPORTANT]
> Ensure elevated permissions in your OpenShift cluster **before** proceeding.

---

### Prerequisites

1. **Install Helm**

   ```bash
   mkdir $HOME/bin/
   curl -fqsLk https://get.helm.sh/helm-v3.17.0-linux-amd64.tar.gz | tar xvz -C $HOME/bin/
   mv $HOME/bin/linux-amd64/helm $HOME/bin/ && rm -r $HOME/bin/linux-amd64
   ```
<br>

> [!WARNING]
> This example uses ***Linux x86_64*** processor architecture.     
> Modify the architecture for your system as needed. [Find the appropriate version here](https://github.com/helm/helm/releases/latest).

<br>

2. **Install Required Packages**

   ```bash
   sudo dnf install -y make jq git
   ```
---

### Clone the Repository

   Clone the repository and navigate into the project directory.

   ```bash
   git clone https://github.com/jayissi/Sandbox-Vault-ExternalSecrets.git
   cd Sandbox-Vault-ExternalSecrets
   ```
---

### Define the environment

Set the `VAULT_ENV` variable based on your target environment:

| `VAULT_ENV` | Description |
|:-----------:|-------------|
|  `dev`  | Deploy a single Vault instance in "Dev" server mode. |
|  `lab`  | Deploy a single instance with auto initialization, unsealing, and auditing. |
|  `prod` | Deploy 3 High Availability (HA) instances with auto initialization, unsealing, and auditing. |

<br>
   Example:
   
   ```bash
   export VAULT_ENV=prod  # Options: 'dev', 'lab', or 'prod'
   ```
<br>

  > [!NOTE]
  > `dev` will configure HashiCorp Vault into ["Dev" server mode](https://developer.hashicorp.com/vault/docs/concepts/dev-server).     
  > Vault will be automatically initialized and unsealed.

---

### Execute Makefile

   Execute the `Makefile` to deploy the environment:
   
   ```bash
   make $VAULT_ENV
   ```

---

### Trust, but verify

Execute the `Makefile` verify scripts to validate the configuration is successful.

```bash
make verify
```

### Verify HashiCorp Vault

<br>

  1. Confirm vault pods are running

  ```bash
  oc get pods -n vault -l app.kubernetes.io/name=vault
  ```
<br>

<p align="center">
    <img src="images/vault/verify-vault-pods.png" align="center" alt="external-secrets">
</p>

<br>
<br>

  2. Verify vault status

  ```bash
  for pod in $(oc get pods -n vault -l app.kubernetes.io/name=vault -o jsonpath='{.items[*].metadata.name}')
  do
    echo "Status for $pod:"
    oc exec -n vault $pod -- vault status
    echo "---------------------------"
  done
  ```

<br>

<p align="center">
    <img src="images/vault/verify-vault-status.png" align="center" alt="external-secrets">
</p>

<br>
<br>

  3. List the raft peers in vault cluster

  ```bash
  oc exec -n vault vault-0 -- vault operator raft list-peers
  ```

<br>

<p align="center">
    <img src="images/vault/verify-vault-raft-peers.png" align="center" alt="external-secrets">
</p>

<br>

### Verify External Secrets Operator

<br>

  1. Confirm external-secrets pods are running

  ```bash
  oc get pods -n external-secrets
  ```
<br>

<p align="center">
    <img src="images/eso/verify-external-secrets-pods.png" align="center" alt="external-secrets">
</p>

<br>
<br>

  2. Validate secret store status is true

  ```bash
  oc get secretstores.external-secrets.io vault -n demo -o jsonpath='{.status.conditions}' | jq
  ```

<br>

<p align="center">
    <img src="images/eso/verify-secret-store-status.png" align="center" alt="external-secrets">
</p>

<br>
<br>

 3. Verify external secrets secret is synced 

  ```bash
  oc get externalsecrets.external-secrets.io vault -n demo -o json | jq '.status | {binding, conditions}'
  ```

<br>

<p align="center">
    <img src="images/eso/verify-external-secrets-sync.png" align="center" alt="external-secrets">
</p>

<br>

### Validate demo secret content in OpenShift

<br>

  1. Display the decoded contents of `secret/demo`

  ```bash 
  oc get secret demo -n demo -o jsonpath='{.data}' | jq -r 'to_entries[] | "\(.key): \(.value | @base64d)"'
  ```

<br>
<br>

<p align="center">
    <img src="images/secret-sync/verify-demo-secret-content.png" align="center" alt="deployment-success">
</p>

<br>

---

## How It All Comes Together

1. **Deploy Vault**: via Helm chart, HashiCorp Vault is deployed to your OpenShift cluster.
2. **Unseal Vault**: After deployment, HashiCorp Vault is unsealed automatically.
3. **Install External Secrets Operator**: External Secrets Operator is installed via Helm to manage the synchronization of secrets from HashiCorp Vault to OpenShift.
4. **Generate Vault demo secrets**: HashiCorp Vault is populated with demo secrets that represent real-world credentials and data.
5. **Secret synchronization to OpenShift**: External Secrets Operator automatically syncs HashiCorp Vault secrets as Kubernetes Secrets in OpenShift, making them available for use by OpenShift.

---

## Architecture Overview

This architecture provides a **secure, automated, and scalable solution** for managing sensitive data in OpenShift using HashiCorp Vault and the External Secrets Operator. By automating deployment, unsealing, and synchronization, the system reduces manual overhead, minimizes the risk of human error, and ensures that secrets are always up-to-date and securely accessible.

The following key tasks are performed:

<br>

### **Vault Deployment**:
- **What it is**: HashiCorp Vault is a robust **secrets management tool** designed to securely store, access, and manage sensitive data such as credentials, tokens, and configuration details.
- **How it works**: Vault is deployed on OpenShift using its **official Helm chart**, which simplifies the installation process. The deployment is configured to support multiple environments (e.g., development, staging, production), ensuring flexibility and scalability.
- **Why it’s needed**: Vault acts as a **centralized and secure repository** for managing secrets. By integrating with OpenShift, it provides a reliable mechanism for applications to securely access sensitive data without exposing it in plaintext.

<br>

### **Vault Unsealing**:
- **What it is**: Vault operates in a **sealed state** by default, meaning it cannot access its stored secrets until it is unsealed. Unsealing is the process of decrypting the storage backend and initializing Vault for operation.
- **How it works**: The unsealing process is automated using a **Makefile**, which handles the unsealing for both `lab` and `prod` environments. This automation ensures that Vault is operational and ready to serve secrets to external systems like ESO.
- **Why it’s needed**: Unsealing HashiCorp Vault is a critical step to allow applications to interact with it and retrieve stored secrets. This step ensures that the HashiCorp Vault instance is secure and operational.

<br>

### **External Secrets Operator**:
- **What it is**: The **External Secrets Operator (ESO)** is a OpenShift operator that synchronizes secrets from external secret management systems (like Vault) into OpenShift secrets.
- **How it works**: ESO continuously monitors Vault for changes to secrets. When a secret is updated in Vault, ESO automatically synchronizes it to the corresponding Kubernetes secret in OpenShift, ensuring consistency across platforms.
- **Why it’s needed**: ESO simplifies the integration of external secret stores, like HashiCorp Vault, to manage secrets in OpenShift. It abstracts the complexity of manually managing secrets and makes it easy to access and rotate secrets in a secure and automated way.

<br>

### **Demo secret Creation in Vault**:
- **What it is**: A **demo secret** is created in Vault to simulate real-world secret management scenarios. This serves as a practical example of how Vault handles sensitive data.
- **How it works**: After HashiCorp Vault is deployed and unsealed, the `Makefile` runs a process to inject demo secret (such as credentials, tokens, and configuration details) into HashiCorp Vault. These secrets are then used to simulate a real-world secret management scenario and validate the integration between Vault, ESO, and OpenShift.
- **Why it’s needed**: The demo secret provides a **simple test case** of how HashiCorp Vault can be used to manage and securely store application secrets. It ensures that secrets can be securely stored, retrieved, and synchronized across platforms.

<br>

### **Syncing Vault Secrets to OpenShift**:
- **What it is**: This process involves synchronizing secrets stored in Vault to OpenShift as Kubernetes secrets using ESO, making them accessible to applications.
- **How it works**: ESO actively watches for updates to secrets in Vault. When a change is detected, ESO ensures that the corresponding Kubernetes secret in OpenShift is updated in **real-time**, maintaining consistency between the two systems.
- **Why it’s needed**: This synchronization ensures that OpenShift applications can securely access secrets managed in Vault without requiring manual updates. It enhances security and operational efficiency by automating secret management.

---

## Uninstall

To clean up resources, run:
```bash
make clean
```

---

## License

This project is licensed under the **GNU General Public License v3.0** - see the [LICENSE](LICENSE) file for details.

The GNU General Public License v3.0 is a free, copyleft license for software and other kinds of works. It ensures that you have the freedom to share and change all versions of the program, making sure it remains free software for all its users. For more information, please refer to the [GNU General Public License v3.0](https://www.gnu.org/licenses/gpl-3.0.en.html).
