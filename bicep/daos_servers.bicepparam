using './daos_servers.bicep'

param existingVnetName = string(readEnvironmentVariable('DAOS_AZ_ARM_NET_VNET_NAME'))
param existingSubnetName = string(readEnvironmentVariable('DAOS_AZ_ARM_NET_SUBNET_NAME'))
param resourcePrefix = string(readEnvironmentVariable('DAOS_AZ_CORE_RESOURCE_PREFIX'))
param adminPublicKeyData = string(readEnvironmentVariable('DAOS_AZ_SSH_ADMIN_KEY_PUB_DATA'))
param serverCount = int(readEnvironmentVariable('DAOS_AZ_ARM_SERVER_COUNT'))
