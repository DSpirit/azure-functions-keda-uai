#Requires -Version 7
<#
.SYNOPSIS
    Build, push, and deploy the Azure Functions on Container Apps sample.

.DESCRIPTION
    This script:
      1. Creates the resource group (if it doesn't exist)
      2. Deploys all Azure infrastructure via Bicep (phase 1 — placeholder image)
      3. Builds and pushes the Docker image to ACR
      4. Re-deploys Bicep with the real image reference (phase 2)
      5. Sends a test queue message using your Azure CLI login identity (no storage keys)
      6. Prints a summary of deployed resources

.PARAMETER ResourceGroup
    Name of the Azure resource group (created if it does not exist).

.PARAMETER Location
    Azure region. Defaults to 'eastus'.

.PARAMETER EnvName
    Short lowercase alphanumeric prefix (3-12 chars) for all resource names.
    Defaults to 'funcapp'.

.PARAMETER Tag
    Docker image tag. Defaults to a UTC timestamp (yyyyMMddHHmmss).

.EXAMPLE
    ./scripts/deploy.ps1 -ResourceGroup rg-myapp -Location eastus -EnvName myapp
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)]
    [string] $ResourceGroup,

    [string] $Location = 'eastus',

    [ValidatePattern('^[a-z0-9]{3,12}$')]
    [string] $EnvName = 'funcapp',

    [string] $Tag = (Get-Date -Format 'yyyyMMddHHmmss' -AsUTC)
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot  = Split-Path -Parent $ScriptDir

Write-Host ""
Write-Host "╔══════════════════════════════════════════════════════════════╗"
Write-Host "║   Azure Functions on Container Apps — Deploy Script          ║"
Write-Host "╚══════════════════════════════════════════════════════════════╝"
Write-Host ""
Write-Host "  Resource group : $ResourceGroup"
Write-Host "  Location       : $Location"
Write-Host "  Environment    : $EnvName"
Write-Host "  Image tag      : $Tag"
Write-Host ""

# ── 1. Ensure resource group exists ──────────────────────────────────────────
Write-Host "▶  Ensuring resource group '$ResourceGroup' exists..."
az group create --name $ResourceGroup --location $Location --output none
if ($LASTEXITCODE -ne 0) { throw "Failed to create/verify resource group." }
Write-Host "   Done."

# ── 2. Initial Bicep deployment (placeholder image) ───────────────────────────
Write-Host ""
Write-Host "▶  Deploying infrastructure (phase 1 — placeholder image)..."
$deploymentJson = az deployment group create `
    --resource-group $ResourceGroup `
    --template-file "$RepoRoot/infra/main.bicep" `
    --parameters "envName=$EnvName" "location=$Location" `
    --query "properties.outputs" `
    --output json
if ($LASTEXITCODE -ne 0) { throw "Bicep deployment (phase 1) failed." }

$outputs          = $deploymentJson | ConvertFrom-Json
$AcrLoginServer   = $outputs.acrLoginServer.value
$StorageAccount   = $outputs.storageAccountName.value
$QueueName        = $outputs.queueName.value
$LogWorkspace     = $outputs.logWorkspaceName.value
$AppInsights      = $outputs.appInsightsName.value
$ContainerApp     = $outputs.containerAppName.value

Write-Host "   ACR login server : $AcrLoginServer"
Write-Host "   Container app    : $ContainerApp"

# ── 3. Build and push the container image ─────────────────────────────────────
$ImageRef = "$AcrLoginServer/functionapp:$Tag"
$AcrName  = $AcrLoginServer.Split('.')[0]

Write-Host ""
Write-Host "▶  Logging in to ACR '$AcrLoginServer'..."
az acr login --name $AcrName
if ($LASTEXITCODE -ne 0) { throw "ACR login failed." }

Write-Host ""
Write-Host "▶  Building Docker image '$ImageRef'..."
docker build `
    --tag $ImageRef `
    --file "$RepoRoot/src/FunctionApp/Dockerfile" `
    "$RepoRoot/src/FunctionApp"
if ($LASTEXITCODE -ne 0) { throw "Docker build failed." }

Write-Host ""
Write-Host "▶  Pushing image '$ImageRef'..."
docker push $ImageRef
if ($LASTEXITCODE -ne 0) { throw "Docker push failed." }

# ── 4. Re-deploy Bicep with the real image ────────────────────────────────────
Write-Host ""
Write-Host "▶  Deploying infrastructure (phase 2 — real image)..."
az deployment group create `
    --resource-group $ResourceGroup `
    --template-file "$RepoRoot/infra/main.bicep" `
    --parameters "envName=$EnvName" "location=$Location" "containerImage=$ImageRef" `
    --output none
if ($LASTEXITCODE -ne 0) { throw "Bicep deployment (phase 2) failed." }
Write-Host "   Done."

# ── 5. Send a test queue message ──────────────────────────────────────────────
Write-Host ""
Write-Host "▶  Sending test queue message to '$QueueName'..."
$testMessage = '{"id":"test-001","description":"Hello from deploy script"}'
az storage message put `
    --account-name $StorageAccount `
    --queue-name $QueueName `
    --content $testMessage `
    --auth-mode login
if ($LASTEXITCODE -ne 0) { throw "Failed to send queue message." }
Write-Host "   Message enqueued."

# ── 6. Print summary ──────────────────────────────────────────────────────────
Write-Host ""
Write-Host "╔══════════════════════════════════════════════════════════════╗"
Write-Host "║   Deployment complete ✓                                      ║"
Write-Host "╚══════════════════════════════════════════════════════════════╝"
Write-Host ""
Write-Host "  Resource group      : $ResourceGroup"
Write-Host "  Container app       : $ContainerApp"
Write-Host "  Storage account     : $StorageAccount"
Write-Host "  Queue name          : $QueueName"
Write-Host "  Application Insights: $AppInsights"
Write-Host "  Log Analytics WS    : $LogWorkspace"
Write-Host "  ACR login server    : $AcrLoginServer"
Write-Host ""
Write-Host "  View logs:"
Write-Host "    az containerapp logs show --name $ContainerApp --resource-group $ResourceGroup --follow"
Write-Host ""
Write-Host "  Send another test message:"
Write-Host "    az storage message put --account-name $StorageAccount --queue-name $QueueName ``"
Write-Host "      --content '{""id"":""test-002""}' --auth-mode login"
Write-Host ""
Write-Host "  Clean up:"
Write-Host "    az group delete --name $ResourceGroup --yes --no-wait"
Write-Host ""
