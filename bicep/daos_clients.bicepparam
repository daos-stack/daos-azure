using './daos_clients.bicep'

param existingVnetName = string(readEnvironmentVariable('DAOS_AZ_ARM_NET_VNET_NAME'))
param existingSubnetName = string(readEnvironmentVariable('DAOS_AZ_ARM_NET_SUBNET_NAME'))
param resourcePrefix = string(readEnvironmentVariable('DAOS_AZ_CORE_RESOURCE_PREFIX'))
param adminPublicKeyData = string(readEnvironmentVariable('DAOS_AZ_SSH_ADMIN_KEY_PUB_DATA'))
param clientCount = int(readEnvironmentVariable('DAOS_AZ_ARM_CLIENT_COUNT'))
