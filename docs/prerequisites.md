# DAOS on Azure - Prerequisites

Before you can deploy DAOS on Azure there are a few prerequisites.

## Subscription

See [How to: Sign Up for a Microsoft Azure Subscription](https://learn.microsoft.com/en-us/dynamics-nav/how-to--sign-up-for-a-microsoft-azure-subscription)

Most organizations have governance around cloud accounts for billing, security and reporting purposes. The process for creating a Subscription may be unique to your organization.

## Install Tools


### Azure CLI

#### Azure CLI Installation

Install the Azure CLI.

See the [Azure CLI instructions](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli) for your platform.

#### Azure CLI Authentication

After installing the CLI you will need to authenticate.

```bash
# Login and follow instructions
az login --scope https://vault.azure.net/.default
```

#### Azure CLI Configuration

Many of the scripts and commands shown in the documentation in this repo require
that you have set your default subscription.

```bash
# List your Subscriptions
az account list

# Set the default Subscription
az account set --subscription <subscription_name>
```

The CLI will warn you about commands that are considered to be experimental.

If you would like to disable these warnings run:

  ```bash
  az config set core.only_show_errors=yes
  ```

#### Azure CLI Extensions

Install Azure CLI Extensions

```bash
az extension add --name bastion
az extension add --name ssh
```

### jq and makeself

#### RedHat, CentOS Stream, Rocky Linux, Alma Linux, Fedora

```bash
sudo dnf install -y epel-release
sudo dnf install -y jq makeself
```

#### Debian, Ubuntu

```bash
sudo apt update
apt install -y jq makeself
```

#### MacOS with Homebrew

```bash
brew install jq makeself
```
