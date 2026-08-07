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

@description('Globally-unique Key Vault name (3-24 chars, alphanumeric/hyphens).')
param keyVaultName string = 'vanity-metrics-kv2026'

@allowed(['7.2', '7.4', '7.6'])
@description('PowerShell worker runtime version. 7.4 reaches EOL 2026-11-10.')
param powerShellVersion string = '7.6'

@secure()
@description('GitHub PAT the function uses to commit filler text. Pass via a GitHub Actions secret, never hardcode.')
param githubToken string

@description('GitHub repo owner the function commits to.')
param githubOwner string = 'HPyn'

@description('GitHub repo name the function commits to.')
param githubRepo string = 'vanity-metrics'

@description('File the function appends filler text to.')
param githubPath string = 'log.md'

@minValue(0)
@maxValue(23)
@description('Earliest local hour (0-23) the function is allowed to commit.')
param workStartHour int = 9

@minValue(0)
@maxValue(23)
@description('Latest local hour (0-23) the function is allowed to commit.')
param workEndHour int = 17

@description('Daily ingestion cap (GB) on Application Insights - a hard stop, not just an alert, in case logging ever runs away.')
param appInsightsDailyCapGb string = '0.1'

@description('Probability (0-1) that a given timer tick produces a commit, before the busy/quiet week multiplier is applied.')
param commitProbability string = '0.4'

@description('GitHub branch the function commits filler text to.')
param githubBranch string = 'main'

@description('ISO week-of-year modulo used to decide which weeks look busier or quieter than average.')
param busyWeekModulo int = 4

@description('Weeks where (ISO week number mod busyWeekModulo) equals this get the busy multiplier.')
param busyWeekRemainder int = 0

@description('Commit-probability multiplier applied on busy weeks.')
param busyWeekMultiplier string = '2.5'

@description('Weeks where (ISO week number mod busyWeekModulo) equals this get the quiet multiplier.')
param quietWeekRemainder int = 2

@description('Commit-probability multiplier applied on quiet weeks.')
param quietWeekMultiplier string = '0.4'

@description('Monthly cost budget for this resource group, in the subscription\'s billing currency (AUD here). Everything deployed is free-tier, so this exists purely as a tripwire.')
param budgetAmount int = 2

@description('First day of the month the budget starts tracking from. Must be the 1st; the Consumption Budgets API cannot change this on an existing budget without recreating it.')
param budgetStartDate string = '2026-08-01'

@description('Emails notified when spend crosses the alert thresholds.')
param budgetContactEmails array = [
  'hayden@hp.id.au'
]

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

resource appInsightsDailyCap 'Microsoft.Insights/components/pricingPlans@2017-10-01' = {
  parent: appInsights
  name: 'current'
  properties: {
    cap: json(appInsightsDailyCapGb)
    warningThreshold: 90
    stopSendNotificationWhenHitCap: false
  }
}

resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: keyVaultName
  location: location
  properties: {
    sku: {
      family: 'A'
      name: 'standard'
    }
    tenantId: tenant().tenantId
    // Unlike WEBSITE_RUN_FROM_PACKAGE, this one isn't optional to omit:
    // the Key Vault RP rejects a PUT with no accessPolicies at all
    // ("The parameter accessPolicies is not specified"), so it has to be
    // asserted here. `[]` is safe because the accessPolicies/add child
    // resource below runs immediately after within the same deployment
    // and re-adds the grant before anything else touches the vault.
    accessPolicies: []
  }
}

resource githubTokenSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'GithubToken'
  properties: {
    value: githubToken
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
    keyVaultReferenceIdentity: 'SystemAssigned'
    siteConfig: {
      powerShellVersion: powerShellVersion
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
          value: '@Microsoft.KeyVault(SecretUri=${githubTokenSecret.properties.secretUri})'
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
        {
          name: 'GITHUB_BRANCH'
          value: githubBranch
        }
        {
          name: 'BUSY_WEEK_MODULO'
          value: string(busyWeekModulo)
        }
        {
          name: 'BUSY_WEEK_REMAINDER'
          value: string(busyWeekRemainder)
        }
        {
          name: 'BUSY_WEEK_MULTIPLIER'
          value: busyWeekMultiplier
        }
        {
          name: 'QUIET_WEEK_REMAINDER'
          value: string(quietWeekRemainder)
        }
        {
          name: 'QUIET_WEEK_MULTIPLIER'
          value: quietWeekMultiplier
        }
      ]
    }
  }
}

// Lets the Function App's managed identity read secrets from the vault.
// Uses a Key Vault access policy rather than an Azure RBAC role
// assignment deliberately: creating a role assignment needs
// Microsoft.Authorization/roleAssignments/write, which the Contributor
// role the GitHub OIDC identity deploys with does NOT grant. Access
// policies are a Key Vault-scoped action Contributor already has, so
// this deploys without widening that identity's permissions.
// Split into its own accessPolicies/add resource (rather than a property
// on the vault itself) to avoid a circular dependency: the vault would
// need functionApp's principalId, while functionApp needs the vault's
// secret URI.
resource keyVaultAccessPolicy 'Microsoft.KeyVault/vaults/accessPolicies@2023-07-01' = {
  parent: keyVault
  name: 'add'
  properties: {
    accessPolicies: [
      {
        tenantId: tenant().tenantId
        objectId: functionApp.identity.principalId
        permissions: {
          secrets: ['get']
        }
      }
    ]
  }
}

resource budget 'Microsoft.Consumption/budgets@2023-11-01' = {
  name: 'vanity-metrics-monthly-budget'
  properties: {
    category: 'Cost'
    amount: budgetAmount
    timeGrain: 'Monthly'
    timePeriod: {
      startDate: budgetStartDate
    }
    notifications: {
      actual_GreaterThan_80_Percent: {
        enabled: true
        operator: 'GreaterThan'
        threshold: 80
        thresholdType: 'Actual'
        contactEmails: budgetContactEmails
      }
      forecasted_GreaterThan_100_Percent: {
        enabled: true
        operator: 'GreaterThan'
        threshold: 100
        thresholdType: 'Forecasted'
        contactEmails: budgetContactEmails
      }
    }
  }
}

// Note: the "Failure Anomalies" smart detector alert rule that shows up
// next to Application Insights in the portal is auto-provisioned by Azure
// Monitor whenever a Insights component is created. It isn't defined here
// deliberately — Azure recreates it on its own.

output functionAppName string = functionApp.name
output functionAppDefaultHostName string = functionApp.properties.defaultHostName
