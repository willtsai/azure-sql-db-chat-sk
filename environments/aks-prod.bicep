extension radius

// Pass in these parameters when deploying the environment, e.g.
//   rad deploy ./environments/aks-prod.bicep --parameters subscriptionId=<subscriptionId> --parameters resourceGroupName=<resourceGroupName>
param subscriptionId string
param resourceGroupName string

resource environment 'Applications.Core/environments@2023-10-01-preview' = {
  name: 'aks-prod'
  properties: {
    compute: {
      kind: 'kubernetes'
      namespace: 'aks-prod'
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
            sku: 'P1'
            enableMultiZone: true
            enableDisasterRecovery: true
            enableTransparentDataEncryption: true
          }
        }
      }
      'Radius.Resources/aiModels': {
        default: {
          templateKind: 'bicep'
          templatePath: 'ghcr.io/willtsai/recipes/openai-azure:latest'
          parameters: {
            enable_jailbreak_filter: true
          }
        }
      }
    }
  }
}
