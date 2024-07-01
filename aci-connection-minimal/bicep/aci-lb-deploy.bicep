// =========== PARAMETERS ===========
@description('Prefix for container group resources')
param appPrefix string = 'aci-min'

@description('Location for all resources.')
param location string = resourceGroup().location

@description('Azure container registry (ACR) name')
param acrName string = 'ops5containers'

@description('Resource group for ACR')
param acrGroup string = 'op5-container-rg'

@description('Container image to deploy. Should be of the form repoName/imagename:tag for images stored in public Docker Hub, or a fully qualified URI for other registries. Images from private registries require additional registry credentials.')
param imageName string = 'dev/aciminimal'

@description('Image tag. Defaults to "latest"')
param imageTag string = 'latest'

@description('ACI os type. Defaults to Windows')
@allowed([
  'Windows'
  'Linux'
])
param osType string = 'Windows'

@description('Name of the application key vault')
param appVaultName string = 'op5-0-aks-kv'

@description('Resource group for application vault')
param appVaultGroup string = 'op5-container-rg'

// @description('Port to open on the container and the public IP address.')
// param ports int[] = [8080,8081]

@description('The number of CPU cores to allocate to the container.')
param cpuCores int = 1

@description('The amount of memory to allocate to the container in gigabytes.')
param memoryInGb int = 2

@description('The virtual network to attach this instance to')
param vnetName string = 'xys-1-vnet'

@description('The subnet on the virtual network')
param subnetName string = 'xys-1-appsvc-snet'

@description('The resource group for the virtual network')
param vnetGroup string = 'xys-0-net-rg'

@description('The behavior of Azure runtime if container has stopped.')
@allowed([
  'Always'
  'Never'
  'OnFailure'
])
param restartPolicy string = 'Never'

// =========== VARIABLES ===========
var acrServer = '${acrName}.azurecr.io'
var appName = '${appPrefix}-ci'
var containerName = '${appPrefix}-container'
var gwName = '${appPrefix}-gw'
// var lbName = '${appPrefix}-lb'
var managedIdentityName = '${appPrefix}-mi'
var vaultSecretUserRoleId = '4633458b-17de-408a-b874-0445c86b69e6'
var vnetRID = resourceId(vnetGroup, 'Microsoft.Network/virtualNetworks', vnetName)
var subnetRID = resourceId(vnetGroup, 'Microsoft.Network/virtualNetworks/subnets', vnetName, subnetName)

var portSettings = [
  {externalPort: 80, internalPort: 8080, protocol: 'http'}
  {externalPort: 443, internalPort: 8081, protocol: 'https'}
]

// =========== RESOURCES ===========

// create managed identity
resource managedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2018-11-30' = {
  name: managedIdentityName
  location: location
}

// resource vNet 'Microsoft.Network/virtualNetworks@2023-11-01' existing = {
//   name: vnetName
//   scope: resourceGroup(vnetGroup)
// }
// resource subnet 'Microsoft.Network/virtualNetworks/subnets@2023-11-01' existing = {
//     name:subnetName
//     parent: vNet
// }

// assign Key Vault Secrets Reader to MI
module vaultSecrets './modules/assign-vault-role.bicep' = {
  name: guid(managedIdentity.id, appVaultName, vaultSecretUserRoleId)
  scope: resourceGroup(subscription().subscriptionId, appVaultGroup)
  params: {
    vaultName: appVaultName
    principalId: managedIdentity.properties.principalId
    vaultRoleId: vaultSecretUserRoleId
  }
}

// assign ACRPull to MI
module acrPull './modules/assign-acrpull-role.bicep' = {
  name: guid(managedIdentity.id, acrName, vaultSecretUserRoleId)
  scope: resourceGroup(subscription().subscriptionId, acrGroup)
  params: {
    acrName: acrName
    principalId: managedIdentity.properties.principalId
  }
}

