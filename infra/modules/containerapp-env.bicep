// ─────────────────────────────────────────────────────────────────────────────
// containerapp-env.bicep — Azure Container Apps Environment
//
// The environment is the shared boundary for networking and observability.
// Container app logs are streamed to the linked Log Analytics workspace.
// ─────────────────────────────────────────────────────────────────────────────

param location string
param environmentName string
param logAnalyticsWorkspaceId string
// Log Analytics shared key is required by the ACA environment to push logs.
// It is retrieved as a secure value and never stored in outputs.
@secure()
param logAnalyticsWorkspaceKey string

resource containerAppEnv 'Microsoft.App/managedEnvironments@2024-03-01' = {
  name: environmentName
  location: location
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: logAnalyticsWorkspaceId
        sharedKey: logAnalyticsWorkspaceKey
      }
    }
    // Workload profiles enable the Consumption plan (serverless, scale-to-zero).
    workloadProfiles: [
      {
        name: 'Consumption'
        workloadProfileType: 'Consumption'
      }
    ]
  }
}

output environmentId string = containerAppEnv.id
output environmentName string = containerAppEnv.name
