// ─────────────────────────────────────────────────────────────────────────────
// storage.bicep — Azure Storage Account + Queue
//
// Creates a StorageV2 account with:
//   • No public blob access
//   • HTTPS only
//   • A "work-items" queue used by the Azure Functions queue trigger
//
// No storage account keys are exposed; all access is via managed identity RBAC.
// ─────────────────────────────────────────────────────────────────────────────

param location string
param storageAccountName string

// Queue name must match the queueName in QueueTriggerFunction.cs and the KEDA scale rule.
var queueName = 'work-items'

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: storageAccountName
  location: location
  kind: 'StorageV2'
  sku: {
    name: 'Standard_LRS'
  }
  properties: {
    supportsHttpsTrafficOnly: true
    allowBlobPublicAccess: false
    minimumTlsVersion: 'TLS1_2'
    // Disable shared-key access — all operations must use Azure AD credentials.
    allowSharedKeyAccess: false
  }
}

resource queueService 'Microsoft.Storage/storageAccounts/queueServices@2023-05-01' = {
  parent: storageAccount
  name: 'default'
}

resource workItemsQueue 'Microsoft.Storage/storageAccounts/queueServices/queues@2023-05-01' = {
  parent: queueService
  name: queueName
}

output storageAccountId string = storageAccount.id
output storageAccountName string = storageAccount.name
// Queue service URI used by the WorkItemsStorage connection prefix in the function app.
// Uses environment() to avoid hardcoding cloud-specific URLs (supports sovereign clouds).
output queueServiceUri string = 'https://${storageAccount.name}.queue.${environment().suffixes.storage}'
// Blob service URI required by the Azure Functions host runtime for internal bookkeeping.
output blobServiceUri string = 'https://${storageAccount.name}.blob.${environment().suffixes.storage}'
output queueName string = queueName
