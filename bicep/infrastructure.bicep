param resourceGroupId string = resourceGroup().id
param location string = resourceGroup().location
param resourcePrefix string = ''
param uamiName string = (empty(resourcePrefix) ? 'daos-uami' : '${resourcePrefix}-daos-uami')
param natGatewayPublicIpName string = (empty(resourcePrefix) ? 'daos-gw-pip' : '${resourcePrefix}-daos-gw-pip')
param natGatewayPublicIpDns string = (empty(resourcePrefix) ? '${uniqueString(resourceGroup().id)}-daos-gw' : '${uniqueString(resourceGroup().id)}-daos-gw' )
param natGatewayName string = (empty(resourcePrefix) ? 'daos-gw' : '${resourcePrefix}-daos-gw')
param networkSecurityGroupName string = (empty(resourcePrefix) ? 'daos-nsg' : '${resourcePrefix}-daos-nsg')
param virtualNetworkName string = (empty(resourcePrefix) ? 'daos-vnet' : '${resourcePrefix}-daos-vnet')
param subnetName string = (empty(resourcePrefix) ? 'daos-sn' : '${resourcePrefix}-daos-sn')
param keyVaultName string = ''
param keyVaultPrivateEndpointName string = '${keyVaultName}-private-endpoint'
param keyVaultprivateDnsZone string = 'privatelink.vaultcore.azure.net'
param bastionPublicIpName string = (empty(resourcePrefix) ? 'daos-bastion-pip' : '${resourcePrefix}-daos-bastion-pip')
param bastionHostName string = (empty(resourcePrefix) ? 'daos-bastion' : '${resourcePrefix}-daos-bastion')
param nsgSecurityRules array = [
  {
    name: 'AllowLoadBalancerInbound'
    properties: {
      protocol: 'Tcp'
      sourceAddressPrefix: 'AzureLoadBalancer'
      sourcePortRange: '*'
      destinationAddressPrefix: 'VirtualNetwork'
      destinationPortRange: '*'
      access: 'Allow'
      direction: 'Inbound'
      priority: 130
    }
  }
  {
    name: 'AllowSshOutBound'
    properties: {
      protocol: 'Tcp'
      sourcePortRange: '*'
      sourceAddressPrefix: '*'
      destinationPortRanges: [
        '22'
      ]
      destinationAddressPrefix: 'VirtualNetwork'
      access: 'Allow'
      priority: 100
      direction: 'Outbound'
    }
  }
  {
    name: 'AllowBastionHostCommunicationOutBound'
    properties: {
      protocol: '*'
      sourcePortRange: '*'
      sourceAddressPrefix: 'VirtualNetwork'
      destinationPortRanges: [
        '8080'
        '5701'
      ]
      destinationAddressPrefix: 'VirtualNetwork'
      access: 'Allow'
      priority: 120
      direction: 'Outbound'
    }
  }
  {
    name: 'AllowGetSessionInformationOutBound'
    properties: {
      protocol: '*'
      sourcePortRange: '*'
      sourceAddressPrefix: '*'
      destinationAddressPrefix: 'Internet'
      destinationPortRanges: [
        '80'
        '443'
      ]
      access: 'Allow'
      priority: 130
      direction: 'Outbound'
    }
  }
  {
    name: 'DenyAllOutBound'
    properties: {
      protocol: '*'
      sourcePortRange: '*'
      destinationPortRange: '*'
      sourceAddressPrefix: '*'
      destinationAddressPrefix: '*'
      access: 'Deny'
      priority: 1000
      direction: 'Outbound'
    }
  }
]
param tagValues object = {
  ResourcePrefix: (empty(resourcePrefix) ? '' : '${resourcePrefix}')
}

var uamiRoles = [
  {
    name: 'Contributor'
    id: '/subscriptions/${subscription().subscriptionId}/providers/Microsoft.Authorization/roleDefinitions/b24988ac-6180-42a0-ab88-20f7382dd24c'
  }
  {
    name: 'Key Vault Administrator'
    id: '/subscriptions/${subscription().subscriptionId}/providers/Microsoft.Authorization/roleDefinitions/00482a5a-887f-4fb3-b363-3b7fe8e74483'
  }
  {
    name: 'Virtual Machine Contributor'
    id: '/subscriptions/${subscription().subscriptionId}/providers/Microsoft.Authorization/roleDefinitions/9980e02c-c2be-4d73-94e8-173b1dc7cf3c'
  }
  {
    name: 'Managed Identity Operator'
    id: '/subscriptions/${subscription().subscriptionId}/providers/Microsoft.Authorization/roleDefinitions/f1a07417-d97a-45cb-824c-7a7467783830'
  }
]

var natGatewayPublicIpAddresses = [
  {
    id: natGatewayPublicIp.id
  }
]

resource managedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: uamiName
  location: location
  tags: tagValues
}

resource roleAssignment 'Microsoft.Authorization/roleAssignments@2020-04-01-preview' = [for role in uamiRoles: {
  name: guid(managedIdentity.name, role.id, resourceGroupId) // Ensuring a unique ID for the role assignment
  properties: {
    roleDefinitionId: role.id
    principalId: managedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}]

resource natGatewayPublicIp 'Microsoft.Network/publicIPAddresses@2023-04-01' = {
  name: natGatewayPublicIpName
  location: location
  tags: tagValues
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAddressVersion: 'IPv4'
    publicIPAllocationMethod: 'Static'
    idleTimeoutInMinutes: 4
    dnsSettings: {
      domainNameLabel: natGatewayPublicIpDns
    }
  }
}

resource networkSecurityGroup 'Microsoft.Network/networkSecurityGroups@2023-04-01' = {
  name: networkSecurityGroupName
  location: location
  properties: {
    securityRules: nsgSecurityRules
  }
  tags: tagValues
}

