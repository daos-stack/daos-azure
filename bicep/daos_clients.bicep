param resourcePrefix string = ''
param existingVnetName string
param existingSubnetName string
param existingUamiName string = (empty(resourcePrefix) ? 'daos-uami' : '${resourcePrefix}-daos-uami')
param location string = resourceGroup().location
param vmScalesetName string = (empty(resourcePrefix) ? 'daos-client-vmss' : '${resourcePrefix}-daos-client-vmss')
param clientVmBaseName string = (empty(resourcePrefix) ? 'daos-client' : '${resourcePrefix}-daos-client')
param clientCount int = 3
param clientDiskCount int = 1
param clientDiskSize int = 1024
param clientStorageSku string = 'Premium_LRS'
param clientCacheOption string = 'None'
param clientSku string = 'Standard_L8s_v3'
param adminUserName string = 'daos_admin'
param adminPublicKeyData string = ''
param useAvailabilityZone bool = true
param availabilityZone int = 1
param tagValues object = {
  DAOS_Role: 'Client'
  Resource_Prefix: (empty(resourcePrefix) ? '' : '${resourcePrefix}')
}

var subnet = resourceId(resourceGroup().name, 'Microsoft.Network/virtualNetworks/subnets', existingVnetName, existingSubnetName)
var uamiId = '/subscriptions/${subscription().subscriptionId}/resourceGroups/${resourceGroup().name}/providers/Microsoft.ManagedIdentity/userAssignedIdentities/${existingUamiName}'
var clientImageReference = {
  publisher: 'almalinux'
  offer: 'almalinux-x86_64'
  sku: '8-gen2'
  version: '8.10.2024082001'
}
var clientDataDisks = [for i in range(0, clientDiskCount): {
  caching: clientCacheOption
  managedDisk: {
    storageAccountType: clientStorageSku
  }
  createOption: 'Empty'
  lun: i
  diskSizeGB: clientDiskSize
}]
// The imagePlan is necessary if you are using an image that is published in the
// Azure Marketplace. If you are using an image that is not in the marketplace,
// you can remove the imagePlan.  Originally we used an Almalinux 8.7 image from
// the Azure Marketplace, but when we tried to use an Almalinux 8.10 image we
// encountered errors. The error message stated that the image was not in the
// Marketplace and that plan information is not required. So this is now
// commented out.
// var imagePlan = {
//   name: '8-gen2'
//   publisher: 'almalinux'
//   product: 'almalinux-x86_64'
// }
var ciScriptClient = base64(loadTextContent('../bin/cloudinit_client.sh'))

resource vmss 'Microsoft.Compute/virtualMachineScaleSets@2023-03-01' = {
  name: vmScalesetName
  location: location
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${uamiId}': {}
    }
  }
  // See the comment on the imagePlan variable above
  // plan: imagePlan
  zones: useAvailabilityZone ? [string(availabilityZone)] : []
  sku: {
    name: clientSku
    tier: 'Standard'
    capacity: clientCount
  }
  properties: {
    overprovision: false
    upgradePolicy: {
      mode: 'Manual'
    }
    virtualMachineProfile: {

      storageProfile: {
        imageReference: clientImageReference
        osDisk: {
          osType: 'Linux'
          createOption: 'FromImage'
          caching: 'ReadWrite'
          managedDisk: {
            storageAccountType: 'Premium_LRS'
          }
          diskSizeGB: 30
        }
        dataDisks: clientDataDisks
      }
      osProfile: {
        computerNamePrefix: '${clientVmBaseName}-'
        adminUsername: adminUserName
        customData: ciScriptClient
        linuxConfiguration: {
          disablePasswordAuthentication: true
          ssh: {
            publicKeys: [
              {
                path: '/home/${adminUserName}/.ssh/authorized_keys'
                keyData: adminPublicKeyData
              }
            ]
          }
        }
      }
      networkProfile: {
        networkInterfaceConfigurations: [
          {
            name: '${clientVmBaseName}-nic'
            properties: {
              primary: true
              enableAcceleratedNetworking: true
              ipConfigurations: [
                {
                  name: '${clientVmBaseName}-ipConfig-vmss'
                  properties: {
                    subnet: {
                      id: subnet
                    }
                  }
                }
              ]
            }
          }
        ]
      }
    }
  }
  tags: tagValues
}

// Add resourceIds to this array that should be cleaned up
// when running `bin/daos_servers.sh --undeploy`
output resourceIds array = [
  vmss.id
]
