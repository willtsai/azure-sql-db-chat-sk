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

@description('SQL Server user password. Defaults to a unique generated value that satisfies SQL password complexity requirements.')
@secure()
param password string = ''

var configuredPassword = context.resource.properties.?password ?? ''
var defaultPassword = '${take(uniqueString(context.resource.id, 'password'), 8)}Aa1!'
var providedPassword = empty(password) ? configuredPassword : password
var adminPassword = empty(providedPassword) ? defaultPassword : providedPassword

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
                value: adminPassword
              }
              {
                name: 'MSSQL_PID'
                value: 'Developer'
              }
              {
                name: 'MSSQL_ENABLE_POLYBASE'
                value: '0'
              }
              {
                name: 'MSSQL_MEMORY_LIMIT_MB'
                value: '3072'
              }
            ]
            securityContext: {
              capabilities: {
                add: ['SYS_PTRACE']
              }
            }
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
    password: adminPassword
    connectionString: 'Server=${sqlServerService.metadata.name}.${sqlServerService.metadata.namespace}.svc.cluster.local,${port};Database=${database};User Id=${username};Password=${adminPassword};TrustServerCertificate=True;Connection Timeout=30;'
  }
}
