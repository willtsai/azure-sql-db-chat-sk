extension radius

// Pass in these parameters when deploying the environment, e.g.
//   rad deploy ./environments/aks-dev.bicep --parameters subscriptionId=<subscriptionId> --parameters resourceGroupName=<resourceGroupName>
param subscriptionId string
param resourceGroupName string

resource environment 'Applications.Core/environments@2023-10-01-preview' = {
  name: 'aks-dev'
  properties: {
    compute: {
      kind: 'kubernetes'
      namespace: 'aks-dev'
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
