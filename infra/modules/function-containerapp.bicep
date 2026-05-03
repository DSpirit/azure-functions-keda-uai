// ─────────────────────────────────────────────────────────────────────────────
// function-containerapp.bicep — Azure Functions on Azure Container Apps
//
// Deploys the function app as a Container App.  Key design decisions:
//
//   • No HTTP ingress — the function is queue-triggered only.
//   • Scale-to-zero is enabled (minReplicas = 0).
//   • KEDA azure-queue scaler uses the user-assigned managed identity for
//     authentication — no SAS tokens or connection strings.
//   • AzureWebJobsStorage uses identity-based connection
//     (accountName + managed identity) instead of a connection string.
//   • AZURE_CLIENT_ID pins DefaultAzureCredential to the specific
//     user-assigned managed identity.
// ─────────────────────────────────────────────────────────────────────────────

param location string
param containerAppName string
param containerAppEnvId string
param containerImage string
param storageAccountName string
param queueServiceUri string
param blobServiceUri string
param appInsightsConnectionString string

var imageRegistryServer = split(containerImage, '/')[0]
var usesAcrManagedIdentity = endsWith(toLower(imageRegistryServer), '.azurecr.io')
var registries = usesAcrManagedIdentity ? [
  {
    server: imageRegistryServer
    identity: 'system'
  }
] : null

resource functionApp 'Microsoft.App/containerApps@2024-10-02-preview' = {
  name: containerAppName
  kind: 'functionapp'
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    managedEnvironmentId: containerAppEnvId
    workloadProfileName: 'Consumption'
    configuration: {
      // Keep only one active revision to avoid parallel placeholder/app revisions.
      activeRevisionsMode: 'Single'
      ingress: {
        external: true
        targetPort: 80
        allowInsecure: false
      }
      // Only private ACR images need registry authentication via managed identity.
      registries: registries
    }
    template: {
      containers: [
        {
          name: 'function-app'
          image: containerImage
          resources: {
            cpu: json('0.5')
            memory: '1Gi'
          }
          env: [
            // ── Azure Functions runtime ──────────────────────────────────────
            {
              name: 'FUNCTIONS_WORKER_RUNTIME'
              value: 'dotnet-isolated'
            }
            {
              name: 'AzureWebJobsFeatureFlags'
              value: 'EnableWorkerIndexing'
            }
            // ── Internal host storage (identity-based, no connection string) ─
            // AzureWebJobsStorage__accountName tells the Functions host which
            // storage account to use for internal bookkeeping (locks, leases, etc.).
            // DefaultAzureCredential (via AZURE_CLIENT_ID) handles authentication.
            {
              name: 'AzureWebJobsStorage__accountName'
              value: storageAccountName
            }
            {
              name: 'AzureWebJobsStorage__blobServiceUri'
              value: blobServiceUri
            }
            {
              name: 'AzureWebJobsStorage__queueServiceUri'
              value: queueServiceUri
            }
            // ── Queue trigger connection (identity-based) ────────────────────
            // "WorkItemsStorage" is the Connection prefix used in QueueTrigger.
            // The SDK resolves WorkItemsStorage__serviceUri to the queue endpoint
            // and authenticates using DefaultAzureCredential.
            {
              name: 'WorkItemsStorage__serviceUri'
              value: queueServiceUri
            }
            // ── Observability ────────────────────────────────────────────────
            {
              name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
              value: appInsightsConnectionString
            }
          ]
        }
      ]
      scale: {
        // Scale to zero when the queue is empty; scale up as messages accumulate.
        minReplicas: 0
        maxReplicas: 10
      }
    }
  }
}

output containerAppName string = functionApp.name
output containerAppId string = functionApp.id
output containerAppPrincipalId string = functionApp.identity.principalId
