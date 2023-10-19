## DAOS on Azure - Infrastructure

### Infrastructure Resources

When deploying DAOS servers and clients using the scripts in this repo it is
assumed that you have already deployed an existing set of *infrastructure* resources.

The Bicep templates for DAOS servers and clients only define a Virtual
Machine Scale Set for the VMs. Other necessary resources such as VNets, Subnets,
Network Security Groups, etc. must exist prior to deploying the DAOS
server and client VMs.

The following *infrastructure* resources are required to exist prior
to deploying DAOS server and client VMs.

| Resource                       | Purpose                                                                                     |
| ------------------------------ | ------------------------------------------------------------------------------------------- |
| Azure Bastion                  | Allows SSH access to VMs                                                                    |
| Key Vault                      | Used to store certficates for deployment                                                    |
| User-Assigned Managed Identity | Identity for DAOS servers and clients. Needs permission to manage secrets in the key vault.                                               |
| NAT Gateway                    | Allows outbound access to DAOS GitHub repos and YUM repos                                   |
| Network Security Group         | NSG with rules to allow outbound access to DAOS repos and inbound SSH from an Azure Bastion |
| Virtual Network                | VNet                                                                                 |
| Subnet                         | Subnet for VMs. All VMs are deployed to the same subnet.                                                                              |

The Network Security Group must contain rules for:
- Outbound HTTPS Access to:
  - https://github.com
  - https://packages.daos.io
- Inbound SSH Access from the Azure bastion to all VMs
- Inbound SSH should be limited to only IPs or CIDRs that need to access VMs via the bastion.

### Deploying Infrastructure Resources

If you are starting with an empty subscription, the easiest way to deploy
the required *infrastructure* resources is to use the `bin/infrastructure.sh` script
in this repo.

The [Quickstart section in the Deployment Guide](deployment.md#quickstart)
assumes that you will deploy the *infrastructure* resources using the
`bin/infrastructure.sh` script.

Many organizations enforce policies on subscriptions and place limitations on
what can be deployed, naming conventions, tags, configurations, open ports,
network security groups and rules, etc.

The `bin/infrastructure.sh` script may not work depending on the policies that
are enforced on your subscription.

Instructions for manually deploying and configuring the required *infrastructure*
resources are beyond the scope of this document. Every organization has policies
that impact how infrastructure resources are deployed and configured. It is
impossible to provide instructions that would work for any organization.

If the required *infrastructure* resources shown in the table above already
exist in your subscription, then you will only need the names and IDs of
those resources in order to set the environment variables in the
[`daos-azure.env` file](env_vars.md).
