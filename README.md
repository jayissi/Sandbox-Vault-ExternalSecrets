# Sandbox Vault ExternalSecrets

![License: GNU GPL v3.0](https://img.shields.io/badge/License-GNU%20General%20Public%20License%20v3.0-blue)
![Supported Platforms: RHEL | Linux](https://img.shields.io/badge/Supported%20Platforms-RHEL%20%7C%20Linux-EE0000)
![Helm](https://img.shields.io/badge/Helm-v3.12%2B-blue.svg)

## Table of Contents
1. [Introduction](#introduction)
2. [Summary](#summary)
3. [Requirements](#requirements)
4. [Installation and Setup](#installation-and-setup)
   - [Prerequisites](#prerequisites)
   - [Clone the Repository](#clone-the-repository)
   - [Define the environment](#define-the-environment)
   - [Execute Makefile](#execute-makefile)
   - [Trust But Verify](#trust-but-verify)
6. [Under The Hood](#under-the-hood)
   - [Vault Deployment](#vault-deployment)
   - [Vault Unsealing](#vault-unsealing)
   - [External Secrets Operator](#external-secrets-operator)
   - [Demo secret Creation in Vault](#demo-secret-creation-in-vault)
   - [Syncing Vault Secrets to OpenShift](#syncing-vault-secrets-to-openshift)
7. [How It All Comes Together](#how-it-all-comes-together)
8. [Uninstall](#uninstall)
9. [License](#license)


## Introduction

This repository automates the deployment and configuration of HashiCorp Vault and External Secrets Operator (ESO) on OpenShift. 
It provides a streamlined process to set up Vault using Helm, unsealing it based on the environment (`lab` or `prod`), install External Secrets Operator via Helm, and finally creates a demo secret within Vault to be accessed in OpenShift.


## Summary

The project offers an automated approach to:

- Deploy HashiCorp Vault on OpenShift via Helm.
- Unseal Vault based on the specified environment.
- Install External Secrets Operator to synchronize secrets from Vault to OpenShift.
- Populate Vault with demo secret.
- Configure External Secrets Operator to introduce Vault demo secret into OpenShift.

## Requirements

Before executing the provided `Makefile`, ensure the following prerequisites are met:

- **OpenShift Cluster**: A running OpenShift cluster where the components will be deployed.
- **Helm**: Helm command version 3.6 or later installed and configured. [Helm Installation Guide](https://helm.sh/docs/intro/install/)
- **openshift-client**: The `oc` command (OpenShift CLI) is required for interacting with OpenShift clusters. [OpenShift Client Installation Guide](https://docs.openshift.com/container-platform/latest/cli_reference/openshift_cli/getting-started-cli.html)
- **make**: The `make` command is required to execute the `Makefile` tasks. [Make Installation Guide](https://www.gnu.org/software/make/)
- **jq**: A command-line tool for processing JSON. It’s used to parse and manipulate JSON data in scripts. [jq Installation Guide](https://stedolan.github.io/jq/download/)
- **git**: Git is required to clone the repository. [Git Installation Guide](https://git-scm.com/book/en/v2/Getting-Started-Installing-Git)
- **Access to Helm Repositories**: Ensure your server can reach [HashiCorp](https://helm.releases.hashicorp.com) and [External-Secrets](https://charts.external-secrets.io) Helm repository.

## Installation and Setup

> [!IMPORTANT]
> This project *presumes* the availability of a **fully functional and operational OpenShift cluster**.     
> Furthermore, you **will need elevated permissions** in the cluster to perform these actions.

### Prerequisites

1. **Install Helm**
   ```bash
   mkdir $HOME/bin/
   curl -fqsLk https://get.helm.sh/helm-v3.17.0-linux-amd64.tar.gz | tar xvz -C $HOME/bin/
   mv $HOME/bin/linux-amd64/helm $HOME/bin/ && rm -r $HOME/bin/linux-amd64
   ```

> [!WARNING]
> This example uses ***Linux x86_64*** processor architecture.     
> Please find the appropriate architecture for your [Helm command](https://github.com/helm/helm/releases/latest).

2. **Install RPMs**
   ```bash
   sudo dnf install -y make jq git
   ```


### **Clone the Repository**

   Clone the repository and navigate into the project directory.
   ```bash
   git clone https://github.com/jayissi/Sandbox-Vault-ExternalSecrets.git
   cd Sandbox-Vault-ExternalSecrets
   ```

### **Define the environment**

|  VAULT_ENV  | Description |
|-------------|-------------|
|  dev  | Deploy 1 Vault instance into "Dev" server mode. |
|  lab  | Deploy 1 Vault instance that auto initialize and unseal with auiting. |
|  prod | Deploy 3 HA Vault instances that auto initialize and unseal with auiting. |

   Set the local variable **VAULT_ENV** to either `dev`, `lab`, or `prod`.     
   This determines if Vault will be initialized and unsealed during the deployment.
   ```bash
   VAULT_ENV=dev  # or VAULT_ENV=lab or VAULT_ENV=prod
   ```
  > [!NOTE]
  > This will configure Hashicorp Vault into ["Dev" server mode](https://developer.hashicorp.com/vault/docs/concepts/dev-server).     
  > Vault will be automatically initialized and unsealed.

### **Execute Makefile**

   Execute the `Makefile` program to initiate the deployment process.
   ```bash
   make $VAULT_ENV
   ```

### **Trust But Verify**

   - Ensure that the Vault pods are running and unsealed, if needed.
   - Check that External Secrets Operator pods are active.
   - Confirm that the demo secret is accessible in OpenShift.


## Under The Hood

This repository automates the deployment and configuration of **HashiCorp Vault** and **External Secrets Operator** on OpenShift. It includes a `Makefile` that orchestrates the entire process from deploying Vault to introducing secrets to OpenShift. The following key tasks are performed:

### **Vault Deployment**:
- **What it is**: HashiCorp Vault is a tool for managing secrets, sensitive data, and encryption. In this project, Vault is deployed using its official Helm chart.
- **How it works**: The `Makefile` automates the deployment of Vault using Helm. Vault is deployed into the OpenShift cluster, and the necessary configurations are applied for both the lab and production environments.
- **Why it’s needed**: Vault will securely store secrets that are later accessed by OpenShift through External Secrets Operator. It provides a central repository for managing secrets and sensitive configurations.

### **Vault Unsealing**:
- **What it is**: Vault requires a process known as "unsealing" to decrypt and initialize the Vault storage after deployment.
- **How it works**: The `Makefile` supports unsealing Vault for both `lab` and `prod` environments. Depending on the specified environment, Vault will be unsealed automatically after deployment. This process is automated to ensure that secrets are available for use by External Secrets Operator.
- **Why it’s needed**: Vault must be unsealed to allow applications to interact with it and retrieve stored secrets. This step ensures that the Vault instance is secure and operational.

### **External Secrets Operator**:
- **What it is**: External Secrets Operator is a tool that synchronizes secrets between external secret stores (like Vault) and Kubernetes/Openshift.
- **How it works**: The `Makefile` installs External Secrets Operator via its Helm chart. Once deployed, this operator ensures that secrets from Vault are automatically created as Kubernetes Secrets in OpenShift. It monitors Vault for changes and ensures that secrets are kept up to date in the OpenShift cluster.
- **Why it’s needed**: This operator makes it easy to use Vault-managed secrets in OpenShift. It abstracts the complexity of manually managing secrets and makes it easy to access and rotate secrets in a secure and automated way.

### **Demo secret Creation in Vault**:
- **What it is**: The repository contains a script to populate Vault with demo secrets for testing purposes.
- **How it works**: After Vault is deployed and unsealed, the `Makefile` runs a process to inject demo secret (such as credentials, tokens, and configuration details) into Vault. These secrets are then used to simulate a real-world secret management scenario.
- **Why it’s needed**: The demo secret provides a simple example of how Vault can be used to manage and securely store application secrets. This makes it easier to test the entire flow from Vault to OpenShift using External Secrets Operator.

### **Syncing Vault Secrets to OpenShift**:
- **What it is**: External Secrets Operator synchronizes the secrets stored in Vault to OpenShift as Kubernetes Secrets, making them accessible to applications.
- **How it works**: Once the demo secret is created in Vault, External Secrets Operator listens for changes to Vault secrets and ensures they are mirrored in OpenShift. The operator ensures that any updates to the Vault secrets are automatically reflected in the OpenShift environment.
- **Why it’s needed**: This step ensures that OpenShift can securely and seamlessly access Vault-managed secrets. By automating this process, developers can focus on building applications without worrying about managing secrets.


## **How It All Comes Together**
1. **Vault is deployed**: Using the Helm chart, Vault is deployed to your OpenShift cluster.
2. **Vault is unsealed**: After deployment, Vault is unsealed automatically based on the environment (`lab` or `prod`).
3. **External Secrets Operator is installed**: External Secrets Operator is installed via Helm to manage the synchronization of secrets from Vault to OpenShift.
4. **Demo secrets are created in Vault**: Vault is populated with demo secrets that represent real-world credentials and data.
5. **Secrets are synchronized to OpenShift**: External Secrets Operator automatically syncs Vault secrets as Kubernetes Secrets in OpenShift, making them available for use by OpenShift.


## Uninstall

To uninstall the project, run the following command:
```bash
make clean
```


## License

This project is licensed under the GNU General Public License v3.0 - see the [LICENSE](https://www.gnu.org/licenses/gpl-3.0.txt) file for details.

The GNU General Public License v3.0 is a free, copyleft license for software and other kinds of works. It ensures that you have the freedom to share and change all versions of the program, making sure it remains free software for all its users. For more information, please refer to the [GNU General Public License v3.0](https://www.gnu.org/licenses/gpl-3.0.en.html).


Refer to the official documentation for further details or advanced configurations:

- [HashiCorp Vault Documentation](https://developer.hashicorp.com/vault/docs)
- [External Secrets Operator Documentation](https://external-secrets.io/)
