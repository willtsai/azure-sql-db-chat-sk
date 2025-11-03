@description('Radius-provided object containing information about the resouce calling the Recipe')
param context object

@description('The geo-location where the resource lives.')
param location string = resourceGroup().location

@description('SQL administrator username')
param adminLogin string = 'sqladmin'

@description('SQL administrator password')
@secure()
param adminPassword string = newGuid()

@description('Name of the SQL database. Defaults to the name of the Radius SQL resource.')
param database string = context.resource.name

@description('SKU name for the SQL database (for example: Basic, S0, S1, P1, GP_Gen5_2)')
param sku string = 'Basic'

@description('Whether to enable geo-backups to support disaster recovery scenarios')
param enableDisasterRecovery bool = false

@description('Whether to enable transparent data encryption (TDE) for the database')
param enableTransparentDataEncryption bool = true

@description('The user-defined tags that will be applied to the resource. Default is null')
param tags object = {}

@description('The Radius specific tags that will be applied to the resource')
var radiusTags = {
  'radapp.io-environment': context.environment.id
  'radapp.io-application': context.application == null ? '' : context.application.id
  'radapp.io-resource': context.resource.id
}

var computedSkuTier = sku == 'Basic'
  ? 'Basic'
  : sku == 'S0' || sku == 'S1' || sku == 'S2' || sku == 'S3'
    ? 'Standard'
    : sku == 'P1' || sku == 'P2' || sku == 'P3'
      ? 'Premium'
      : startsWith(toLower(sku), 'gp_')
        ? 'GeneralPurpose'
        : startsWith(toLower(sku), 'bc_')
          ? 'BusinessCritical'
          : startsWith(toLower(sku), 'hs_')
            ? 'Hyperscale'
            : 'Standard'

var mssqlPort = 1433

resource mssql 'Microsoft.Sql/servers@2021-02-01-preview' = {
  name: '${context.resource.name}-${uniqueString(context.resource.id, resourceGroup().id)}'
  location: location
  tags: union(tags, radiusTags)
  properties: {
    administratorLogin: adminLogin
    administratorLoginPassword: adminPassword
  }

  resource firewallAllowEverything 'firewallRules' = {
    name: 'firewall-allow-everything'
    properties: {
      startIpAddress: '0.0.0.0'
      endIpAddress: '255.255.255.255'
    }
  }
}

resource db 'Microsoft.Sql/servers/databases@2021-02-01-preview' = {
  name: database
  parent: mssql
  location: location
  tags: union(tags, radiusTags)
  sku: {
    name: sku
    tier: computedSkuTier
  }
  properties: {
    requestedBackupStorageRedundancy: enableDisasterRecovery ? 'Geo' : 'Local'
  }
}

resource transparentDataEncryption 'Microsoft.Sql/servers/databases/transparentDataEncryption@2021-02-01-preview' = {
  name: 'current'
  parent: db
  properties: {
    state: enableTransparentDataEncryption ? 'Enabled' : 'Disabled'
  }
}

output result object = {
  values: {
    server: mssql.properties.fullyQualifiedDomainName
    port: mssqlPort
    database: database
    username: adminLogin
  }
  secrets: {
    #disable-next-line outputs-should-not-contain-secrets
    password: adminPassword
    #disable-next-line outputs-should-not-contain-secrets
    connectionString: 'Server=tcp:${mssql.properties.fullyQualifiedDomainName},${mssqlPort};Initial Catalog=${database};User Id=${adminLogin};Password=${adminPassword};Encrypt=false'
  }
}
