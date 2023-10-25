# daos-azure

Automation scripts for deploying DAOS on Azure

## Directory Structure

```
./
├── bicep/        Bicep templates and parameter files
├── bin/          Bash scripts for deployment
├── docs/         Documentation
├── tools/        pre-commit tools
└── vm_files/     Files to be added to self-extracting cloud-init
```

## Deploy DAOS on Azure

See the [Deployment Guide](docs/deployment.md).

## Support

Official support for the content in this repo is not available at this time.

## Software Versions

The content in this repo was tested with the following versions of software.

| Software  | Version     |
| --------- | ----------- |
| Azure CLI | 2.50        |
| jq        | 1.6         |
| makeself  | 2.5.0       |
| Ansible   | core 2.14.2 |
| DAOS      | 2.4.0       |

## Links

- [Distributed Asynchronous Object Storage (DAOS)](https://docs.daos.io/)
- [ansible-collection-daos](https://github.com/daos-stack/ansible-collection-daos)

## License

DAOS is licensed under the BSD-2-Clause Plus Patent License.

The content in this repo is licensed under the same BSD-2-Clause Plus Patent License.

Please see the [LICENSE](./LICENSE) & [NOTICE](./NOTICE) files for more information.
