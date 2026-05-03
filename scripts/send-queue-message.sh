#!/usr/bin/env bash

set -euo pipefail

RESOURCE_GROUP="${RESOURCE_GROUP:-}"
STORAGE_ACCOUNT="${STORAGE_ACCOUNT:-}"
QUEUE_NAME="${QUEUE_NAME:-}"
MESSAGE_CONTENT='{"id":"test-001","description":"Hello from queue message script"}'
MESSAGE_ENCODING="${MESSAGE_ENCODING:-base64}"

STORAGE_QUEUE_DATA_CONTRIBUTOR_ROLE_ID="974c5e8b-45b9-4653-ba55-5f855dd0fb88"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --resource-group|-g) RESOURCE_GROUP="$2"; shift 2 ;;
    --storage-account|-s) STORAGE_ACCOUNT="$2"; shift 2 ;;
    --queue-name|-q) QUEUE_NAME="$2"; shift 2 ;;
    --content|-c) MESSAGE_CONTENT="$2"; shift 2 ;;
    --encoding) MESSAGE_ENCODING="$2"; shift 2 ;;
    --raw-content) MESSAGE_ENCODING="none"; shift ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

if [[ -z "$RESOURCE_GROUP" ]]; then
  echo "ERROR: --resource-group is required." >&2
  exit 1
fi

DEPLOYMENT_OUTPUT=$(az deployment group show \
  --resource-group "$RESOURCE_GROUP" \
  --name main \
  --query properties.outputs \
  --output json 2>/dev/null || echo '{}')

if [[ -z "$STORAGE_ACCOUNT" ]]; then
  STORAGE_ACCOUNT=$(echo "$DEPLOYMENT_OUTPUT" | jq -r '.storageAccountName.value // empty')
fi

if [[ -z "$STORAGE_ACCOUNT" ]]; then
  # Fallback for cases where deployment outputs are unavailable.
  STORAGE_ACCOUNT=$(az storage account list \
    --resource-group "$RESOURCE_GROUP" \
    --query '[0].name' \
    --output tsv 2>/dev/null || true)
fi

if [[ -z "$QUEUE_NAME" ]]; then
  QUEUE_NAME=$(echo "$DEPLOYMENT_OUTPUT" | jq -r '.queueName.value // empty')
fi

if [[ -z "$QUEUE_NAME" ]]; then
  # Default queue name used by this sample.
  QUEUE_NAME='work-items'
fi

if [[ -z "$STORAGE_ACCOUNT" || -z "$QUEUE_NAME" ]]; then
  echo "ERROR: Could not determine storage account or queue name automatically." >&2
  echo "Pass --storage-account and --queue-name explicitly." >&2
  exit 1
fi

if [[ "$MESSAGE_ENCODING" != "base64" && "$MESSAGE_ENCODING" != "none" ]]; then
  echo "ERROR: --encoding must be 'base64' or 'none'." >&2
  exit 1
fi

MESSAGE_CONTENT_TO_SEND="$MESSAGE_CONTENT"
if [[ "$MESSAGE_ENCODING" == "base64" ]]; then
  # Azure Functions queue trigger commonly expects Base64 payloads by default.
  MESSAGE_CONTENT_TO_SEND=$(printf '%s' "$MESSAGE_CONTENT" | base64 | tr -d '\n')
fi

DEPLOYER_PRINCIPAL_TYPE=$(az account show --query user.type -o tsv)
DEPLOYER_PRINCIPAL_NAME=$(az account show --query user.name -o tsv)

if [[ "$DEPLOYER_PRINCIPAL_TYPE" == "user" ]]; then
  DEPLOYER_PRINCIPAL_ID=$(az ad signed-in-user show --query id -o tsv)
  ASSIGNEE_PRINCIPAL_TYPE="User"
else
  DEPLOYER_PRINCIPAL_ID=$(az ad sp show --id "$DEPLOYER_PRINCIPAL_NAME" --query id -o tsv)
  ASSIGNEE_PRINCIPAL_TYPE="ServicePrincipal"
fi

STORAGE_ACCOUNT_ID=$(az storage account show \
  --name "$STORAGE_ACCOUNT" \
  --resource-group "$RESOURCE_GROUP" \
  --query id \
  --output tsv)

az role assignment create \
  --assignee-object-id "$DEPLOYER_PRINCIPAL_ID" \
  --assignee-principal-type "$ASSIGNEE_PRINCIPAL_TYPE" \
  --role "$STORAGE_QUEUE_DATA_CONTRIBUTOR_ROLE_ID" \
  --scope "$STORAGE_ACCOUNT_ID" \
  --output none 2>/dev/null || true

echo "▶  Sending queue message to '$QUEUE_NAME' on '$STORAGE_ACCOUNT' (encoding: $MESSAGE_ENCODING)..."

if az storage message put \
  --account-name "$STORAGE_ACCOUNT" \
  --queue-name "$QUEUE_NAME" \
  --content "$MESSAGE_CONTENT_TO_SEND" \
  --auth-mode login
then
  echo "   Message enqueued."
else
  echo "   WARNING: Message could not be enqueued with the signed-in principal." >&2
  echo "   RBAC propagation can take a few minutes; retry the script shortly." >&2
  exit 1
fi