resource natGateway 'Microsoft.Network/natGateways@2023-04-01' = {
  name: natGatewayName
  location: location
  tags: tagValues
  sku: {
    name: 'Standard'
  }
  properties: {
    idleTimeoutInMinutes: 4
    publicIpAddresses: !empty(natGatewayPublicIpDns) ? natGatewayPublicIpAddresses : null
  }
}

resource virtualNetwork 'Microsoft.Network/virtualNetworks@2023-04-01' = {
  name: virtualNetworkName
  location: location
  tags: tagValues
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.0.0.0/16'
      ]
    }
    subnets: [
      {
        name: subnetName
        properties: {
          addressPrefix: '10.0.2.0/24'
          natGateway: {
            id: natGateway.id
          }
          serviceEndpoints: [
            {
              locations: [
                location
              ]
              service: 'Microsoft.KeyVault'
            }
          ]
        }
      }
    ]
  }

}

resource keyVault 'Microsoft.KeyVault/vaults@2022-07-01' = {
  name: keyVaultName
  location: location
  tags: tagValues
  properties: {
    enabledForDeployment: true
    enabledForDiskEncryption: true
    enabledForTemplateDeployment: true
    enableRbacAuthorization: true
    publicNetworkAccess: 'disabled'
    tenantId: tenant().tenantId
    accessPolicies: []
    sku: {
      name: 'standard'
      family: 'A'
    }
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Deny'
    }
  }
}

resource keyVaultPrivateEndpoint 'Microsoft.Network/privateEndpoints@2023-04-01' = {
  name: keyVaultPrivateEndpointName
  location: location
  tags: tagValues
  properties: {
    privateLinkServiceConnections: [
      {
        name: keyVaultPrivateEndpointName
        properties: {
          privateLinkServiceId: keyVault.id
          groupIds: [
            'vault'
          ]
        }
      }
    ]
    subnet: {
      id: virtualNetwork.properties.subnets[0].id
    }
  }
}

resource keyVaultPrivateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: keyVaultprivateDnsZone
  location: 'global'
  tags: tagValues
}

resource keyVaultPrivateEndpointDns 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-04-01' = {
  parent: keyVaultPrivateEndpoint
  name: 'vault-PrivateDnsZoneGroup'
  properties:{
    privateDnsZoneConfigs: [
      {
        name: keyVaultPrivateDnsZone.name
        properties:{
          privateDnsZoneId: keyVaultPrivateDnsZone.id
        }
      }
    ]
  }
}

resource keyVaultPrivateDnsZoneVnetLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: keyVaultPrivateDnsZone
  name: uniqueString(keyVault.id)
  location: 'global'
  tags: tagValues
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: virtualNetwork.id
    }
  }
}

resource bastionSubnet 'Microsoft.Network/virtualNetworks/subnets@2023-04-01' = {
  parent: virtualNetwork
  name: 'AzureBastionSubnet'
  properties: {
    addressPrefix: '10.0.1.0/24'
    privateEndpointNetworkPolicies: 'Disabled'
    privateLinkServiceNetworkPolicies: 'Disabled'
  }
}

resource bastionPublicIp 'Microsoft.Network/publicIPAddresses@2023-04-01' = {
  name: bastionPublicIpName
  location: location
  tags: tagValues
  sku: {
    name: 'Standard'
    tier: 'Regional'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

resource bastionHost 'Microsoft.Network/bastionHosts@2023-04-01' = {
  name: bastionHostName
  location: location
  tags: tagValues
  sku: {
    name: 'Standard'
  }
  properties: {
    disableCopyPaste: false
    enableFileCopy: true
    enableIpConnect: true
    enableTunneling: true
    ipConfigurations: [
      {
        name: 'bastionIpConf'
        properties: {
          subnet: {
            id: bastionSubnet.id
          }
          publicIPAddress: {
            id: bastionPublicIp.id
          }
        }
      }
    ]
  }
}

output resourcePrefix string = resourcePrefix
output resourceGroupName string = resourceGroup().name
output location string = location
output managedIdentityName string = managedIdentity.name
output managedIdentityId string = managedIdentity.id
output natGatewayPublicIpName string = natGatewayPublicIp.name
output natGatewayPublicIpId string = natGatewayPublicIp.id
output networkSecurityGroupName string = networkSecurityGroup.name
output networkSecurityGroupId string = networkSecurityGroup.id
output natGatewayName string = natGateway.name
output natGatewayId string = natGateway.id
output virtualNetworkName string = virtualNetwork.name
output virtualNetworkId string = virtualNetwork.id
output keyVaultName string = keyVault.name
output keyVaultId string = keyVault.id
output keyVaultPrivateEndpointName string = keyVaultPrivateEndpoint.name
output keyVaultPrivateEndpointId string = keyVaultPrivateEndpoint.id
output keyVaultPrivateDnsZoneName string = keyVaultPrivateDnsZone.name
output keyVaultPrivateDnsZoneId string = keyVaultPrivateDnsZone.id
output keyVaultPrivateEndpointDnsName string = keyVaultPrivateEndpointDns.name
output keyVaultPrivateEndpointDnsId string = keyVaultPrivateEndpointDns.id
output keyVaultPrivateDnsZoneVnetLinkName string = keyVaultPrivateDnsZoneVnetLink.name
output keyVaultPrivateDnsZoneVnetLinkId string = keyVaultPrivateDnsZoneVnetLink.id
output bastionSubnetName string = bastionSubnet.name
output bastionSubnetId string = bastionSubnet.id
output bastionPublicIpName string = bastionPublicIp.name
output bastionPublicIpId string = bastionPublicIp.id
output bastionHostName string = bastionHost.name
output bastionHostId string = bastionHost.id
output tags object = tagValues
