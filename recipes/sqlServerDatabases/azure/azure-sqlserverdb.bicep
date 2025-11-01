@description('The context provided by Radius for linking resources')
param context object

@description('The Azure region where resources will be deployed')
param location string = resourceGroup().location

@description('The name of the SQL Server database to create')
param database string = context.resource.properties.?database ?? context.resource.name

@description('The database username')
param username string = context.resource.properties.?username ?? '${context.application.name}-user'

@description('The SQL Server version. For Azure SQL Database, this is always the latest version')
param version string = '12.0'

@description('Custom tags to apply to resources')
param tags object = {}

@description('The SKU name for the Azure SQL Database provided via Radius Recipe Parameters.')
@allowed([
  'Basic'
  'S0'
  'S1'
  'S2'
  'S3'
  'P1'
  'P2'
  'P4'
  'GP_Gen5_2'
  'GP_Gen5_4'
  'GP_Gen5_8'
])
param sku string

@description('Enable disaster recovery for the SQL Database by creating a geo-replicated secondary database in a paired region.')
param enableDisasterRecovery bool

@description('Enable Transparent Data Encryption (TDE) for the SQL Database to encrypt data at rest.')
param enableTransparentDataEncryption bool

// Generate unique identifiers for this database instance
var uniqueName = 'sqlserver-${uniqueString(context.resource.id, resourceGroup().id)}'
var sqlServerName = toLower(uniqueName)
var password = '${toUpper(uniqueString(context.resource.id, 'password', sqlServerName))}${uniqueString(context.resource.id, 'salt')}!Aa1'
var port = 1433

// Disaster recovery configuration
var pairedRegions = {
  eastus: 'westus'
  eastus2: 'centralus'
  westus: 'eastus'
  westus2: 'westcentralus'
  westus3: 'eastus'
  centralus: 'eastus2'
  northcentralus: 'southcentralus'
  southcentralus: 'northcentralus'
  westcentralus: 'westus2'
  northeurope: 'westeurope'
  westeurope: 'northeurope'
  uksouth: 'ukwest'
  ukwest: 'uksouth'
  eastasia: 'southeastasia'
  southeastasia: 'eastasia'
  japaneast: 'japanwest'
  japanwest: 'japaneast'
  australiaeast: 'australiasoutheast'
  australiasoutheast: 'australiaeast'
  canadacentral: 'canadaeast'
  canadaeast: 'canadacentral'
  brazilsouth: 'southcentralus'
  southindia: 'centralindia'
  centralindia: 'southindia'
  westindia: 'southindia'
}

var secondaryLocation = enableDisasterRecovery ? pairedRegions[location] : location
var secondaryServerName = '${sqlServerName}-dr'
var failoverGroupName = '${uniqueName}-fog'

// Check if SKU supports geo-replication (Basic tier does not)
var supportsGeoReplication = sku != 'Basic'
var drEnabled = enableDisasterRecovery && supportsGeoReplication

// Merge Radius tags with user-provided tags
var radiusTags = {
  'radapp.io-environment': context.environment.name
  'radapp.io-application': context.application.name
  'radapp.io-resource': context.resource.name
  'radapp.io-resource-type': 'Radius.Data-sqlServerDatabases'
}
var allTags = union(tags, radiusTags)

resource sqlServer 'Microsoft.Sql/servers@2023-08-01-preview' = {
  name: sqlServerName
  location: location
  tags: allTags
  properties: {
    administratorLogin: username
    administratorLoginPassword: password
    version: version
    publicNetworkAccess: 'Enabled'
  }
}

