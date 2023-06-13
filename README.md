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

2. **Build the DAOS image**
   See [images/README.md](./images/README.md) for details.

3. **Deploy DAOS Servers**

   Deploy the default configuration consisting of 3 servers.

   ```bash
   cd bin
   ./daos_servers_deploy.sh
   ```

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
