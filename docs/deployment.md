# DAOS on Azure - Deployment Guide

- [DAOS on Azure - Deployment Guide](#daos-on-azure---deployment-guide)
  - [Quickstart](#quickstart)
  - [Deleting Resources](#deleting-resources)


## Quickstart

These quickstart steps assume you will use the `bin/infrastructure.sh` script
to deploy the required *[Infrastructure](infrastructure.md)* resources (VNet, Subnet, Network
Security Group, etc.).

It is also assumed that you will use all default settings.

1. **Clone the repo**

   ```bash
   git clone https://github.com/daos-stack/daos-azure.git
   cd daos-azure
   export DAOS_AZ_REPO_HOME="$(pwd)"
   ```

2. **Create a `daos-azure.env` file**

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

   See [Environment Variables](env_vars.md) for more information about the `daos-azure.env` file.

3. **Deploy **infrastructure** resources**

   ```bash
   cd "${DAOS_AZ_REPO_HOME}/bin"
   ./infrastructure.sh --deploy
   ```

   The first time you run the script you will be prompted to accept the
   AlmaLinux License Agreement.  The DAOS server and client VMs
   use the free AlmaLinux 8 image. To use this image you must accept
   the license agreement.

   It can take up to 20 minutes for the deployment to finish.

   Wait for the deployment to finish before going to the next step.

4. **Deploy DAOS servers**

   ```bash
   ./daos_servers.sh --deploy
   ```

   This will deploy a Virtual Machine Scale Set with 3 DAOS server VMs.

   After the VMs start it will take about 6 minutes for the cloud-init script to
   run an Ansible playbook on the VMs.

   It's best to wait at least 5 minutes after the `daos_servers.sh` script
   has finished running before continuing to the next step.
   This will allow time for the servers to start.  If you deploy the
   clients before the servers are up, you may have to restart
   the `daos_agent` on the client VMs after they are deployed.

5. **Deploy DAOS clients**

   ```bash
   ./daos_clients.sh --deploy
   ```
   This will deploy a Virtual Machine Scale Set with 3 DAOS client VMs.

6. **Create an SSH tunnel**

   To log into the VMs you need to set up an SSH tunnel to the first
   client VM.

   This will allow you to use `ssh` in a terminal to log into the VMs.

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

   NOTE: The `tunnel.sh` script sets up the tunnel on `127.0.0.1:2022`.
   If you are using port `2022` on your system for something else, you
   will need to change the value of the `TUNNEL_LOCAL_PORT` variable in
   the `tunnel.sh` script.

7. Log into the first client VM

   ```bash
   ssh daos-client-000000
   ```

   This will log you in as the `daos_admin` user which has sudo permission.

   NOTE: If the variables in the `daos-azure.env` have been changed from
   their default values, the name of the client VMs may be different.
   The `tunnel.sh` script will print the name of the first client VM.

8. Check the status of the DAOS storage system

   ```bash
   # Show the status of the servers
   sudo dmg system query -v

   # Show the status of the pool named 'pool1'
   sudo dmg pool list
   sudo dmg storage query usage
   ```

   If the `dmg` command is not available yet or you are seeing errors
   related to certificates, it may be that the Ansible playbook has not
   finished configuring the system yet.  Wait a few minutes and try again.
   If you still encounter issues, refer to the
   [Troubleshooting Guide](troubleshooting.md) for tips.

9. Create a [DAOS container](https://docs.daos.io/v2.4/user/container/) and mount it

   ```
   DAOS_POOL_NAME=pool1
   DAOS_CONTAINER_NAME=cont1
   DAOS_CONTAINER_MOUNT_DIR=~/daos/$DAOS_CONTAINER_NAME

   # Create DAOS container
   daos container create --type=POSIX --properties rd_fac:1 $DAOS_POOL_NAME $DAOS_CONTAINER_NAME

   # Create mount point
   mkdir -p $DAOS_CONTAINER_MOUNT_DIR

   # Mount
   dfuse --singlethread \
   --pool=$DAOS_POOL_NAME \
   --container=$DAOS_CONTAINER_NAME \
   --mountpoint=$DAOS_CONTAINER_MOUNT_DIR

   # View mount
   df -h -t fuse.daos
   ```

10. Use the storage

    Create a 20GiB file which will be stored in the DAOS filesystem.

    ```bash
    cd ~/daos/cont1
    time LD_PRELOAD=/usr/lib64/libioil.so dd if=/dev/zero of=./${HOSTNAME}_test21G.img bs=1G count=20
    ```

10. Unmount the DAOS container

    ```bash
    cd ~/
    fusermount -u $DAOS_CONTAINER_MOUNT_DIR
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
