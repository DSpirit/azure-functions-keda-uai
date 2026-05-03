# Azure Functions on Azure Container Apps — Keyless Starter

A minimal, production-aligned sample that runs an **Azure Queue Storage–triggered Azure Function** on **Azure Container Apps** using **managed identity only** — no connection strings, no storage account keys, no secrets.

Built with:
- **.NET 10 isolated worker** (Azure Functions v4)
- **Azure Container Apps** (Consumption plan, scale-to-zero via KEDA)
- **Azure Container Registry** (managed-identity pull)
- **Application Insights** (workspace-based, for observability)
- **Bicep** (modular, parameterized infrastructure-as-code)

---

## Repository structure

```
├── src/
│   └── FunctionApp/
│       ├── FunctionApp.csproj          # .NET 10 isolated worker project
│       ├── Program.cs                  # Host builder + Application Insights
│       ├── QueueTriggerFunction.cs     # Queue trigger (identity-based connection)
│       ├── Dockerfile                  # Multi-stage build
│       ├── host.json                   # Functions host settings
│       └── local.settings.json.example # Local dev settings template
├── infra/
│   ├── main.bicep                      # Top-level orchestration
│   └── modules/
│       ├── acr.bicep                   # Azure Container Registry
│       ├── storage.bicep               # Storage account + work-items queue
│       ├── loganalytics.bicep          # Log Analytics workspace
│       ├── appinsights.bicep           # Application Insights (workspace-based)
│       ├── containerapp-env.bicep      # Container Apps environment
│       ├── function-containerapp.bicep # Function app container + KEDA scale rule
│       └── role-assignments.bicep      # RBAC assignments (no secrets)
├── scripts/
│   ├── deploy.sh                       # Bash deploy script
│   ├── send-queue-message.sh           # Bash helper to enqueue a test message
│   └── deploy.ps1                      # PowerShell deploy script
└── README.md
```

---

## Prerequisites

