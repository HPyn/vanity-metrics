// Recreates the rg-vanity-metrics resource group contents:
// a timer-triggered PowerShell Function App that writes Lorem Ipsum filler
// into log.md via the GitHub API. See ../README.md for why this exists.

@description('Azure region for all resources.')
param location string = resourceGroup().location

@description('Globally-unique storage account name (lowercase, no dashes).')
param storageAccountName string = 'vanitymetricssa2026'

@description('Function App name.')
param functionAppName string = 'vanity-metrics-filler'

@description('App Service Plan (Consumption) name.')
param appServicePlanName string = 'AustraliaEastPlan'

@description('Application Insights component name.')
param appInsightsName string = 'vanity-metrics-filler'

@secure()
@description('GitHub PAT the function uses to commit filler text. Pass via a GitHub Actions secret, never hardcode.')
param githubToken string

@description('GitHub repo owner the function commits to.')
param githubOwner string = 'HPyn'

@description('GitHub repo name the function commits to.')
param githubRepo string = 'vanity-metrics'

@description('File the function appends filler text to.')
param githubPath string = 'log.md'

@description('Earliest local hour (0-23) the function is allowed to commit.')
param workStartHour int = 9

@description('Latest local hour (0-23) the function is allowed to commit.')
param workEndHour int = 17

@description('Probability (0-1) that a given timer tick produces a commit.')
param commitProbability string = '0.4'

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageAccountName
  location: location
  kind: 'StorageV2'
  sku: {
    name: 'Standard_LRS'
  }
  properties: {
    accessTier: 'Hot'
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    supportsHttpsTrafficOnly: true
  }
}

resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: appInsightsName
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
    IngestionMode: 'ApplicationInsights'
  }
}

resource hostingPlan 'Microsoft.Web/serverfarms@2023-01-01' = {
  name: appServicePlanName
  location: location
  kind: 'functionapp'
  sku: {
    name: 'Y1'
    tier: 'Dynamic'
  }
  properties: {}
}

resource functionApp 'Microsoft.Web/sites@2023-01-01' = {
  name: functionAppName
  location: location
  kind: 'functionapp'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: hostingPlan.id
    httpsOnly: true
    siteConfig: {
      powerShellVersion: '7.4'
      minTlsVersion: '1.2'
      ftpsState: 'FtpsOnly'
      use32BitWorkerProcess: true
      appSettings: [
        {
          name: 'AzureWebJobsStorage'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};AccountKey=${storageAccount.listKeys().keys[0].value};EndpointSuffix=core.windows.net'
        }
        {
          name: 'WEBSITE_CONTENTAZUREFILECONNECTIONSTRING'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};AccountKey=${storageAccount.listKeys().keys[0].value};EndpointSuffix=core.windows.net'
        }
        {
          name: 'WEBSITE_CONTENTSHARE'
          value: toLower(functionAppName)
        }
        {
          name: 'FUNCTIONS_EXTENSION_VERSION'
          value: '~4'
        }
        {
          name: 'FUNCTIONS_WORKER_RUNTIME'
          value: 'powershell'
        }
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: appInsights.properties.ConnectionString
        }
        {
          name: 'GITHUB_TOKEN'
          value: githubToken
        }
        {
          name: 'GITHUB_OWNER'
          value: githubOwner
        }
        {
          name: 'GITHUB_REPO'
          value: githubRepo
        }
        {
          name: 'GITHUB_PATH'
          value: githubPath
        }
        {
          name: 'WORK_START_HOUR'
          value: string(workStartHour)
        }
        {
          name: 'WORK_END_HOUR'
          value: string(workEndHour)
        }
        {
          name: 'COMMIT_PROBABILITY'
          value: commitProbability
        }
      ]
    }
  }
}

// Note: the "Failure Anomalies" smart detector alert rule that shows up
// next to Application Insights in the portal is auto-provisioned by Azure
// Monitor whenever a Insights component is created. It isn't defined here
// deliberately — Azure recreates it on its own.

output functionAppName string = functionApp.name
output functionAppDefaultHostName string = functionApp.properties.defaultHostName