resource publicIp 'Microsoft.Network/publicIPAddresses@2023-11-01' = {
  name: '${appName}-pi'
  location: location
  sku: { 
    name: 'Standard' 
    tier: 'Regional'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
    ddosSettings: {
      protectionMode: 'VirtualNetworkInherited'
    }
  }
}
resource gw 'Microsoft.Network/applicationGateways@2023-11-01' = {
  name: gwName
  location: location
  properties: {
    sku: {
      name: 'Standard_Small'
      tier: 'Standard_v2'
    }
    frontendIPConfigurations: [
      {
        name: 'frontend'
        properties: {
          publicIPAddress: { id: publicIp.id }
        }
      }
    ]
    frontendPorts: [for port in portSettings: {
        name: 'frontend-${port.protocol}'
        properties:{ port: port.externalPort }
      }]
    backendAddressPools: [
      {
        name: 'backend-pool'
        properties: {
          backendAddresses: [ { ipAddress: containerGroup.properties.ipAddress.ip } ]
        }
      }
    ]
    backendHttpSettingsCollection: [for port in portSettings: {
        name: '${port.protocol}Settings'
        properties: {
          protocol: port.protocol
          port: port.internalPort
        }
      }]
    probes: [for port in portSettings: {
        name: port.protocol
        properties: { port: port.externalPort, protocol: port.protocol, path: '/' }
      }]
    httpListeners: [for port in portSettings: {
        name: 'listener-${port.protocol}'
        properties: {
          frontendIPConfiguration: {
            id: resourceId('Microsoft.Network/applicationGateways/frontendIPConfigurations', gwName, 'frontend')
          }
          frontendPort: {
            id: resourceId('Microsoft.Network/applicationGateways/frontendPorts', gwName, 'frontend-${port.protocol}')
          }
          protocol: port.protocol
        }
      }]
    requestRoutingRules: [for port in portSettings: {
        name: 'route-${port.protocol}-${port.externalPort}-${port.internalPort}'
        properties: {
          priority: 100
          ruleType: 'Basic'
          httpListener: {
            id: resourceId('Microsoft.Network/applicationGateways/httpListeners', gwName, 'listener-${port.protocol}')
          }
          backendAddressPool: {
            id: resourceId('Microsoft.Network/applicationGateways/backendAddressPools', gwName, 'backend-pool')
          }
          backendHttpSettings: {
            id: resourceId('Microsoft.Network/applicationGateways/backendHttpSettingsCollection', gwName, '${port.protocol}Settings')
          }
        }
      }]  
    // loadBalancingRules: [
    //   {
    //     name: 'Http'
    //     properties: {
    //       protocol: 'Tcp'
    //       frontendPort: 80
    //       backendPort: 8080
    //       frontendIPConfiguration: { id: resourceId('Microsoft.Network/applicationGateways/frontendIPConfigurations', gwName, 'frontend') }
    //       probe: { id: resourceId('Microsoft.Network/applicationGateways/probes', gwName, 'http') }
    //       backendAddressPool: { id: resourceId('Microsoft.Network/applicationGateways/backendAddressPools', gwName, 'backend-pool') }
    //       disableOutboundSnat: true
    //     }
    //   }
    //   {
    //     name: 'Https'
    //     properties: {
    //       protocol: 'Tcp'
    //       frontendPort: 443
    //       backendPort: 8081
    //       frontendIPConfiguration: { id: resourceId('Microsoft.Network/applicationGateways/frontendIPConfigurations', gwName, 'frontend') }
    //       probe: { id: resourceId('Microsoft.Network/applicationGateways/probes', gwName, 'https') }
    //       backendAddressPool: { id: resourceId('Microsoft.Network/applicationGateways/backendAddressPools', gwName, 'backend-pool') }
    //       disableOutboundSnat: true
    //     }
    //   }
    // ]
  }
  dependsOn: [
    publicIp
    containerGroup
  ]
}
/*
// Load balancers against ACI not supported
// https://learn.microsoft.com/en-us/azure/container-instances/container-instances-virtual-network-concepts
resource lb 'Microsoft.Network/loadBalancers@2023-11-01' = {
  name: lbName
  location: location
  sku: {
    name: 'Standard'
    tier: 'Regional'
  }
  properties: {
    frontendIPConfigurations: [
      {
        name: 'frontend'
        properties: {
          publicIPAddress: { id: publicIp.id }
        }
      }
    ]
    backendAddressPools: [
      {
        name: 'backend-pool'
        properties: {
          loadBalancerBackendAddresses: [
            {
              name: '${appName}-backend'
              properties: {
                virtualNetwork: { id: vnetRID }
                subnet: { id: subnetRID }
                ipAddress: containerGroup.properties.ipAddress.ip
              }
            }
          ]
        }
      }
    ]
    probes: [
      {
        name: 'http'
        properties: {
          port: 80
          protocol: 'Http'
          requestPath: '/'
        }
      }
      {
        name: 'https'
        properties: {
          port: 443
          protocol: 'Https'
          requestPath: '/'
        }
      }
    ]
    loadBalancingRules: [
      {
        name: 'Http'
        properties: {
          protocol: 'Tcp'
          frontendPort: 80
          backendPort: 8080
          frontendIPConfiguration: { id: resourceId('Microsoft.Network/loadbalancers/frontendIPConfigurations', lbName, 'frontend') }
          probe: { id: resourceId('Microsoft.Network/loadBalancers/probes', lbName, 'http') }
          backendAddressPool: { id: resourceId('Microsoft.Network/loadbalancers/backendAddressPools', lbName, 'backend-pool') }
          disableOutboundSnat: true
        }
      }
      {
        name: 'Https'
        properties: {
          protocol: 'Tcp'
          frontendPort: 443
          backendPort: 8081
          frontendIPConfiguration: { id: resourceId('Microsoft.Network/loadbalancers/frontendIPConfigurations', lbName, 'frontend') }
          probe: { id: resourceId('Microsoft.Network/loadBalancers/probes', lbName, 'https') }
          backendAddressPool: { id: resourceId('Microsoft.Network/loadbalancers/backendAddressPools', lbName, 'backend-pool') }
          disableOutboundSnat: true
        }
      }
    ]
  }
  dependsOn: [
    publicIp
    containerGroup
  ]
}
*/
resource containerGroup 'Microsoft.ContainerInstance/containerGroups@2023-05-01' existing = {
  name: appName
}
// create container group
// resource containerGroup 'Microsoft.ContainerInstance/containerGroups@2023-05-01' = {
//   name: appName
//   location: location
//   dependsOn: [
//     vaultSecrets
//     acrPull
//   ]
//   identity: {
//     type: 'UserAssigned'
//     userAssignedIdentities: {
//       '${managedIdentity.id}': {}
//     }
//   }
//   properties: {
//     imageRegistryCredentials: [
//       {
//         server: acrServer
//         identity: managedIdentity.id
//       }
//     ]
//     ipAddress: {
//         type: 'Private'
//         ports: [for port in portSettings: {
//           port: port.internalPort
//           protocol: 'TCP'
//         }]
//     }
//     containers: [
//       {
//         name: containerName
//         properties: {
//           image: '${acrServer}/${imageName}:${imageTag}'
//           ports: [for port in portSettings: {
//             port: port.internalPort
//             protocol: 'TCP'
//           }]
//           environmentVariables: [
//           ]
//           resources: {
//             requests: {
//               cpu: cpuCores
//               memoryInGB: memoryInGb
//             }
//           }
//         }
//       }
//     ]
//     osType: osType
//     subnetIds: [ { id: subnetRID } ]
//     restartPolicy: restartPolicy
//   }
// }