resource sqlDatabase 'Microsoft.Sql/servers/databases@2023-08-01-preview' = {
  parent: sqlServer
  name: database
  location: location
  tags: allTags
  sku: {
    name: sku
    tier: startsWith(sku, 'GP_') ? 'GeneralPurpose' : startsWith(sku, 'P') ? 'Premium' : startsWith(sku, 'S') ? 'Standard' : 'Basic'
  }
  properties: {
    collation: 'SQL_Latin1_General_CP1_CI_AS'
    maxSizeBytes: sku == 'Basic' ? 2147483648 : 268435456000 // 2GB for Basic, 250GB for others
    catalogCollation: 'SQL_Latin1_General_CP1_CI_AS'
    zoneRedundant: false
  }
}

// Transparent Data Encryption (TDE) for the primary database
resource transparentDataEncryption 'Microsoft.Sql/servers/databases/transparentDataEncryption@2023-08-01-preview' = if (enableTransparentDataEncryption) {
  parent: sqlDatabase
  name: 'current'
  properties: {
    state: 'Enabled'
  }
}

resource firewallRuleAllowAzureServices 'Microsoft.Sql/servers/firewallRules@2023-08-01-preview' = {
  parent: sqlServer
  name: 'AllowAllWindowsAzureIps'
  properties: {
    startIpAddress: '0.0.0.0'
    endIpAddress: '0.0.0.0'
  }
}

// Secondary SQL Server for disaster recovery (only created if DR is enabled and SKU supports it)
resource secondarySqlServer 'Microsoft.Sql/servers@2023-08-01-preview' = if (drEnabled) {
  name: secondaryServerName
  location: secondaryLocation
  tags: union(allTags, { 'radapp.io-replica': 'secondary' })
  properties: {
    administratorLogin: username
    administratorLoginPassword: password
    version: '12.0'
    publicNetworkAccess: 'Enabled'
  }
}

resource secondaryFirewallRule 'Microsoft.Sql/servers/firewallRules@2023-08-01-preview' = if (drEnabled) {
  parent: secondarySqlServer
  name: 'AllowAllWindowsAzureIps'
  properties: {
    startIpAddress: '0.0.0.0'
    endIpAddress: '0.0.0.0'
  }
}

// Failover group for automatic geo-replication and failover
resource failoverGroup 'Microsoft.Sql/servers/failoverGroups@2023-08-01-preview' = if (drEnabled) {
  parent: sqlServer
  name: failoverGroupName
  properties: {
    readWriteEndpoint: {
      failoverPolicy: 'Automatic'
      failoverWithDataLossGracePeriodMinutes: 60
    }
    readOnlyEndpoint: {
      failoverPolicy: 'Disabled'
    }
    partnerServers: [
      {
        id: secondarySqlServer.id
      }
    ]
    databases: [
      sqlDatabase.id
    ]
  }
}

output result object = {
  resources: concat(
    concat([
      sqlServer.id
      sqlDatabase.id
      firewallRuleAllowAzureServices.id
    ], enableTransparentDataEncryption ? [
      transparentDataEncryption.id
    ] : []),
    drEnabled ? [
      secondarySqlServer.id
      secondaryFirewallRule.id
      failoverGroup.id
    ] : []
  )
  values: {
    // When DR is enabled, use the failover group listener endpoint for automatic failover
    host: drEnabled ? '${failoverGroupName}.${environment().suffixes.sqlServerHostname}' : sqlServer.properties.fullyQualifiedDomainName
    port: port
    database: database
    username: username
    disasterRecoveryEnabled: drEnabled
    primaryRegion: location
    secondaryRegion: drEnabled ? secondaryLocation : null
    failoverGroupName: drEnabled ? failoverGroupName : null
    transparentDataEncryptionEnabled: enableTransparentDataEncryption
  }
  secrets: {
    password: password
    // Connection string uses failover group listener when DR is enabled
    connectionString: drEnabled
      ? 'Server=${failoverGroupName}.${environment().suffixes.sqlServerHostname},${port};Database=${database};User Id=${username};Password=${password};Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;'
      : 'Server=${sqlServer.properties.fullyQualifiedDomainName},${port};Database=${database};User Id=${username};Password=${password};Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;'
  }
}
