@description('The context provided by Radius for linking resources')
param context object

@description('The Azure region where resources will be deployed')
param location string = resourceGroup().location

@description('SKU name for the Cognitive Account (S0, S1, etc.)')
param sku_name string = 'S0'

@description('Deployment capacity (tokens per minute in thousands)')
param capacity int = 10

@description('Azure OpenAI API version')
param api_version string = '2024-02-15-preview'

@description('Enable or disable public network access')
@allowed(['Enabled', 'Disabled'])
param public_network_access string = 'Enabled'

@description('Custom tags to apply to resources')
param tags object = {}

@description('Enable jailbreak content filtering for chat/completions output')
param enable_jailbreak_filter bool

@description('Optional RAI policy name to use when jailbreak filtering is enabled. Leave blank to let this template create a policy automatically.')
param jailbreak_policy_name string = ''


// Generate identifiers
var deploymentName = context.resource.name
var sanitizedDeploymentName = toLower(replace(replace(replace(deploymentName, '-', ''), '_', ''), '.', ''))
var baseAccountName = empty(sanitizedDeploymentName) ? 'oa' : 'oa${sanitizedDeploymentName}'
var uniqueSuffix = uniqueString(resourceGroup().id, context.resource.id)
var maxCognitiveAccountNameLength = 63
var uniqueSuffixLength = length(uniqueSuffix)
var maxBaseAccountNameLength = maxCognitiveAccountNameLength - uniqueSuffixLength
var trimmedBaseAccountName = substring(baseAccountName, 0, min(length(baseAccountName), maxBaseAccountNameLength))
var cognitiveAccountName = '${trimmedBaseAccountName}${uniqueSuffix}'
var model = context.resource.properties.model

// Map model names to Azure OpenAI deployment configurations
var modelConfig = {
  'gpt-4': {
    format: 'OpenAI'
    name: 'gpt-4'
    version: 'turbo-2024-04-09'
  }
  'gpt-35-turbo': {
    format: 'OpenAI'
    name: 'gpt-35-turbo'
    version: '0125'
  }
  'text-embedding-3-small': {
    format: 'OpenAI'
    name: 'text-embedding-3-small'
    version: '1'
  }
  'text-embedding-ada-002': {
    format: 'OpenAI'
    name: 'text-embedding-ada-002'
    version: '2'
  }
  'gpt-4o': {
    format: 'OpenAI'
    name: 'gpt-4o'
    version: '2024-05-13'
  }
}

// Select the model configuration
var selectedModel = modelConfig[model] ?? {
  format: 'OpenAI'
  name: model
  version: '1'
}

// Built-in jailbreak filtering applies only to chat/completions models
var raiSupportedModels = [
  'gpt-4'
  'gpt-35-turbo'
  'gpt-4o'
]
var useJailbreakPolicy = enable_jailbreak_filter && contains(raiSupportedModels, selectedModel.name)

// Determine SKU name overrides for specific models (e.g., embeddings require GlobalStandard)
var deploymentSkuName = selectedModel.name == 'text-embedding-3-small'
  ? 'GlobalStandard'
  : selectedModel.name == 'text-embedding-3-large'
    ? 'GlobalStandard'
    : 'Standard'

// Resolve the RAI policy name when jailbreak filtering is enabled
var trimmedJailbreakPolicyName = trim(jailbreak_policy_name)
var shouldCreateJailbreakPolicy = useJailbreakPolicy && empty(trimmedJailbreakPolicyName)
var computedJailbreakPolicyName = shouldCreateJailbreakPolicy ? '${deploymentName}-jailbreak-filter' : trimmedJailbreakPolicyName
var resolvedRaiPolicyName = useJailbreakPolicy
  ? (empty(computedJailbreakPolicyName) ? 'Microsoft.Default' : computedJailbreakPolicyName)
  : 'Microsoft.Default'

// Merge Radius tags with user-provided tags
var radiusTags = {
  'radapp.io-environment': context.environment.name
  'radapp.io-application': context.application.name
  'radapp.io-resource': context.resource.name
  'radapp.io-resource-type': 'Radius.Resources-aiModels'
}
var allTags = union(tags, radiusTags)

// Cognitive Account - provisioned per model deployment to isolate capacity and settings
// Bicep uses declarative deployment mode, so existing resources are updated, not recreated
resource cognitiveAccount 'Microsoft.CognitiveServices/accounts@2024-10-01' = {
  name: cognitiveAccountName
  location: location
  kind: 'OpenAI'
  sku: {
    name: sku_name
  }
  properties: {
    publicNetworkAccess: public_network_access
  }
  tags: allTags
}

// Optional jailbreak RAI policy (created when filtering is enabled and no existing policy name is provided)
resource jailbreakPolicy 'Microsoft.CognitiveServices/accounts/raiPolicies@2024-10-01' = if (shouldCreateJailbreakPolicy) {
  parent: cognitiveAccount
  name: computedJailbreakPolicyName
  properties: {
    basePolicyName: 'Microsoft.Default'
    mode: 'Asynchronous_filter'
    contentFilters: [
      {
        name: 'Jailbreak'
        blocking: true
        enabled: true
        severityThreshold: 'Low'
        source: 'Prompt'
      }
    ]
  }
}

// Model deployment
resource modelDeployment 'Microsoft.CognitiveServices/accounts/deployments@2024-10-01' = {
  parent: cognitiveAccount
  name: deploymentName
  dependsOn: shouldCreateJailbreakPolicy ? [jailbreakPolicy] : []
  sku: {
    name: deploymentSkuName
    capacity: capacity
  }
  properties: {
    model: {
      format: selectedModel.format
      name: selectedModel.name
      version: selectedModel.version
    }
    raiPolicyName: resolvedRaiPolicyName
    versionUpgradeOption: 'OnceNewDefaultVersionAvailable'
  }
}

@secure()
output result object = {
  resources: concat(
    [
      cognitiveAccount.id
      modelDeployment.id
    ],
    shouldCreateJailbreakPolicy ? [jailbreakPolicy.id] : []
  )
  values: {
    apiVersion: api_version
    endpoint: cognitiveAccount.properties.endpoint
    model: model
    deployment: deploymentName
    location: location
    capacity: capacity
    skuName: sku_name
    publicNetworkAccess: public_network_access
    jailbreakFilterEnabled: useJailbreakPolicy
    jailbreakPolicyNameApplied: resolvedRaiPolicyName
    deploymentSkuName: deploymentSkuName
  }
  secrets: {
    apiKey: cognitiveAccount.listKeys().key1
  }
}