| Tool | Minimum version | Install |
|------|----------------|---------|
| Azure CLI | 2.57 | [docs.microsoft.com/cli/azure/install-azure-cli](https://docs.microsoft.com/cli/azure/install-azure-cli) |
| Docker (with BuildKit) | 24 | [docs.docker.com/get-docker](https://docs.docker.com/get-docker/) |
| .NET SDK | 10.0 | [dotnet.microsoft.com/download](https://dotnet.microsoft.com/download) |
| `jq` *(bash script only)* | 1.6 | `apt install jq` / `brew install jq` |
| PowerShell *(ps1 script only)* | 7.0 | [github.com/PowerShell/PowerShell](https://github.com/PowerShell/PowerShell) |

Your Azure account needs **Owner** or **Contributor + User Access Administrator** on the target resource group (to assign RBAC roles).

---

## Azure login

```bash
az login
# or with a specific tenant:
az login --tenant <tenant-id>

# Set the subscription you want to deploy to:
az account set --subscription <subscription-id>
```

---

## Deploy

### Bash

```bash
chmod +x scripts/deploy.sh

./scripts/deploy.sh \
  --resource-group rg-myapp \
  --location eastus \
  --env-name myapp
```

### PowerShell

```powershell
./scripts/deploy.ps1 `
  -ResourceGroup rg-myapp `
  -Location eastus `
  -EnvName myapp
```

### What the script does

1. Creates the resource group if it does not exist.
2. Deploys all infrastructure via `infra/main.bicep` with a placeholder image (so ACR exists before the build).
3. Builds the Docker image from `src/FunctionApp/Dockerfile`.
4. Pushes the image to ACR using `az acr login` (your CLI identity needs AcrPush on the registry, or Owner/Contributor on the resource group).
5. Re-deploys Bicep with the real image reference so the container app is updated.
6. Enqueues a test message using `az storage message put --auth-mode login` — **no storage key is used**.
7. Prints a summary of all deployed resources.

---

## Azure resources deployed

| Resource | Name pattern | Notes |
|----------|-------------|-------|
| Azure Container Registry | `cr<envName>` | adminUserEnabled = false |
| Storage account | `st<envName>` | allowSharedKeyAccess = false |
| Queue | `work-items` | Matches the trigger in code |
| Log Analytics workspace | `log-<envName>` | 30-day retention |
| Application Insights | `appi-<envName>` | Workspace-based |
| Container Apps environment | `cae-<envName>` | Consumption plan |
| Container App (function) | `ca-<envName>-func` | Scale 0–10 replicas |
| User-assigned managed identity | `id-<envName>` | Used by the function app |

### RBAC assignments (no keys, no secrets)

| Role | Scope | Purpose |
|------|-------|---------|
| Storage Queue Data Contributor | Storage account | Read & delete queue messages |
| Storage Blob Data Owner | Storage account | Azure Functions host internal bookkeeping |
| AcrPull | Container Registry | Pull the function container image |

---

## How keyless / managed-identity access works

```
┌─────────────────────────────────────────────────────────────────────┐
│  Azure Container App  (identity: id-<envName>)                       │
│                                                                      │
│  AZURE_CLIENT_ID = <client-id of id-<envName>>                       │
│                                                                      │
│  AzureWebJobsStorage__accountName = st<envName>          ─────────► │── Storage Blob Data Owner
│  WorkItemsStorage__serviceUri     = https://st<envName>  ─────────► │── Storage Queue Data Contributor
│                                                queue.core.windows.net │
│  Container image pulled from ACR                          ─────────► │── AcrPull
└─────────────────────────────────────────────────────────────────────┘
```

1. **`AZURE_CLIENT_ID`** tells `DefaultAzureCredential` (used by the Azure SDK) to authenticate as the specific user-assigned managed identity `id-<envName>`.  Without this, `DefaultAzureCredential` would try a system-assigned identity or the VM metadata endpoint.

2. **`AzureWebJobsStorage__accountName`** (without a connection string) instructs the Azure Functions host to use the storage account for its internal lease/lock storage via managed identity, rather than a connection string.

3. **`WorkItemsStorage__serviceUri`** is the [identity-based connection](https://learn.microsoft.com/azure/azure-functions/functions-reference#configure-an-identity-based-connection) for the `QueueTrigger`.  The `WorkItemsStorage` prefix matches the `Connection` property in the `[QueueTrigger]` attribute.

4. **KEDA** (built into Azure Container Apps) reads the queue length to decide how many replicas to run.  It authenticates to the storage account using the same managed identity via the `identity` field of the scale rule.

---

## Test manually

After deployment, you can enqueue messages at any time:

```bash
./scripts/send-queue-message.sh \
  --resource-group <resource-group> \
  --content '{"id":"test-002","description":"Manual test"}'
```

The script reads the storage account and queue name from the latest main Bicep deployment in the resource group. If needed, you can override them with --storage-account and --queue-name.

By default, the helper sends messages with `--encoding base64` to match the queue trigger host default. Use `--raw-content` (or `--encoding none`) only if your host is configured for non-Base64 queue payloads.

The container app will scale from 0 to 1+ replicas within ~30 seconds of the message arriving.

---

## View logs

### Container App console logs (real-time)

```bash
az containerapp logs show \
  --name ca-<envName>-func \
  --resource-group <resource-group> \
  --follow
```

### Application Insights (Kusto query)

In the Azure Portal → Application Insights → **Logs**:

```kusto
traces
| where timestamp > ago(1h)
| order by timestamp desc
```

Or for function invocations specifically:

```kusto
requests
| where timestamp > ago(1h)
| where name == "WorkItemProcessor"
| order by timestamp desc
```

## Create a share-safe support bundle

To share diagnostics publicly (for example in GitHub issues) without exposing
subscription/tenant/principal IDs or internal hostnames:

```bash
chmod +x scripts/create-sanitized-support-pack.sh

./scripts/create-sanitized-support-pack.sh \
  --resource-group <resource-group> \
  --container-app ca-<envName>-func
```

The script writes a redacted bundle under `artifacts/support-pack/<timestamp>/`
and a zip at `artifacts/support-pack/<timestamp>.zip`.

---

## Local development

1. Install [Azurite](https://learn.microsoft.com/azure/storage/common/storage-use-azurite) (local storage emulator):

   ```bash
   npm install -g azurite
   azurite --location /tmp/azurite
   ```

2. Copy the example settings file:

   ```bash
   cp src/FunctionApp/local.settings.json.example src/FunctionApp/local.settings.json
   ```

3. Run the function locally:

   ```bash
   cd src/FunctionApp
   func start
   ```

4. Enqueue a test message against the local emulator:

   ```bash
   az storage message put \
     --account-name devstoreaccount1 \
     --queue-name work-items \
     --content '{"id":"local-001"}' \
     --connection-string "UseDevelopmentStorage=true"
   ```

> **Note**: `local.settings.json` is listed in `.gitignore` — never commit it to version control.

---

## Clean up

```bash
az group delete --name <resource-group> --yes --no-wait
```

This removes all resources created by the deploy script.

---

## Naming conventions

Resource names follow [Microsoft's recommended abbreviations](https://learn.microsoft.com/azure/cloud-adoption-framework/ready/azure-best-practices/resource-abbreviations):

| Abbreviation | Resource type |
|---|---|
| `cr` | Container Registry |
| `st` | Storage account |
| `log` | Log Analytics workspace |
| `appi` | Application Insights |
| `cae` | Container Apps environment |
| `ca` | Container App |
| `id` | User-assigned managed identity |
