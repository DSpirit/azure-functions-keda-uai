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
param userAssignedIdentityId string
param userAssignedIdentityClientId string
param storageAccountName string
param queueServiceUri string
param blobServiceUri string
param queueName string
param appInsightsConnectionString string

resource functionApp 'Microsoft.App/containerApps@2024-03-01' = {
  name: containerAppName
  location: location
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      // Key must be the full resource ID of the managed identity.
      '${userAssignedIdentityId}': {}
    }
  }
  properties: {
    environmentId: containerAppEnvId
    workloadProfileName: 'Consumption'
    configuration: {
      // No HTTP ingress — queue trigger only.
      ingress: null
      // Pull the container image from ACR using the managed identity (AcrPull role assigned separately).
      registries: [
        {
          server: split(containerImage, '/')[0]
          identity: userAssignedIdentityId
        }
      ]
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
            // ── Managed identity ─────────────────────────────────────────────
            // Setting AZURE_CLIENT_ID causes DefaultAzureCredential to use this
            // specific user-assigned managed identity instead of any system-assigned
            // or ambient credential.
            {
              name: 'AZURE_CLIENT_ID'
              value: userAssignedIdentityClientId
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
        rules: [
          {
            name: 'queue-trigger'
            custom: {
              // KEDA azure-queue scaler — authenticates via the managed identity.
              type: 'azure-queue'
              metadata: {
                queueName: queueName
                // Trigger a new replica for every 5 messages in the queue.
                queueLength: '5'
                accountName: storageAccountName
              }
              // Use the user-assigned managed identity for KEDA to read the queue length.
              // BCP037: 'identity' is valid at runtime but not yet reflected in Bicep type
              // definitions for this API version; suppress the warning.
              #disable-next-line BCP037
              identity: userAssignedIdentityId
            }
          }
        ]
      }
    }
  }
}

output containerAppName string = functionApp.name
output containerAppId string = functionApp.id
