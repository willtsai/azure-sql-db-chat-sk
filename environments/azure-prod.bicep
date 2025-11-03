extension radius

param subscriptionId string = '66d1209e-1382-45d3-99bb-650e6bf63fc0'
param resourceGroupName string = 'ignite2025-azure-prod'

resource environment 'Applications.Core/environments@2023-10-01-preview' = {
  name: 'azure-prod'
  properties: {
    compute: {
      kind: 'kubernetes'   // Required. The kind of container runtime to use
      namespace: 'azure-prod' // Required. The Kubernetes namespace in which to render application resources
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
            sku: 'S1'
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
