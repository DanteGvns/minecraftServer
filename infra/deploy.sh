#!/bin/bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

READY_TIMEOUT_SECONDS="${MC_READY_TIMEOUT_SECONDS:-120}"
UPDATE_HISTORY="${MC_UPDATE_HISTORY:-$SCRIPT_DIR/update-history.log}"

mkdir -p "$(dirname "$UPDATE_HISTORY")"
BEFORE_IMAGE="$(docker inspect -f '{{.Config.Image}}' "$CONTAINER_NAME" 2>/dev/null || echo none)"
BEFORE_VERSION="$(docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "$CONTAINER_NAME" 2>/dev/null | sed -n 's/^VERSION=//p' | head -n 1 || true)"
TIMESTAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

echo "Creating pre-update backup..."
bash "$SCRIPT_DIR/backup.sh"
echo "Pulling pinned Bedrock image..."
compose pull
echo "Starting Bedrock container..."
compose up -d

ready=0
for ((attempt = 1; attempt <= READY_TIMEOUT_SECONDS; attempt++)); do
  if is_container_running && server_list >/dev/null 2>&1; then
    ready=1
    break
  fi
  sleep 1
done

AFTER_IMAGE="$(docker inspect -f '{{.Config.Image}}' "$CONTAINER_NAME" 2>/dev/null || echo unknown)"
AFTER_VERSION="$(docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "$CONTAINER_NAME" 2>/dev/null | sed -n 's/^VERSION=//p' | head -n 1 || true)"
if [ "$ready" -eq 1 ]; then
  printf '%s previous_image=%s previous_version=%s target_image=%s target_version=%s result=success\n' "$TIMESTAMP" "$BEFORE_IMAGE" "${BEFORE_VERSION:-unknown}" "$AFTER_IMAGE" "${AFTER_VERSION:-unknown}" >> "$UPDATE_HISTORY"
  echo "Deploy complete. Server is responding."
else
  printf '%s previous_image=%s previous_version=%s target_image=%s target_version=%s result=readiness-timeout\n' "$TIMESTAMP" "$BEFORE_IMAGE" "${BEFORE_VERSION:-unknown}" "$AFTER_IMAGE" "${AFTER_VERSION:-unknown}" >> "$UPDATE_HISTORY"
  echo "Deploy timed out waiting for the Bedrock server." >&2
  exit 1
fi
