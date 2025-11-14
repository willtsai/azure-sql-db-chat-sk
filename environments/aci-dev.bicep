extension radius

// Pass in these parameters when deploying the environment, e.g.
//   rad deploy ./environments/aci-dev.bicep --parameters subscriptionId=<subscriptionId> --parameters resourceGroupName=<resourceGroupName> --parameters userAssignedIdentityId=<userAssignedIdentityId>
param subscriptionId string
param resourceGroupName string
param userAssignedIdentityId string

resource environment 'Applications.Core/environments@2023-10-01-preview' = {
  name: 'aci-dev'
  properties: {
    compute: {
      kind: 'aci'
      resourceGroup: '/subscriptions/${subscriptionId}/resourceGroups/${resourceGroupName}'
      identity: {
        kind:'userAssigned'
        managedIdentity: ['/subscriptions/${subscriptionId}/resourceGroups/${resourceGroupName}/providers/Microsoft.ManagedIdentity/userAssignedIdentities/${userAssignedIdentityId}']
      }
    }
    providers: {
      azure: {
        scope: '/subscriptions/${subscriptionId}/resourceGroups/${resourceGroupName}'
      }
    }
    recipes: {
      'Radius.Resources/sqlServerDatabases': {
        default: {
          templateKind: 'bicep'
          templatePath: 'ghcr.io/willtsai/recipes/sqlserverdb-azure:latest'
          parameters: {
            sku: 'Basic'
            enableDisasterRecovery: false
            enableMultiZone: false
            enableTransparentDataEncryption: true
          }
        }
      }
      'Radius.Resources/aiModels': {
        default: {
          templateKind: 'bicep'
          templatePath: 'ghcr.io/willtsai/recipes/openai-azure:latest'
          parameters: {
            enable_jailbreak_filter: false
          }
        }
      }
    }
  }
}
