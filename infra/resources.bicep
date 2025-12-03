@description('The location used for all deployed resources')
param location string = resourceGroup().location

@description('Tags that will be applied to all resources')
param tags object = {}

@description('ID of the user or app to assign application roles')
param principalId string

@description('Principal type of user or app')
param principalType string

var abbrs = loadJsonContent('./abbreviations.json')
var resourceToken = uniqueString(subscription().id, resourceGroup().id, location)

// Monitor application with Azure Monitor
module monitoring 'br/public:avm/ptn/azd/monitoring:0.1.0' = {
  name: 'monitoring'
  params: {
    logAnalyticsName: '${abbrs.operationalInsightsWorkspaces}${resourceToken}'
    applicationInsightsName: '${abbrs.insightsComponents}${resourceToken}'
    applicationInsightsDashboardName: '${abbrs.portalDashboards}${resourceToken}'
    location: location
    tags: tags
  }
}

// App Service Plan
module appServicePlan 'br/public:avm/res/web/serverfarm:0.2.2' = {
  name: 'appserviceplan'
  params: {
    name: '${abbrs.webServerFarms}${resourceToken}'
    location: location
    tags: tags
    skuName: 'B1'
    skuCapacity: 1
    kind: 'Windows'
    reserved: false
  }
}

module srcIdentity 'br/public:avm/res/managed-identity/user-assigned-identity:0.2.1' = {
  name: 'srcidentity'
  params: {
    name: '${abbrs.managedIdentityUserAssignedIdentities}src-${resourceToken}'
    location: location
  }
}

// Key Vault
@secure()
param openAiApiKey string

@secure()
param azureOpenAiApiKey string

@secure()
param stripeOauthAccessToken string

module keyVault 'br/public:avm/res/key-vault/vault:0.13.3' = {
  name: 'keyvault'
  params: {
    name: '${abbrs.keyVaultVaults}${resourceToken}'
    location: location
    tags: tags
    sku: 'standard'
    enableRbacAuthorization: true
    roleAssignments: [
      {
        principalId: srcIdentity.outputs.principalId
        principalType: 'ServicePrincipal'
        roleDefinitionIdOrName: 'Key Vault Secrets User'
      }
      {
        principalId: principalId
        principalType: principalType
        roleDefinitionIdOrName: 'Key Vault Administrator'
      }
    ]
    secrets: [
      {
        name: 'OPENAI-API-KEY'
        value: openAiApiKey
      }
      {
        name: 'AZURE-OPENAI-API-KEY'
        value: azureOpenAiApiKey
      }
      {
        name: 'STRIPE-OAUTH-ACCESS-TOKEN'
        value: stripeOauthAccessToken
      }
    ]
  }
}

// Azure OpenAI
module openAI 'br/public:avm/res/cognitive-services/account:0.14.0' = {
  name: 'openai'
  params: {
    name: '${abbrs.cognitiveServicesAccounts}${resourceToken}'
    location: location
    tags: tags
    kind: 'OpenAI'
    customSubDomainName: '${abbrs.cognitiveServicesAccounts}${resourceToken}'
    networkAcls: {
      defaultAction: 'Allow'
      bypass: 'AzureServices'
    }
    // Allow key-based authentication
    // Should be disabled in production environments in favor of managed identities
    disableLocalAuth: false
    roleAssignments: [
      {
        principalId: srcIdentity.outputs.principalId
        principalType: 'ServicePrincipal'
        roleDefinitionIdOrName: 'Cognitive Services OpenAI User'
      }
      {
        principalId: principalId
        principalType: principalType
        roleDefinitionIdOrName: 'Cognitive Services Contributor'
      }
    ]
    deployments: [
      {
        name: 'gpt-5-mini'
        sku: {
          name: 'GlobalStandard'
          capacity: 10
        }
        model: {
          format: 'OpenAI'
          name: 'gpt-5-mini'
          version: '2025-08-07'
        }
      }
    ]    
  }
}

// App Service
module src 'br/public:avm/res/web/site:0.19.4' = {
  name: 'src'
  params: {
    name: '${abbrs.webSitesAppService}${resourceToken}'
    location: location
    tags: union(tags, { 'azd-service-name': 'src' })
    kind: 'app'
    serverFarmResourceId: appServicePlan.outputs.resourceId
    managedIdentities: {
      systemAssigned: false
      userAssignedResourceIds: [srcIdentity.outputs.resourceId]
    }
    siteConfig: {
      netFrameworkVersion: 'v10.0'
      alwaysOn: true
      ftpsState: 'Disabled'
      minTlsVersion: '1.2'
      use32BitWorkerProcess: false
      http20Enabled: true
      metadata: [
        {
          name: 'CURRENT_STACK'
          value: 'dotnet'
        }
      ]
      appSettings: [
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: monitoring.outputs.applicationInsightsConnectionString
        }
        {
          name: 'AZURE_CLIENT_ID'
          value: srcIdentity.outputs.clientId
        }
        {
          name: 'Azure__KeyVault__VaultUri'
          value: keyVault.outputs.uri
        }
        {
          name: 'Azure__OpenAI__Endpoint'
          value: openAI.outputs.endpoint
        }
        {
          name: 'AZURE_TOKEN_CREDENTIALS'
          value: 'ManagedIdentityCredential'
        }
      ]
    }
  }
}

output AZURE_RESOURCE_SRC_ID string = src.outputs.resourceId
output AZURE_KEY_VAULT_ENDPOINT string = keyVault.outputs.uri
output AZURE_KEY_VAULT_NAME string = keyVault.outputs.name
output AZURE_OPENAI_ENDPOINT string = openAI.outputs.endpoint
output AZURE_OPENAI_NAME string = openAI.outputs.name
