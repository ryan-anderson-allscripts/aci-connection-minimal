﻿// =========== PARAMETERS ===========
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

@description('Port to open on the container and the public IP address.')
param ports int[] = [8080,8081]

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
var managedIdentityName = '${appPrefix}-mi'
var vaultSecretUserRoleId = '4633458b-17de-408a-b874-0445c86b69e6'
var subnetRID = resourceId(vnetGroup, 'Microsoft.Network/virtualNetworks/subnets', vnetName, subnetName)

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

// create container group
resource containerGroup 'Microsoft.ContainerInstance/containerGroups@2023-05-01' = {
  name: appName
  location: location
  dependsOn: [
    vaultSecrets
    acrPull
  ]
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${managedIdentity.id}': {}
    }
  }
  properties: {
    imageRegistryCredentials: [
      {
        server: acrServer
        identity: managedIdentity.id
      }
    ]
    ipAddress: {
        type: 'Private'
        // type: 'Public'
        ports: [for port in ports: {
          port: port
          protocol: 'TCP'
        }]
    }
    containers: [
      {
        name: containerName
        properties: {
          image: '${acrServer}/${imageName}:${imageTag}'
          ports: [for port in ports: {
            port: port
            protocol: 'TCP'
          }]
          environmentVariables: [
          ]
          resources: {
            requests: {
              cpu: cpuCores
              memoryInGB: memoryInGb
            }
          }
        }
      }
    ]
    osType: osType
    subnetIds: [ { id: subnetRID } ]
    restartPolicy: restartPolicy
  }
}
