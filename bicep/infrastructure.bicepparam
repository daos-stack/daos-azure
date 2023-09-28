using './infrastructure.bicep'

param resourcePrefix = string(readEnvironmentVariable('DAOS_AZ_CORE_RESOURCE_PREFIX'))
param keyVaultName = string(readEnvironmentVariable('DAOS_AZ_ARM_KEY_VAULT_NAME'))
