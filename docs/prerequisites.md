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

    If you do not have any resource groups yet, create one. You should also create a storage account. The name of your storage account must be unique across Azure. To ensure a unique name we will add a timestamp to the name in the example below.

    ```bash
    az group create --name "daos-rg" --location "westus3"

    az storage create --name "daos$(date "+%Y%m%d%H%M%S")" --location "westus3"
    ```

    Set the default resource group for the Azure CLI

    ```bash
    az config set defaults.location=westus3 defaults.group=daos-rg
    ```

    Disable warnings about experimental commands

    ```bash
    az config set core.only_show_errors=yes
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

## Next Steps

Before you can deploy DAOS you will need to build an image.

See [images/README.md](../images/README.md)
