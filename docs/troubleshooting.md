# Troubleshooting

- [Troubleshooting](#troubleshooting)
  - [Enable debug logging](#enable-debug-logging)
  - [Checking the provisioning status of Virtual Machine Scale Sets](#checking-the-provisioning-status-of-virtual-machine-scale-sets)
  - [Checking the status of VMs](#checking-the-status-of-vms)
  - [Logging into VMs via SSH](#logging-into-vms-via-ssh)
    - [Check SSH Keys](#check-ssh-keys)
      - [Does your ~/.ssh directory have the proper permissions?](#does-your-ssh-directory-have-the-proper-permissions)
      - [Do the keys exist and have the correct permissions?](#do-the-keys-exist-and-have-the-correct-permissions)
      - [Have you added your private key to the SSH Agent?](#have-you-added-your-private-key-to-the-ssh-agent)
      - [Do you have a tunnel open?](#do-you-have-a-tunnel-open)
      - [Is the SSH config correct?](#is-the-ssh-config-correct)
  - [cloud-init](#cloud-init)
    - [cloud-init flow](#cloud-init-flow)
    - [Viewing cloud-init files before deployment](#viewing-cloud-init-files-before-deployment)
    - [Viewing cloud-init files after deployment](#viewing-cloud-init-files-after-deployment)
    - [Troubleshooting cloud-init files on VMs](#troubleshooting-cloud-init-files-on-vms)
    - [Viewing cloud-init log output](#viewing-cloud-init-log-output)
  - [Order of deployment](#order-of-deployment)
  - [Deleting resources](#deleting-resources)

This document contains information that may be helpful for troubleshooting
deployment issues.

Throughout the document `DAOS_AZ_REPO_HOME` will be used to refer to the path
of the local clone of the [daos-stack/daos-azure](https://github.com/daos-stack/daos-azure) repo on your system.

If you set `DAOS_AZ_REPO_HOME`, you will be able to copy and run the
example commands in this document.

## Enable debug logging

Before running `bin/*.sh` scripts you can set an environment variable
that will turn on debug logging in the scripts.

```bash
export DAOS_AZ_LOG_LEVEL=DEBUG
```

When `DAOS_AZ_LOG_LEVEL=DEBUG` the scripts will print more verbose output.

Remember to export the `DAOS_AZ_LOG_LEVEL` variable!

## Checking the provisioning status of Virtual Machine Scale Sets

After running `bin/daos_servers.sh --deploy` or `bin/daos_clients.sh --deploy`
you can check the status of the vmss via the Azure portal or the CLI.

To check the status of the VMSS with the CLI open a new terminal and run

```bash
cd "${DAOS_AZ_REPO_HOME}"
source daos-azure.env

# Server VMSS provisioning state
az vmss show \
  --subscription "${DAOS_AZ_CORE_ACCT_NAME}" \
  --resource-group "${DAOS_AZ_CORE_RG_NAME}" \
  --name "${DAOS_AZ_ARM_SERVER_VMSS_NAME}" \
  --query "provisioningState" \
  --output tsv

# Client VMSS provisioning state
az vmss show \
  --subscription "${DAOS_AZ_CORE_ACCT_NAME}" \
  --resource-group "${DAOS_AZ_CORE_RG_NAME}" \
  --name "${DAOS_AZ_ARM_CLIENT_VMSS_NAME}" \
  --query "provisioningState" \
  --output tsv
```

## Checking the status of VMs

To check the status of VMs with the CLI open a new terminal and run

```bash
cd "${DAOS_AZ_REPO_HOME}"
source daos-azure.env

# DAOS Server VMs
serverInstanceIds=$(az vmss list-instances \
  --subscription "${DAOS_AZ_CORE_ACCT_NAME}" \
  --resource-group "${DAOS_AZ_CORE_RG_NAME}" \
  --name "${DAOS_AZ_ARM_SERVER_VMSS_NAME}" \
  --query "[].instanceId" \
  --output tsv)

for serverId in $serverInstanceIds; do
  az vmss get-instance-view \
    --instance-id $serverId \
    --name "${DAOS_AZ_ARM_SERVER_VMSS_NAME}" \
    --resource-group "${DAOS_AZ_CORE_RG_NAME}" \
    --query "{ComputerName:computerName,Status:statuses[].displayStatus}" \
    --output json
done

# DAOS Client VMs
clientInstanceIds=$(az vmss list-instances \
  --subscription "${DAOS_AZ_CORE_ACCT_NAME}" \
  --resource-group "${DAOS_AZ_CORE_RG_NAME}" \
  --name "${DAOS_AZ_ARM_CLIENT_VMSS_NAME}" \
  --query "[].instanceId" \
  --output tsv)

for clientId in $clientInstanceIds; do
  az vmss get-instance-view \
    --instance-id $clientId \
    --name "${DAOS_AZ_ARM_CLIENT_VMSS_NAME}" \
    --resource-group "${DAOS_AZ_CORE_RG_NAME}" \
    --query "{ComputerName:computerName,Status:statuses[].displayStatus}" \
    --output json
done
```

## Logging into VMs via SSH

Having trouble logging into VMs via SSH?

### Does your ~/.ssh directory have the proper permissions?

The ~/.ssh/ directory itself should also have restricted permissions to
ensure that others cannot view or modify its contents.

A common and recommended permission setting for the directory is 700
(read, write, and execute permissions for the owner, and no permissions
for others):

```bash
chmod 700 ~/.ssh
```

### Do the SSH keys exist and have the correct permissions?

Make sure that the SSH key specified in the daos-azure.env

```bash
cd "${DAOS_AZ_REPO_HOME}"
source daos-azure.env
echo
echo "Private Key"
ls -l "${DAOS_AZ_SSH_ADMIN_KEY}"
echo
echo "Public Key"
ls -l "${DAOS_AZ_SSH_ADMIN_KEY_PUB}"
echo
```
Owner of the files should be your account.

Permissions on the private key should be 600 or 400

Permissions on the public key should be 644 or 444

#### Have you added your private key to the SSH Agent?

To be able to forward your key through the SSH tunnel, your private
key needs to be added to the ssh agent.

Check it

```bash
ssh-add -l
```

If you don't see your key listed, add it.

```bash
cd "${DAOS_AZ_REPO_HOME}"
source daos-azure.env
ssh-add "${DAOS_AZ_SSH_ADMIN_KEY}"
```

#### Do you have a tunnel open?

Let's assume you have [checked the status of your VMs](troubleshooting.md#checking-the-status-of-vms).

You are trying to log in with

```
ssh <computer_name>
```

but it's not working.

Have you established a tunnel through the Azure Bastion?

Check to see if there is a tunnel running.

```bash
cd "${DAOS_AZ_REPO_HOME}/bin"
./tunnel.sh -l
```

You should see something like `TCP localhost:down (LISTEN)` in the output.
Don't worry that is shows the word "down".  If you see this text, generally
that means you have created a tunnel.

You can always try to recreate the tunnel.

```bash
cd "${DAOS_AZ_REPO_HOME}/bin"
./tunnel.sh -d
./tunnel.sh -c
```

#### Is the SSH config correct?

Check your `~/.ssh/config` file.

Is the file owned by your account?

Are the permissions correct on the file? They should be 600.

Is the line `Include ~/.ssh/config.d/*` present in the file?

If not then it should be added.

When the `bin/tunnel.sh` script runs it creates a
`~/.ssh/config.d/azure-tunnel` file which contains the configuration
that allows you to log into your VMs with just `ssh <computer_name>`.

You can run `bin/tunnel.sh --create --configure-ssh` to attempt to
fix issues with

## cloud-init

When VMs start they run a cloud-init script.

The cloud-init script is a self-extracting archive that extracts all necessary
files for installing and configuring DAOS. After extracting the files the
cloud-init script runs a setup script which was extracted from the archive.

### cloud-init flow

When running `bin/daos_servers.sh --deploy` :

1. `bin/daos_servers.sh` calls `bin/gen_cloudinit.sh` to create a cloud-init script.
2. `bin/gen_cloudinit.sh` will create a `vm_files/daos_server/daos_server_setup.env`
   file.
3. `bin/gen_cloudinit.sh` runs the `makeself` utility to create a self-extracting
   executable file (`bin/cloudinit_server.sh`) that includes an archive of the `vm_files/daos_server` directory.
4. The `arm/daos/azuredeploy_server.json` ARM template will be generated and the
   contents of the `bin/cloudinit_server.sh` file will be added to the
   `customData` property of the VM profile.
5. A deployment will be created using the `arm/daos/azuredeploy_server.json`
   arm template.
6. All files that were created for the purpose of generating the
   `bin/cloudinit_server.sh` and `arm/daos/azuredeploy_server.*` files will be
   removed.

### Viewing cloud-init files before deployment

To see the files that were used to generate the `bin/cloudinit_server.sh` and
`arm/daos/azuredeploy_server.*` files without doing a deployment,
run the following command.

```
cd "${DAOS_AZ_REPO_HOME}/bin"
./daos_servers.sh --gen-arm --no-clean
```

This creates the following files and does not remove them when finished.

- `bin/cloudinit_*`
- `vm_files/daos_server/*.env`
- `cloudinit_*.sh`

### Viewing cloud-init files after deployment

Log into the VMs

### Troubleshooting cloud-init files on VMs

The cloud-init file is a self-extracting archive.

Extract the files to the `/root` directory.

```bash
/var/lib/cloud/instance/scripts/part-001 --target /root --noexec
```

Now the setup script and environment variables file will be extracted to the
`/root` directory.

```bash
ll /root/*_setup.*
-rw-r--r--. 1 501 games 2372 Mar 21 17:38 /root/daos_server_setup.env
-rwxr-xr-x. 1 501 games 3864 Mar 21 17:25 /root/daos_server_setup.sh
```

You can now edit the environment variables used by the setup script and then
run the setup script with `/root/daos_server_setup.sh`.

### Viewing cloud-init log output

You can grep for 'cloud-init' in `/var/log/messages` on the VMs to view
the cloud-init log output.

```bash
grep -i cloud-init /var/log/messages | less
```


cloud-init runs the script that was embedded in the customData
property of the osProfile for the VM. That script is the
`cloudinit_server.sh` or `cloudinit_client.sh` file that was generated
by the `bin/gen_cloudinit.sh` script.

When `cloudinit_server.sh` or `cloudinit_client.sh` are run they will
extract an archive to a temporary directory and run a setup script.
That setup script will log to `/var/log/daos/daos_server_setup.log` or
`/var/log/daos/daos_client_setup.log`

The `/var/log/daos/daos_*.log` files show the output of a setup script that

  - Installs Ansible
  - Installs Ansible collections
  - Runs an Ansible playbook

**In summary**

  - To view cloud-init log output on DAOS server and client VMs:

    `sudo grep 'cloud-init' /var/log/messages`

  - To view setup script output:
    - DAOS server VMs:

      `sudo less /var/log/daos/daos_server_setup.log`

    - DAOS client VMs:

      `sudo less /var/log/daos/daos_client_setup.log`


## Order of deployment

The order in which resources are deployed is very important.

If resources are not deployed in the proper order, failures will occur.

Deploy resources in the following order:

1. Infrastructure resources
2. DAOS Server Virtual Machine Scale Set
3. DAOS Client Virtual Machine Scale Set

## Deleting resources

To quickly delete all resources delete the resource group that the
resources belong to. Use the *force* option when deleting the resource group.

If the `bin/infrastructure.sh` was used to create the infrastructure
resources, running `bin/infrastructure.sh --undeploy` will delete all
resources and the resource group that contains them.
