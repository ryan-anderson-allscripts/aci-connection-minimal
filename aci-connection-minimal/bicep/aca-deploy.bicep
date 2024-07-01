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
param subnetName string = 'xys-1-pri-snet'

@description('The resource group for the virtual network')
param vnetGroup string = 'xys-0-net-rg'

// =========== VARIABLES ===========
var acrServer = '${acrName}.azurecr.io'
var appName = '${appPrefix}-ca'
var containerAppEnvName = '${appPrefix}-env'
var containerAppLogAnalyticsName = '${appPrefix}-logs'
var managedIdentityName = '${appPrefix}-mi'
var vaultSecretUserRoleId = '4633458b-17de-408a-b874-0445c86b69e6'
var subnetRID = resourceId(vnetGroup, 'Microsoft.Network/virtualNetworks/subnets', vnetName, subnetName)

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

resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2021-06-01' existing = {
  name: containerAppLogAnalyticsName
}
// resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2021-06-01' = {
//   name: containerAppLogAnalyticsName
//   location: location
//   properties: {
//     sku: {
//       name: 'PerGB2018'
//     }
//     retentionInDays: 30
//   }
// }

resource containerAppEnv 'Microsoft.App/managedEnvironments@2022-06-01-preview' existing = {
  name: containerAppEnvName
}

// resource containerAppEnv 'Microsoft.App/managedEnvironments@2022-06-01-preview' = {
//   name: containerAppEnvName
//   location: location
//   sku: {
//     name: 'Consumption'
//   }
//   properties: {
//     appLogsConfiguration: {
//       destination: 'log-analytics'
//       logAnalyticsConfiguration: {
//         customerId: logAnalytics.properties.customerId
//         sharedKey: logAnalytics.listKeys().primarySharedKey
//       }
//     }
//     vnetConfiguration: {
//       infrastructureSubnetId: subnetRID
//     }
//   }
//   dependsOn: [logAnalytics]
// }


resource containerApp 'Microsoft.App/containerApps@2024-03-01' = {
  name: appName
  location: location
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${managedIdentity.id}': {}
    }
  }
  properties: {
    managedEnvironmentId: containerAppEnv.id
    configuration: {
      ingress: {
        external: true
        targetPort: ports[1]
        allowInsecure: false
        traffic: [
          {
            latestRevision: true
            weight: 100
          }
        ]
      }
      registries: [
        {
          server: acrServer
          identity: managedIdentity.id
        }
      ]
      // secrets: [
      //   {
      //     name: 'scm-service'
      //     keyVaultUrl: '${vaultUrl}/secrets/PSCMServices'
      //     identity: managedIdentity.id
      //   }
      //   {
      //     name: 'scm-app-pool'
      //     keyVaultUrl: '${vaultUrl}/secrets/PSCMAppPools'
      //     identity: managedIdentity.id
      //   }
      // ]
    }
    template: {
      containers: [
        {
          name: '${appName}-ctr'
          image: '${acrServer}/${imageName}:${imageTag}'
          resources: {
            cpu: cpuCores
            memory: '${memoryInGb}Gi'
          }
          // volumeMounts: [
          //   {
          //     volumeName: 'secret-vol'
          //     mountPath: '/app/secrets'
          //   }
          // ]
        }
      ]
      scale: {
        minReplicas: 0
        maxReplicas: 1
        rules: [
          {
            name: 'http-rule'
            http: {
              metadata: {
                concurrentRequests: '100'
              }
            }
          }
        ]
      }
      // volumes: [
      //   {
      //     name: 'secret-vol'
      //     storageType: 'Secret'
      //   }
      // ]
    }
  }
  dependsOn: [logAnalytics, containerAppEnv]
}

