@description('The name of the key vault')
param vaultName string
@description('the ID of the role definition. Defaults to the "Key Vault Secrets User" role ID')
param vaultRoleId string = '4633458b-17de-408a-b874-0445c86b69e6'
@description('The ID of the user principal')
param principalId string

var vaultRoleRID = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', vaultRoleId)

resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' existing = {
  name: vaultName
}

resource kvRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(principalId, vaultRoleRID)
  scope: keyVault
  properties: {
    principalId: principalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', vaultRoleId)
    principalType: 'ServicePrincipal'
  }
  
}

@description('The ResourceID of the new roleDefinition')
output roleDefinitionRID string = kvRole.id
