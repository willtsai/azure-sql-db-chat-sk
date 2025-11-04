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

@description('Whether to enable zone-backups to support disaster recovery scenarios')
param enableDisasterRecovery bool = false

@description('Whether to enable transparent data encryption (TDE) for the database')
param enableTransparentDataEncryption bool = true

@description('Enable zone redundancy (multi-zone) for the database if supported by the selected SKU tier. Premium (DTU) and BusinessCritical (vCore) tiers support zone redundancy; others will ignore this flag.')
param enableMultiZone bool = false

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
    : sku == 'P1' || sku == 'P2' || sku == 'P3' || sku == 'P4' || sku == 'P6' || sku == 'P11'
      ? 'Premium'
      : startsWith(toLower(sku), 'gp_')
        ? 'GeneralPurpose'
        : startsWith(toLower(sku), 'bc_')
          ? 'BusinessCritical'
          : startsWith(toLower(sku), 'hs_')
            ? 'Hyperscale'
            : 'Standard'

var mssqlPort = 1433

// Zone redundancy support (currently only Premium DTU or BusinessCritical vCore tiers). Hyperscale & GeneralPurpose ignored for this property.
var multiZoneSupported = (computedSkuTier == 'Premium' || computedSkuTier == 'BusinessCritical')

// Effective enablement (must be requested AND supported)
var multiZoneEnabled = enableMultiZone && multiZoneSupported

// Reason string for clarity in outputs when not supported
var multiZoneReason = multiZoneSupported ? '' : 'Zone redundancy only supported for Premium or BusinessCritical tiers; current tier: ${computedSkuTier}'

// Build properties object conditionally to avoid sending zoneRedundant for unsupported tiers (which triggers ProvisioningDisabled)
var dbProperties = multiZoneEnabled ? {
  requestedBackupStorageRedundancy: 'Zone'
  zoneRedundant: true
} : {
  requestedBackupStorageRedundancy: enableDisasterRecovery ? 'Zone' : 'Local'
}

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
  properties: dbProperties
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
    multiZoneEnabled: multiZoneEnabled
    multiZoneRequested: enableMultiZone
    multiZoneEffective: multiZoneEnabled
    multiZoneSupported: multiZoneSupported
    multiZoneReason: multiZoneReason
  }
  secrets: {
    #disable-next-line outputs-should-not-contain-secrets
    password: adminPassword
    #disable-next-line outputs-should-not-contain-secrets
    connectionString: 'Server=tcp:${mssql.properties.fullyQualifiedDomainName},${mssqlPort};Initial Catalog=${database};User Id=${adminLogin};Password=${adminPassword};Encrypt=false'
  }
}
