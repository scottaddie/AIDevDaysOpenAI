targetScope = 'subscription'

@minLength(1)
@maxLength(64)
@description('Name of the environment that can be used in resource tags')
param environmentName string

@minLength(1)
@description('Primary location for all resources')
param location string

@description('Id of the user or app to assign application roles')
param principalId string

@description('Principal type of user or app')
param principalType string

@description('OpenAI API key to access OpenAI services')
param openAiApiKey string

@description('Azure OpenAI API key to access Azure OpenAI services')
param azureOpenAiApiKey string

@description('Stripe OAuth access token for payment processing')
param stripeOauthAccessToken string

// Tags that should be applied to all resources.
// 
// Note that 'azd-service-name' tags should be applied separately to service host resources.
// Example usage:
//   tags: union(tags, { 'azd-service-name': <service name in azure.yaml> })
var tags = {
  'azd-env-name': environmentName
}

// Organize resources in a resource group
resource rg 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: 'rg-aidevdaysopenai'
  location: location
  tags: tags
}

module resources 'resources.bicep' = {
  scope: rg
  name: 'resources'
  params: {
    location: location
    tags: tags
    principalId: principalId
    principalType: principalType
    openAiApiKey: openAiApiKey
    azureOpenAiApiKey: azureOpenAiApiKey
    stripeOauthAccessToken: stripeOauthAccessToken
  }
}

output AZURE_RESOURCE_SRC_ID string = resources.outputs.AZURE_RESOURCE_SRC_ID
