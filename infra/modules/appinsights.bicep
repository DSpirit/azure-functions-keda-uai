// ─────────────────────────────────────────────────────────────────────────────
// appinsights.bicep — Application Insights (workspace-based)
//
// Workspace-based mode is the current best practice; classic mode is deprecated.
// ─────────────────────────────────────────────────────────────────────────────

param location string
param appInsightsName string
param logAnalyticsWorkspaceId string

resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: appInsightsName
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
    // Link to the Log Analytics workspace (workspace-based mode).
    WorkspaceResourceId: logAnalyticsWorkspaceId
    IngestionMode: 'LogAnalytics'
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

output appInsightsId string = appInsights.id
output appInsightsName string = appInsights.name
// Connection string is the preferred way to configure Application Insights; the instrumentation key is legacy.
output connectionString string = appInsights.properties.ConnectionString
