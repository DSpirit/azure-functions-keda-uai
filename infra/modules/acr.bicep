// ─────────────────────────────────────────────────────────────────────────────
// acr.bicep — Azure Container Registry
//
// Creates an ACR with Basic SKU (sufficient for a starter sample).
// AcrPull access for the function app identity is handled in role-assignments.bicep.
// ─────────────────────────────────────────────────────────────────────────────

param location string
param acrName string

resource acr 'Microsoft.ContainerRegistry/registries@2023-07-01' = {
  name: acrName
  location: location
  sku: {
    name: 'Basic'
  }
  properties: {
    adminUserEnabled: false // Use managed identity for pull access; no admin credentials needed.
  }
}

output acrId string = acr.id
output loginServer string = acr.properties.loginServer
