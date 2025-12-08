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
        name: 'STRIPE-OAUTH-ACCESS-TOKEN'
        value: stripeOauthAccessToken
      }
      {
        name: 'AZURE-OPENAI-API-KEY'
        value: foundry.listKeys().key1
      }
    ]
  }
}

// Foundry Account (AIServices variant of CognitiveServices)
resource foundry 'Microsoft.CognitiveServices/accounts@2025-04-01-preview' = {
  name: '${abbrs.foundryAccounts}${abbrs.cognitiveServicesAccounts}${resourceToken}'
  location: location
  tags: tags
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${resourceId('Microsoft.ManagedIdentity/userAssignedIdentities', '${abbrs.managedIdentityUserAssignedIdentities}src-${resourceToken}')}': {}
    }
  }
  sku: {
    name: 'S0'
  }
  kind: 'AIServices'
  properties: {
    // Required to work in Foundry
    allowProjectManagement: true
    
    // Defines developer API endpoint subdomain
    customSubDomainName: '${abbrs.cognitiveServicesAccounts}${resourceToken}'
    
    // Allow key-based authentication
    // Should be disabled in production environments in favor of managed identities
    disableLocalAuth: false
  }
  dependsOn: [
    srcIdentity
  ]
}

// Foundry Project
// Developer APIs are exposed via a project, which groups in- and outputs that relate to one use case
resource foundryProject 'Microsoft.CognitiveServices/accounts/projects@2025-04-01-preview' = {
  name: '${abbrs.foundryProjects}${abbrs.cognitiveServicesAccounts}${resourceToken}'
  parent: foundry
  location: location
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${resourceId('Microsoft.ManagedIdentity/userAssignedIdentities', '${abbrs.managedIdentityUserAssignedIdentities}src-${resourceToken}')}': {}
    }
  }
}

// Model deployment for playground, agents and other tools
resource modelDeployment 'Microsoft.CognitiveServices/accounts/deployments@2024-10-01' = {
  parent: foundry
  name: 'gpt-5-mini'
  sku: {
    capacity: 10
    name: 'GlobalStandard'
  }
  properties: {
    model: {
      name: 'gpt-5-mini'
      format: 'OpenAI'
      version: '2025-08-07'
    }
  }
}

// Role assignments for Foundry Account
resource foundryRoleAssignmentSrc 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(subscription().id, resourceGroup().id, foundry.name, srcIdentity.name, 'Cognitive Services OpenAI User')
  scope: foundry
  properties: {
    principalId: srcIdentity.outputs.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '5e0bd9bd-7b93-4f28-af87-19fc36ad61bd') // Cognitive Services OpenAI User
  }
}

resource foundryRoleAssignmentUser 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(foundry.id, principalId, 'Cognitive Services Contributor')
  scope: foundry
  properties: {
    principalId: principalId
    principalType: principalType
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '25fbc0a9-bd7c-42a3-aa1a-3b75d497ee68') // Cognitive Services Contributor
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
          name: 'AZURE_CLIENT_ID'
          value: srcIdentity.outputs.clientId
        }
        {
          name: 'Azure__KeyVault__VaultUri'
          value: keyVault.outputs.uri
        }
        {
          name: 'Azure__OpenAI__Endpoint'
          value: 'https://${foundry.properties.customSubDomainName}.openai.azure.com/'
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
output AZURE_OPENAI_ENDPOINT string = foundry.properties.endpoint
output AZURE_OPENAI_NAME string = foundry.name
output AZURE_AI_FOUNDRY_NAME string = foundry.name
output AZURE_AI_PROJECT_NAME string = foundryProject.name
