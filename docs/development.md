# DAOS Azure - Development

## Prerequisites

1. Install the Azure CLI

   https://learn.microsoft.com/en-us/cli/azure/install-azure-cli

2. Configure the Azure CLI

   Log in.

   ```bash
   az login
   ```

   View your list of subscriptions and set the default subscription.

   ```bash
   az account list
   az account set -s <subscription id>
   ```

   View list of locations and set the default location.

   ```bash
   az account list-locations
   az configure --defaults location=<location_name>
   ```

   Now that the defaults have been set, any CLI commands that require a subscription or location will use the defaults if those values are not passed as arguments.

3. Install Packer

4. Clone the repo

   ```bash
   git clone git@github.com:daos-stack/daos-azure.git
   ```

5. **Deploy infrastructure**

   ```bash
   export DAOS_AZ_LOCATION="<location>"
   bin/deploy_infra.sh
   ```
   **NOTE**
   If you do not set DAOS_AZ_LOCATION it will default to uswest3.

6. **Build images**

   ```bash
   cd images
   ./build.sh
   ```

## Deploy DAOS

1. **Deploy DAOS Admin and Servers**

2. **Deploy Clients**
