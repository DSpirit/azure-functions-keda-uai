// ─────────────────────────────────────────────────────────────────────────────
// main.bicep — Top-level orchestration template
//
// Deploys all resources required for the Azure Functions on Container Apps
// starter sample.  Resources are named using the recommended Azure naming
// convention: <abbreviation>-<envName> (or <abbreviation><envName> for services
// that do not allow hyphens, such as storage accounts and ACR).
//
// Usage:
//   az deployment group create \
//     --resource-group <rg> \
//     --template-file infra/main.bicep \
//     --parameters envName=<prefix> containerImage=<acr>/<repo>:<tag>
// ─────────────────────────────────────────────────────────────────────────────

targetScope = 'resourceGroup'

@minLength(3)
@maxLength(12)
@description('Short lowercase alphanumeric prefix for all resource names (3-12 chars).')
param envName string

@description('Azure region for all resources.')
param location string = resourceGroup().location

@description('''
Full container image reference including registry, repository and tag.
Example: myacr.azurecr.io/functionapp:latest
Use the placeholder value for the initial deployment; update after pushing the image.
''')
param containerImage string = 'mcr.microsoft.com/azure-functions/dotnet-isolated:4-dotnet-isolated10.0'

// ─────────────────────────────────────────────────────────────────────────────
// Resource names (deterministic and globally unique where required)
// ─────────────────────────────────────────────────────────────────────────────
// ACR and storage names must be globally unique lowercase alphanumeric.
var globalNameSuffix   = take(uniqueString(subscription().subscriptionId, resourceGroup().id, envName), 6)
var acrName            = 'cr${envName}${globalNameSuffix}'
var storageAccountName = 'st${envName}${globalNameSuffix}'
var logWorkspaceName   = 'log-${envName}'
var appInsightsName    = 'appi-${envName}'
var containerEnvName   = 'cae-${envName}'
var functionAppName    = 'ca-${envName}-func'
var identityName       = 'id-${envName}'

// ─────────────────────────────────────────────────────────────────────────────
// User-assigned managed identity
// ─────────────────────────────────────────────────────────────────────────────
resource userAssignedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: identityName
  location: location
}

// ─────────────────────────────────────────────────────────────────────────────
// Modules
// ─────────────────────────────────────────────────────────────────────────────

module acr 'modules/acr.bicep' = {
  name: 'deploy-acr'
  params: {
    location: location
    acrName: acrName
  }
}

module storage 'modules/storage.bicep' = {
  name: 'deploy-storage'
  params: {
    location: location
    storageAccountName: storageAccountName
  }
}

module logAnalytics 'modules/loganalytics.bicep' = {
  name: 'deploy-loganalytics'
  params: {
    location: location
    workspaceName: logWorkspaceName
  }
}

module appInsights 'modules/appinsights.bicep' = {
  name: 'deploy-appinsights'
  params: {
    location: location
    appInsightsName: appInsightsName
    logAnalyticsWorkspaceId: logAnalytics.outputs.workspaceId
  }
}

// Retrieve the Log Analytics shared key for the Container Apps environment.
// This is a listKeys call on the existing workspace; no secret is stored in outputs.
resource logWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' existing = {
  name: logWorkspaceName
  dependsOn: [logAnalytics]
}

module containerAppEnv 'modules/containerapp-env.bicep' = {
  name: 'deploy-containerapp-env'
  params: {
    location: location
    environmentName: containerEnvName
    logAnalyticsWorkspaceId: logWorkspace.properties.customerId
    logAnalyticsWorkspaceKey: logWorkspace.listKeys().primarySharedKey
  }
}

module roleAssignments 'modules/role-assignments.bicep' = {
  name: 'deploy-role-assignments'
  params: {
    storageAccountId: storage.outputs.storageAccountId
    acrId: acr.outputs.acrId
    principalId: userAssignedIdentity.properties.principalId
  }
}

module functionApp 'modules/function-containerapp.bicep' = {
  name: 'deploy-function-containerapp'
  // Role assignments must exist before the container app starts, otherwise the
  // Functions host will fail to authenticate to storage on first boot.
  dependsOn: [roleAssignments]
  params: {
    location: location
    containerAppName: functionAppName
    containerAppEnvId: containerAppEnv.outputs.environmentId
    containerImage: containerImage
    userAssignedIdentityId: userAssignedIdentity.id
    userAssignedIdentityClientId: userAssignedIdentity.properties.clientId
    storageAccountName: storage.outputs.storageAccountName
    queueServiceUri: storage.outputs.queueServiceUri
    blobServiceUri: storage.outputs.blobServiceUri
    appInsightsConnectionString: appInsights.outputs.connectionString
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Outputs — used by the deploy scripts
// ─────────────────────────────────────────────────────────────────────────────
output acrLoginServer       string = acr.outputs.loginServer
output storageAccountName   string = storage.outputs.storageAccountName
output queueName            string = storage.outputs.queueName
output logWorkspaceName     string = logAnalytics.outputs.workspaceName
output appInsightsName      string = appInsights.outputs.appInsightsName
output containerAppName     string = functionApp.outputs.containerAppName
output resourceGroupName    string = resourceGroup().name
