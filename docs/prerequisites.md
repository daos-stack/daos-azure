# DAOS Deployment on Azure - Prerequisites

## Sign up for a Subscription

See [How to: Sign Up for a Microsoft Azure Subscription](https://learn.microsoft.com/en-us/dynamics-nav/how-to--sign-up-for-a-microsoft-azure-subscription)

Most organizations have governance around cloud accounts for billing, security and reporting purposes. The process for creating a Subscription may be unique to your organization.

## Install Tools

### Packer

See the [Packer Installation instructions](https://developer.hashicorp.com/packer/tutorials/docker-get-started/get-started-install-cli) for your OS.

### Azure CLI

#### Azure CLI Installation

See the [Azure CLI instructions](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli) for your OS.

#### Azure CLI Authentication

```bash
# Login and follow instructions to authenticate
az login --scope https://vault.azure.net/.default
```

#### Azure CLI Configuration

  - Set your default subscription

    ```bash
    # List subscriptions
    az account list

    # Set default Subscription
    az account set --subscription <subscription_name>
    ```

  - Set default Resource Group

    To see a list of Resource Groups run

    ```bash
    az group list
    ```

    If you do not have any resource groups yet, you will need to [create one](https://learn.microsoft.com/en-us/cli/azure/group?view=azure-cli-latest#az-group-create).

    ```bash
    az group create --name "daos-rg" --location "westus3"
    ```

    Disable warnings about experimental commands

    ```bash
    az config set core.only_show_errors=yes
    ```

    Set the default resource group for the Azure CLI

    ```bash
    az config set defaults.location=westus3 defaults.group=daos-rg
    ```

### jq and makeself

RedHat, CentOS Stream, Rocky Linux, Alma Linux, Fedora

```bash
sudo dnf install -y epel-release
sudo dnf install -y jq makeself
```

Debian, Ubuntu

```bash
sudo apt update
apt install -y jq makeself
```

MacOS with Homebrew

```bash
brew install jq makeself
```

## Create Required Resources

### Storage Account

A [Storage Account](https://learn.microsoft.com/en-us/azure/storage/common/storage-account-overview) is required for a DAOS deployment.

View your storage accounts

```bash
az storage account list
```

If you do not have a storage account, you will need to [create one](https://learn.microsoft.com/en-us/cli/azure/group?view=azure-cli-latest#az-group-create).

```bash
az storage create --name "daos$(date "+%Y%m%d%H%M%S")" --location "westus3"
```

### Application Registration and Service Principal

Packer authenticates with Azure using a service principal. An Azure service principal is a security identity that you can use with apps, services, and automation tools like Packer. You control and define the permissions as to what operations the service principal can perform in Azure.

See [Application and service principal objects in Azure Active Directory](https://learn.microsoft.com/en-us/azure/active-directory/develop/app-objects-and-service-principals?tabs=browser) for more information.

List your Application Registrations

```bash
az ad app list --show-mine
```

If there are none, you will need to create one.

```bash
AZ_SUBSCRIPTION_NAME="<your subscription name>"
AZ_SUBSCRIPTION_ID=$(az account list --query "[?name=='${AZ_SUBSCRIPTION_NAME}'].id" -o tsv)

az ad sp create-for-rbac \
  --display-name "daos-packer" \
  --role Contributor \
  --scopes "/subscriptions/${AZ_SUBSCRIPTION_ID}" \
  --query "{ client_id: appId, client_secret: password, tenant_id: tenant }"
```

Save the Client_id, Client_secret and Tenant_id values as you will need to set environment variables with these values before running `packer`.


## Next Steps

Before you can deploy DAOS you will need to build a VM image that has DAOS pre-installed.

For instructions see [images/README.md](../images/README.md)
