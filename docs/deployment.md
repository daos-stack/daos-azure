# DAOS on Azure - Deployment Guide

- [DAOS on Azure - Deployment Guide](#daos-on-azure---deployment-guide)
  - [Quickstart](#quickstart)
  - [Deleting Resources](#deleting-resources)


## Quickstart

The following instructions describe how to deploy a DAOS
cluster using pre-defined settings.

The cluster will consist of 3 DAOS server VMs and 3 DAOS client VMs. The
server and client VMs both use the [Standard_L8s_v3](https://learn.microsoft.com/en-us/azure/virtual-machines/lsv3-series) SKU.

In these instructions the `bin/infrastructure.sh` script will be used
to deploy all required *[Infrastructure](infrastructure.md)* resources
(VNet, Subnet, Network Security Group, etc.).

1. **Prerequisites**

   Follow the instructions in the [Prerequisites](prerequisites.md) document
   to ensure that the required software is installed on your system and
   that you have configured the Azure CLI.

2. **Clone the daos-azure repo**

   ```bash
   git clone https://github.com/daos-stack/daos-azure.git
   cd daos-azure
   export DAOS_AZ_REPO_HOME="$(pwd)"
   ```

3. **Create a `daos-azure.env` file**

   Make a copy of the `daos-azure.env.example` file.

   ```bash
   cp daos-azure.env.example daos-azure.env
   ```

   See a list of the variables that must be set

   ```bash
   grep -e '"<.*>"' daos-azure.env
   ```

   This will show the user specific environment variables in the `daos-azure.env`
   file that must be set prior to deployment.

   Edit the `daos-azure.env` file and set only those variables.

   For more information about the `daos-azure.env` file see [Environment Variables](env_vars.md).

4. **Deploy **infrastructure** resources (optional)**

   The term "infrastructure" is used to describe the resources that must exist prior to deploying DAOS servers and clients.

   Such resources include a resource group, virtual network, Azure bastion, Key Vault, etc.

   ```bash
   cd "${DAOS_AZ_REPO_HOME}/bin"
   ./infrastructure.sh --deploy
   ```

   It can take up to 20 minutes for the deployment to finish. The majority of
   the time is spent on setting up the Azure Bastion.

   Wait for the deployment to finish before going to the next step.

5. **Deploy DAOS servers**

   ```bash
   ./daos_servers.sh --deploy
   ```
   This will deploy a Virtual Machine Scale Set with 3 DAOS server VMs.

   The first time the script runs it prompts to accept the
   AlmaLinux License Agreement.  The DAOS server and client VMs
   use the free AlmaLinux 8 image.
   To use this image you must accept the license agreement.

   After the VMs start it will take about 6 minutes for the cloud-init script to
   run an Ansible playbook on the VMs.

   It's best to wait at least 5 minutes after the `daos_servers.sh` script
   has finished running before continuing to the next step.
   This will allow time for the servers to start.  If you deploy the
   clients before the servers are up, you may have to restart
   the `daos_agent` on the client VMs after they are deployed.

6. **Deploy DAOS clients**

   ```bash
   ./daos_clients.sh --deploy
   ```
   This will deploy a Virtual Machine Scale Set with 3 DAOS client VMs.

7. **Create an SSH tunnel**

   **NOTE:**

   The provided `bin/tunnel.sh` script in this step will modify your `~/.ssh/config` file!

   If you do not want the script to modify your `~/.ssh/config`, run the following command to only
   print an SSH configuration that you can then manually add to your `~/.ssh/config` file or use as
   reference for setting up connections in PuTTY or other SSH clients.

   ```bash
   bin/tunnel.sh --print
   ```



   To log into the VMs you need to set up an SSH tunnel to the first
   DAOS client VM or the first DAOS server VM if you have only deployed DAOS servers. .

   This will allow you to log into your VMs using SSH on your local system.

   ```
   [Your System] ---SSH---> [Azure Bastion] ---SSH---> [Azure VM]
         ||                        ||                       ||
   (localhost:2022)         (Bastion IP:22)         (VM Private IP:22)
   ```

   Run the following command to modify your `~/.ssh/config` file and create a tunnel.

   ```bash
   ./tunnel.sh --create --configure-ssh
   ```

   The `--configure-ssh` option only needs to be specified the
   first time the `tunnel.sh` script is run.

   The `--configure-ssh` option will:

     - Create an `~/.ssh` directory if it doesn't exist
     - Create an `~/.ssh/config.d` directory if it doesn't exist
     - Create an `~/.ssh/config` file if it doesn't exist
     - Ensure that `Include ~/.ssh/config.d/*` is present in the `~/.ssh/config` file
     - Create a `~/.ssh/config.d/azure-tunnel` SSH config file that
       configures the tunnel on your local system as a jump host for
       the DAOS VMs.

   The `tunnel.sh` script sets up the tunnel on `127.0.0.1:2022`.
   If you are using port `2022` on your system for something else, you
   will need to change the value of the `TUNNEL_LOCAL_PORT` variable in
   the `tunnel.sh` script.

8. **Log into the VM**

   The `tunnel.sh` script will print the name of the first client VM or first
   server VM (if you have only deployed DAOS servers) when you run
   `tunnel.sh --create`.

   The name of the VM displayed by the  `tunnel.sh` script is the VM that you
   can log into via the tunnel.

   For example

   ```bash
   ssh daos-client-000000
   ```

   This will log you in as the `daos_admin` user.

   The `daos_admin` user has sudo permission.

   The DAOS management utility `dmg` must always be run with sudo.

   NOTE: If the variables in the `daos-azure.env` have been changed from
   their default values, the name of the client or server VM that you will
   log into may be different that what is shown above.



9.  **Check the DAOS storage system**

   ```bash
   # Show the status of the servers
   sudo dmg system query -v

   # Show pool information
   sudo dmg pool list
   sudo dmg storage query usage
   ```

   If the `dmg` command is not available or you are seeing errors
   related to certificates, it may be that the Ansible playbook has not
   finished configuring the system yet.  Wait a few minutes and try again.
   If you still encounter issues, refer to the
   [Troubleshooting Guide](troubleshooting.md).

10. **Create and mount a [DAOS container](https://docs.daos.io/v2.4/user/container/)**

    ```
    DAOS_POOL_NAME=$(sudo dmg pool list -j | jq -r '.response.pools[0].label')
    DAOS_CONT_NAME=cont1
    DAOS_CONT_MOUNT_DIR=~/daos/$DAOS_CONT_NAME

    # Create DAOS container
    daos container create --type=POSIX $DAOS_POOL_NAME $DAOS_CONT_NAME

    # Create mount point
    mkdir -p $DAOS_CONT_MOUNT_DIR

    # Mount
    dfuse --singlethread \
    --pool=$DAOS_POOL_NAME \
    --container=$DAOS_CONT_NAME \
    --mountpoint=$DAOS_CONT_MOUNT_DIR

    # View mount
    df -h -t fuse.daos
    ```

11. **Use the storage**

    Create a 20GiB file which will be stored in the DAOS filesystem.

    ```bash
    dd if=/dev/zero of="${DAOS_CONT_MOUNT_DIR}/${HOSTNAME}_test20G.img" bs=1G count=20
    ```

12. **Unmount the DAOS container**

    ```bash
    fusermount -u $DAOS_CONT_MOUNT_DIR
    ```

## Deleting Resources

Delete the DAOS server and client VMs but leave the infrastructure resources.

```bash
cd "${DAOS_AZ_REPO_HOME}/bin"

# Undeploy DAOS Clients
./daos_client.sh --undeploy

# Undeploy DAOS Servers
./daos_server.sh --undeploy

```

Delete the infrastructure resources and all VMs.

```bash
cd "${DAOS_AZ_REPO_HOME}/bin"

# Delete ALL resources!
./infrastructure.sh --undeploy
```
