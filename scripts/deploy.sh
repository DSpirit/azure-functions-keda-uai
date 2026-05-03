#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# deploy.sh — Build, push, and deploy the Azure Functions on Container Apps sample
#
# Prerequisites:
#   • Azure CLI >= 2.57  (az login already completed)
#   • Bicep CLI (installed automatically by az deployment group create)
#
# Usage:
#   chmod +x scripts/deploy.sh
#   ./scripts/deploy.sh --resource-group rg-myapp --location eastus --env-name myapp
#
# Environment variables (alternative to flags):
#   RESOURCE_GROUP, LOCATION, ENV_NAME
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

# ── Defaults ──────────────────────────────────────────────────────────────────
RESOURCE_GROUP="${RESOURCE_GROUP:-}"
LOCATION="${LOCATION:-eastus}"
ENV_NAME="${ENV_NAME:-funcapp}"
IMAGE_TAG="$(date -u +%Y%m%d%H%M%S)"

STORAGE_QUEUE_DATA_CONTRIBUTOR_ROLE_ID="974c5e8b-45b9-4653-ba55-5f855dd0fb88"

# ── Argument parsing ──────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --resource-group|-g) RESOURCE_GROUP="$2"; shift 2 ;;
    --location|-l)       LOCATION="$2";       shift 2 ;;
    --env-name|-e)       ENV_NAME="$2";       shift 2 ;;
    --tag|-t)            IMAGE_TAG="$2";       shift 2 ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

if [[ -z "$RESOURCE_GROUP" ]]; then
  echo "ERROR: --resource-group is required." >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║   Azure Functions on Container Apps — Deploy Script          ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
echo "  Resource group : $RESOURCE_GROUP"
echo "  Location       : $LOCATION"
echo "  Environment    : $ENV_NAME"
echo "  Image tag      : $IMAGE_TAG"
echo ""

# ── 1. Ensure resource group exists ──────────────────────────────────────────
echo "▶  Ensuring resource group '$RESOURCE_GROUP' exists..."
az group create \
  --name "$RESOURCE_GROUP" \
  --location "$LOCATION" \
  --output none
echo "   Done."

# ── 2. Initial Bicep deployment (with placeholder image) ─────────────────────
# The container app is created with a placeholder image so all infrastructure
# (including ACR) is ready before we build and push the real image.
echo ""
echo "▶  Deploying infrastructure (phase 1 — placeholder image)..."
DEPLOYMENT_OUTPUT=$(az deployment group create \
  --resource-group "$RESOURCE_GROUP" \
  --template-file "$REPO_ROOT/infra/main.bicep" \
  --parameters envName="$ENV_NAME" location="$LOCATION" \
  --query "properties.outputs" \
  --output json)

ACR_LOGIN_SERVER=$(echo "$DEPLOYMENT_OUTPUT" | jq -r '.acrLoginServer.value')
STORAGE_ACCOUNT=$(echo "$DEPLOYMENT_OUTPUT" | jq -r '.storageAccountName.value')
QUEUE_NAME=$(echo "$DEPLOYMENT_OUTPUT" | jq -r '.queueName.value')
LOG_WORKSPACE=$(echo "$DEPLOYMENT_OUTPUT" | jq -r '.logWorkspaceName.value')
APP_INSIGHTS=$(echo "$DEPLOYMENT_OUTPUT" | jq -r '.appInsightsName.value')
CONTAINER_APP=$(echo "$DEPLOYMENT_OUTPUT" | jq -r '.containerAppName.value')

echo "   ACR login server : $ACR_LOGIN_SERVER"
echo "   Container app    : $CONTAINER_APP"

echo ""
echo "▶  Enabling ACR ARM authentication for managed-identity image pulls..."
az acr config authentication-as-arm update \
  --registry "${ACR_LOGIN_SERVER%%.*}" \
  --status enabled \
  --output none
echo "   Done."

# ── 3. Build and push the container image ─────────────────────────────────────
IMAGE_REF="$ACR_LOGIN_SERVER/functionapp:$IMAGE_TAG"

echo ""
echo "▶  Building and pushing image in ACR as linux/amd64..."
pushd "$REPO_ROOT/src/FunctionApp" >/dev/null
az acr build \
  --registry "${ACR_LOGIN_SERVER%%.*}" \
  --image "functionapp:$IMAGE_TAG" \
  --file "Dockerfile" \
  --platform linux/amd64 \
  .
popd >/dev/null

# ── 4. Re-deploy Bicep with the real image ────────────────────────────────────
echo ""
echo "▶  Deploying infrastructure (phase 2 — real image)..."
az deployment group create \
  --resource-group "$RESOURCE_GROUP" \
  --template-file "$REPO_ROOT/infra/main.bicep" \
  --parameters envName="$ENV_NAME" location="$LOCATION" containerImage="$IMAGE_REF" \
  --output none
echo "   Done."

# ── 5. Send a test queue message ──────────────────────────────────────────────
# Uses your Azure CLI login identity to enqueue a message — no storage keys.
echo ""
if "$REPO_ROOT/scripts/send-queue-message.sh" \
  --resource-group "$RESOURCE_GROUP" \
  --storage-account "$STORAGE_ACCOUNT" \
  --queue-name "$QUEUE_NAME" \
  --content '{"id":"test-001","description":"Hello from deploy script"}'
then
  :
else
  echo "   WARNING: Test message could not be enqueued during deployment."
  echo "   Retry later with scripts/send-queue-message.sh once RBAC propagation has completed."
fi

# ── 6. Print summary ──────────────────────────────────────────────────────────
echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║   Deployment complete ✓                                      ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
echo "  Resource group      : $RESOURCE_GROUP"
echo "  Container app       : $CONTAINER_APP"
echo "  Storage account     : $STORAGE_ACCOUNT"
echo "  Queue name          : $QUEUE_NAME"
echo "  Application Insights: $APP_INSIGHTS"
echo "  Log Analytics WS    : $LOG_WORKSPACE"
echo "  ACR login server    : $ACR_LOGIN_SERVER"
echo ""
echo "  View logs:"
echo "    az containerapp logs show --name $CONTAINER_APP --resource-group $RESOURCE_GROUP --follow"
echo ""
echo "  Send another test message:"
echo "    ./scripts/send-queue-message.sh --resource-group $RESOURCE_GROUP --content '{\"id\":\"test-002\"}'"
echo ""
echo "  Clean up:"
echo "    az group delete --name $RESOURCE_GROUP --yes --no-wait"
echo ""
