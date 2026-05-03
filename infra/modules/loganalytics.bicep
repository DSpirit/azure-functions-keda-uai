// ─────────────────────────────────────────────────────────────────────────────
// loganalytics.bicep — Log Analytics Workspace
//
// Used as the backing store for Application Insights (workspace-based mode).
// ─────────────────────────────────────────────────────────────────────────────

param location string
param workspaceName string

resource workspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: workspaceName
  location: location
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
  }
}

output workspaceId string = workspace.id
output workspaceName string = workspace.name
