# daos-azure

Automation scripts for deploying DAOS on Azure

## Directory Structure

```
./
├── arm/
│   └── daos/     ARM Templates for DAOS
├── bin/          Bash scripts for deployment
├── docs/         Documentation
├── images/       Packer, Ansible and other files for image builds
├── vm_files/     Files to be added to self-extracting cloud-init scripts
├── LICENSE
└── README.md
```

## Deploy DAOS on Azure

1. **Install necessary software**
   See [Prerequisites](./docs/prerequisites.md) for instructions.

2. **Deploy Infrastructure Resources**
   You will need to create many resources that make up the "infrastructure"
   required for a DAOS Server deployment.

   TODO: Create documentation for creating infrastructure resources.
         Currently we are using a Terraform configuration in a private repo.

3. **Create a `daos-azure.env` file**
   All bash scripts will source a file named `daos-azure.env` located in the
   root of the local clone of this repo.

   To create the `daos-azure.env` file make a copy of the `daos-azure.env.example` file.

   ```bash
   cp daos-azure.env.example daos-azure.env
   ```

   Modify the variable values to contain the settings for your deployment.

4. **Build the DAOS image**

   ```bash
   cd images
   ./build.sh
   ```

   See [images/README.md](./images/README.md) for details.

5. **Deploy DAOS Servers**

   ```bash
   cd bin
   ./daos_servers_deploy.sh
   ```

6. **Deploy DAOS Clients**

   TODO: Still need to create ARM templates and scripts for client deployments.

7. **Log into first server**

   TODO: Provide instructions for setting up an Azure bastion and tunneling through it to the first server VM.

8. **Undeploy the Servers**

   ```bash
   cd bin
   ./daos_servers_undeploy.sh
   ```

## Support

As this repo is in the very early stages of development there is not official support for the content within.

More information will be added later.

## Versions

The content in this repo was tested with the following versions of software.

| Software  | Version     |
| --------- | ----------- |
| Packer    | v1.9.1      |
| Azure CLI | v2.48.1     |
| jq        | v1.6        |
| makeself  | v2.5.0      |
| DAOS      | v2.3.108-tb |

Newer versions of software may introduce changes that impact successful deployments.

## Support

TBD

## Links

- [Distributed Asynchronous Object Storage (DAOS)](https://docs.daos.io/)
- [Packer](https://www.packer.io/)
- [Ansible](https://docs.ansible.com/ansible/latest/)

## License

DAOS is licensed under the BSD-2-Clause Plus Patent License. Please see the [LICENSE](./LICENSE) & [NOTICE](./NOTICE) files for more information.
