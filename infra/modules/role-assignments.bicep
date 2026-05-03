// ─────────────────────────────────────────────────────────────────────────────
// role-assignments.bicep — RBAC for the user-assigned managed identity
//
// Grants the minimum set of roles required for the function app to operate
// without connection strings or storage account keys:
//
//   • Storage Queue Data Contributor  — read/process queue messages
//   • Storage Blob Data Owner         — required by the Azure Functions host runtime
//                                       for internal blob-based locking and lease storage
//   • AcrPull                         — pull the container image from ACR
//
// Role definition IDs are built-in and stable across all Azure tenants.
// ─────────────────────────────────────────────────────────────────────────────

param storageAccountId string
param acrId string
param principalId string // Object ID of the user-assigned managed identity

// ── Built-in role definition IDs ─────────────────────────────────────────────
var storageQueueDataContributorRoleId = '974c5e8b-45b9-4653-ba55-5f855dd0fb88'
var storageBlobDataOwnerRoleId        = 'b7e6dc6d-f1e8-4753-8033-0f276bb0955b'
var acrPullRoleId                     = '7f951dda-4ed3-4680-a7ca-43fe172d538d'

// ── Existing resource references ──────────────────────────────────────────────
// Required to set the scope property on role assignment resources.
resource storageAccountRef 'Microsoft.Storage/storageAccounts@2023-05-01' existing = {
  name: last(split(storageAccountId, '/'))!
}

resource acrRef 'Microsoft.ContainerRegistry/registries@2023-07-01' existing = {
  name: last(split(acrId, '/'))!
}

// ── Storage Queue Data Contributor ───────────────────────────────────────────
resource storageQueueDataContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  // Scope to the storage account; the role covers all queues within it.
  scope: storageAccountRef
  // Use a deterministic GUID so re-deployments are idempotent.
  name: guid(storageAccountId, principalId, storageQueueDataContributorRoleId)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', storageQueueDataContributorRoleId)
    principalId: principalId
    principalType: 'ServicePrincipal'
  }
}

// ── Storage Blob Data Owner ───────────────────────────────────────────────────
resource storageBlobDataOwner 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: storageAccountRef
  name: guid(storageAccountId, principalId, storageBlobDataOwnerRoleId)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', storageBlobDataOwnerRoleId)
    principalId: principalId
    principalType: 'ServicePrincipal'
  }
}

// ── AcrPull ───────────────────────────────────────────────────────────────────
resource acrPull 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: acrRef
  name: guid(acrId, principalId, acrPullRoleId)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', acrPullRoleId)
    principalId: principalId
    principalType: 'ServicePrincipal'
  }
}
