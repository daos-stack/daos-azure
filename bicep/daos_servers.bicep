param resourcePrefix string = ''
param existingVnetName string
param existingSubnetName string
param existingUamiName string = (empty(resourcePrefix) ? 'daos-uami' : '${resourcePrefix}-daos-uami')
param location string = resourceGroup().location
param vmScalesetName string = (empty(resourcePrefix) ? 'daos-server-vmss' : '${resourcePrefix}-daos-server-vmss')
param serverVmBaseName string = (empty(resourcePrefix) ? 'daos-server' : '${resourcePrefix}-daos-server')
param serverCount int = 3
param serverDiskCount int = 1
param serverDiskSize int = 1024
param serverStorageSku string = 'Premium_LRS'
param serverCacheOption string = 'None'
param serverSku string = 'Standard_L8s_v3'
param adminUserName string = 'daos_admin'
param adminPublicKeyData string = ''
param useAvailabilityZone bool = true
param availabilityZone int = 1

var subnet = resourceId(resourceGroup().name, 'Microsoft.Network/virtualNetworks/subnets', existingVnetName, existingSubnetName)
var uamiId = '/subscriptions/${subscription().subscriptionId}/resourceGroups/${resourceGroup().name}/providers/Microsoft.ManagedIdentity/userAssignedIdentities/${existingUamiName}'
var serverImageReference = {
  publisher: 'almalinux'
  offer: 'almalinux'
  sku: '8-gen2'
  version: 'latest'
}
var serverDataDisks = [for i in range(0, serverDiskCount): {
  caching: serverCacheOption
  managedDisk: {
    storageAccountType: serverStorageSku
  }
  createOption: 'Empty'
  lun: i
  diskSizeGB: serverDiskSize
}]
var imagePlan = {
  name: '8-gen2'
  publisher: 'almalinux'
  product: 'almalinux'
}
var ciScriptServer = base64(loadTextContent('../bin/cloudinit_server.sh'))

resource vmss 'Microsoft.Compute/virtualMachineScaleSets@2023-03-01' = {
  name: vmScalesetName
  location: location
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${uamiId}': {}
    }
  }
  plan: imagePlan
  zones: useAvailabilityZone ? [string(availabilityZone)] : []
  sku: {
    name: serverSku
    tier: 'Standard'
    capacity: serverCount
  }
  properties: {
    overprovision: false
    upgradePolicy: {
      mode: 'Manual'
    }
    virtualMachineProfile: {

      storageProfile: {
        imageReference: serverImageReference
        osDisk: {
          osType: 'Linux'
          createOption: 'FromImage'
          caching: 'ReadWrite'
          managedDisk: {
            storageAccountType: 'Premium_LRS'
          }
          diskSizeGB: 30
        }
        dataDisks: serverDataDisks
      }
      osProfile: {
        computerNamePrefix: '${serverVmBaseName}-'
        adminUsername: adminUserName
        customData: ciScriptServer
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
            name: '${serverVmBaseName}-nic'
            properties: {
              primary: true
              enableAcceleratedNetworking: true
              ipConfigurations: [
                {
                  name: '${serverVmBaseName}-ipConfig-vmss'
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
}

// Add resourceIds to this array that should be cleaned up
// when running `bin/daos_servers.sh --undeploy`
output resourceIds array = [
  vmss.id
]
