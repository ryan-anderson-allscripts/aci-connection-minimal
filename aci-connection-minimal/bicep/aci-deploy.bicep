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

@description('Name of the application key vault')
param appVaultName string = 'op5-0-aks-kv'

@description('Resource group for application vault')
param appVaultGroup string = 'op5-container-rg'

@description('Port to open on the container and the public IP address.')
param port int = 8080

@description('The number of CPU cores to allocate to the container.')
param cpuCores int = 1

@description('The amount of memory to allocate to the container in gigabytes.')
param memoryInGb int = 2

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

// =========== RESOURCES ===========

// create managed identity
resource managedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2018-11-30' = {
  name: managedIdentityName
  location: location
}

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

// create container group
resource containerGroup 'Microsoft.ContainerInstance/containerGroups@2023-05-01' = {
  name: appName
  location: location
  dependsOn: [
    vaultSecrets
    acrPull
  ]
  identity: {
    type: 'SystemAssigned, UserAssigned'
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
        type: 'Public'
          ports: [
            {
              port: port
              protocol: 'TCP'
            }
          ]
    }
    containers: [
      {
        name: containerName
        properties: {
          image: '${acrServer}/${imageName}'
          ports: [
            {
              port: port
              protocol: 'TCP'
            }
          ]
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
    osType: 'Windows'
    restartPolicy: restartPolicy
  }
}
