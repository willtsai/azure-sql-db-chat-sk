@description('The context provided by Radius for linking resources')
param context object

extension kubernetes with {
  kubeConfig: ''
  namespace: context.runtime.kubernetes.namespace
} as kubernetes

@description('The name of the SQL Server database to create')
param database string = context.resource.properties.?database ?? context.resource.name

@description('The database username')
param username string = context.resource.properties.?username ?? '${context.application.name}-user'

@description('The SQL Server version to deploy. Supported values: "2017", "2019", "2022", "2025"')
@allowed([
  '2017'
  '2019'
  '2022'
  '2025'
])
param version string = context.resource.properties.?version ?? '2025'

@description('The SQL Server port')
var port = 1433

@description('Unique name for the SQL Server deployment and service.')
var uniqueName = 'sqlserver-${uniqueString(context.resource.id)}'

@description('The SQL Server image to use')
var sqlServerImage = 'mcr.microsoft.com/mssql/server:${version}-latest'

@description('SQL Server user password. Defaults to a unique generated value.')
var password = uniqueString(context.resource.id, 'password')

resource sqlServerDeployment 'apps/Deployment@v1' = {
  metadata: {
    name: uniqueName
    namespace: context.runtime.kubernetes.namespace
    labels: {
      'app.kubernetes.io/name': uniqueName
      'app.kubernetes.io/part-of': context.application.name
      'radapp.io/application': context.application.name
      'radapp.io/resource': context.resource.name
      'radapp.io/resource-type': 'Radius.Data-sqlServerDatabases'
    }
  }
  spec: {
    selector: {
      matchLabels: {
        app: uniqueName
      }
    }
    template: {
      metadata: {
        labels: {
          app: uniqueName
          'app.kubernetes.io/name': uniqueName
          'app.kubernetes.io/part-of': context.application.name
          'radapp.io/application': context.application.name
          'radapp.io/resource': context.resource.name
          'radapp.io/resource-type': 'Radius.Data-sqlServerDatabases'
        }
      }
      spec: {
        containers: [
          {
            name: 'sqlserver'
            image: sqlServerImage
            ports: [
              {
                containerPort: port
                protocol: 'TCP'
              }
            ]
            env: [
              {
                name: 'ACCEPT_EULA'
                value: 'Y'
              }
              {
                name: 'MSSQL_SA_PASSWORD'
                value: password
              }
              {
                name: 'MSSQL_PID'
                value: 'Developer'
              }
            ]
            resources: {
              requests: {
                memory: '2Gi'
                cpu: '1000m'
              }
              limits: {
                memory: '4Gi'
                cpu: '2000m'
              }
            }
          }
        ]
      }
    }
  }
}

resource sqlServerService 'core/Service@v1' = {
  metadata: {
    name: uniqueName
    namespace: context.runtime.kubernetes.namespace
    labels: {
      'app.kubernetes.io/name': uniqueName
      'app.kubernetes.io/part-of': context.application.name
      'radapp.io/application': context.application.name
      'radapp.io/resource': context.resource.name
      'radapp.io/resource-type': 'Radius.Data-sqlServerDatabases'
    }
  }
  spec: {
    type: 'ClusterIP'
    selector: {
      app: uniqueName
    }
    ports: [
      {
        port: port
        targetPort: string(port)
        protocol: 'TCP'
      }
    ]
  }
}

output result object = {
  resources: [
    '/planes/kubernetes/local/namespaces/${sqlServerService.metadata.namespace}/providers/core/Service/${sqlServerService.metadata.name}'
    '/planes/kubernetes/local/namespaces/${sqlServerDeployment.metadata.namespace}/providers/apps/Deployment/${sqlServerDeployment.metadata.name}'
  ]
  values: {
    host: '${sqlServerService.metadata.name}.${sqlServerService.metadata.namespace}.svc.cluster.local'
    port: port
    database: database
    username: username
  }
  secrets: {
    password: password
    connectionString: 'Server=${sqlServerService.metadata.name}.${sqlServerService.metadata.namespace}.svc.cluster.local,${port};Database=${database};User Id=${username};Password=${password};TrustServerCertificate=True;Connection Timeout=30;'
  }
}
