#!/usr/bin/env bash

set -euo pipefail

RESOURCE_GROUP="${RESOURCE_GROUP:-az-keda}"
CONTAINER_APP="${CONTAINER_APP:-ca-funcapp-func}"
DEPLOYMENT_NAME="${DEPLOYMENT_NAME:-main}"
OUT_ROOT="${OUT_ROOT:-artifacts/support-pack}"
TS="$(date -u +%Y%m%dT%H%M%SZ)"
OUT_DIR="$OUT_ROOT/$TS"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --resource-group|-g) RESOURCE_GROUP="$2"; shift 2 ;;
    --container-app|-a) CONTAINER_APP="$2"; shift 2 ;;
    --deployment-name|-d) DEPLOYMENT_NAME="$2"; shift 2 ;;
    --out-dir|-o) OUT_ROOT="$2"; OUT_DIR="$OUT_ROOT/$TS"; shift 2 ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

mkdir -p "$OUT_DIR"
TMP_DIR="$(mktemp -d)"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

sanitize_text() {
  local in_file="$1"
  local out_file="$2"

  sed -E \
    -e 's#/subscriptions/[0-9a-fA-F-]{36}#/subscriptions/<SUBSCRIPTION_ID>#g' \
    -e 's#"subscriptionId"[[:space:]]*:[[:space:]]*"[^"]*"#"subscriptionId":"<SUBSCRIPTION_ID>"#g' \
    -e 's#"tenantId"[[:space:]]*:[[:space:]]*"[^"]*"#"tenantId":"<TENANT_ID>"#g' \
    -e 's#"principalId"[[:space:]]*:[[:space:]]*"[^"]*"#"principalId":"<PRINCIPAL_ID>"#g' \
    -e 's#"clientId"[[:space:]]*:[[:space:]]*"[^"]*"#"clientId":"<CLIENT_ID>"#g' \
    -e 's#"objectId"[[:space:]]*:[[:space:]]*"[^"]*"#"objectId":"<OBJECT_ID>"#g' \
    -e 's#[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}#<GUID>#g' \
    -e 's#https://[^[:space:]"<>]+#https://<REDACTED_HOST>#g' \
    "$in_file" > "$out_file"
}

run_json_cmd() {
  local name="$1"
  shift
  local raw="$TMP_DIR/$name.raw.json"
  local out="$OUT_DIR/$name.json"

  if "$@" > "$raw" 2> "$TMP_DIR/$name.stderr"; then
    sanitize_text "$raw" "$out"
  else
    {
      echo '{'
      echo '  "status": "command_failed",'
      echo "  \"command\": \"$*\","
      echo '  "stderr": "See .txt file"'
      echo '}'
    } > "$out"
    sanitize_text "$TMP_DIR/$name.stderr" "$OUT_DIR/$name.error.txt"
  fi
}

run_text_cmd() {
  local name="$1"
  shift
  local raw="$TMP_DIR/$name.raw.txt"
  local out="$OUT_DIR/$name.txt"

  if "$@" > "$raw" 2> "$TMP_DIR/$name.stderr"; then
    sanitize_text "$raw" "$out"
  else
    sanitize_text "$TMP_DIR/$name.stderr" "$OUT_DIR/$name.error.txt"
  fi
}

run_json_cmd "containerapp_show" \
  az containerapp show -g "$RESOURCE_GROUP" -n "$CONTAINER_APP" -o json --only-show-errors

run_json_cmd "containerapp_scale_and_env" \
  az containerapp show -g "$RESOURCE_GROUP" -n "$CONTAINER_APP" \
  --query '{identityType:identity.type,revisionMode:properties.configuration.activeRevisionsMode,scaleRules:properties.template.scale.rules,env:properties.template.containers[0].env}' \
  -o json --only-show-errors

run_json_cmd "containerapp_revisions" \
  az containerapp revision list -g "$RESOURCE_GROUP" -n "$CONTAINER_APP" -o json --only-show-errors

run_text_cmd "containerapp_logs_tail300" \
  az containerapp logs show -g "$RESOURCE_GROUP" -n "$CONTAINER_APP" --tail 300 --only-show-errors

run_json_cmd "deployment_main" \
  az deployment group show -g "$RESOURCE_GROUP" -n "$DEPLOYMENT_NAME" -o json --only-show-errors

cat > "$OUT_DIR/repro-summary.md" <<'EOF'
# Functions on ACA - Sanitized Repro Bundle

- Resource group: <RESOURCE_GROUP>
- Container app: <CONTAINER_APP>
- Deployment name: <DEPLOYMENT_NAME>
- Observation: Azure Functions on ACA does not auto-create queue scaler rules (`scaleRules` is null).

## Included files

- containerapp_show.json
- containerapp_scale_and_env.json
- containerapp_revisions.json
- containerapp_logs_tail300.txt
- deployment_main.json

All identifiers and hostnames are redacted for safe sharing.
EOF

ZIP_PATH="$OUT_DIR.zip"
(
  cd "$OUT_ROOT"
  zip -rq "$(basename "$ZIP_PATH")" "$(basename "$OUT_DIR")"
)

echo "Sanitized support bundle created: $OUT_DIR"
echo "Sanitized zip created: $ZIP_PATH"
