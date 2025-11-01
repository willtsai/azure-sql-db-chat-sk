extension radius

resource environment 'Applications.Core/environments@2023-10-01-preview' = {
  name: 'azure-dev'
  properties: {
    compute: {
      kind: 'kubernetes'   // Required. The kind of container runtime to use
      namespace: 'azure-dev' // Required. The Kubernetes namespace in which to render application resources
    }
    recipes: {
      'Radius.Resources/sqlServerDatabases': {
        default: {
          templateKind: 'bicep'
          templatePath: 'ghcr.io/willtsai/recipes/sqlserverdb-azure:latest'
          parameters: {
            sku: 'Basic'
            enableDisasterRecovery: false
            enableTransparentDataEncryption: true
          }
        }
      }
      'Radius.Resources/aiModels': {
        default: {
          templateKind: 'terraform'
          templatePath: 'git::https://github.com/willtsai/radius-recipes.git//recipes/aiModels/azure-openai'
          parameters: {
            enable_pii_filter: true
          }
        }
      }
    }
    providers: {
      azure: {
        scope: '/subscriptions/66d1209e-1382-45d3-99bb-650e6bf63fc0/resourceGroups/ignite2025-azure-dev' // TODO
      }
    }
  }
}
