#!/bin/bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

READY_TIMEOUT_SECONDS="${MC_READY_TIMEOUT_SECONDS:-120}"
UPDATE_HISTORY="${MC_UPDATE_HISTORY:-$SCRIPT_DIR/update-history.log}"

mkdir -p "$(dirname "$UPDATE_HISTORY")"
BEFORE_IMAGE="$(docker inspect -f '{{.Config.Image}}' "$CONTAINER_NAME" 2>/dev/null || echo none)"
BEFORE_IMAGE_ID="$(docker inspect -f '{{.Image}}' "$CONTAINER_NAME" 2>/dev/null || true)"
BEFORE_VERSION="$(docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "$CONTAINER_NAME" 2>/dev/null | sed -n 's/^VERSION=//p' | head -n 1 || true)"
TIMESTAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

is_positive_integer "$READY_TIMEOUT_SECONDS" || {
  echo "MC_READY_TIMEOUT_SECONDS must be a positive integer." >&2
  exit 1
}
is_positive_integer "$STATUS_TIMEOUT_SECONDS" || {
  echo "MC_STATUS_TIMEOUT_SECONDS must be a positive integer." >&2
  exit 1
}
is_valid_port "$SERVER_PORT" || {
  echo "MC_SERVER_PORT must be an integer from 1 through 65535." >&2
  exit 1
}
acquire_operation_lock

EXISTING_WORLD="$(world_mountpoint 2>/dev/null || true)"
if [ -n "$EXISTING_WORLD" ] && world_is_valid "$EXISTING_WORLD"; then
  echo "Creating pre-update backup..."
  MC_OPERATION_LOCK_HELD=1 bash "$SCRIPT_DIR/backup.sh"
else
  echo "No existing world found; skipping the pre-update backup for first deployment."
fi
echo "Pulling pinned Bedrock image..."
compose pull
echo "Starting Bedrock container..."
compose up -d

AFTER_IMAGE="$(docker inspect -f '{{.Config.Image}}' "$CONTAINER_NAME" 2>/dev/null || echo unknown)"
AFTER_VERSION="$(docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "$CONTAINER_NAME" 2>/dev/null | sed -n 's/^VERSION=//p' | head -n 1 || true)"
if wait_for_server "$READY_TIMEOUT_SECONDS"; then
  printf '%s previous_image=%s previous_version=%s target_image=%s target_version=%s result=success\n' "$TIMESTAMP" "$BEFORE_IMAGE" "${BEFORE_VERSION:-unknown}" "$AFTER_IMAGE" "${AFTER_VERSION:-unknown}" >> "$UPDATE_HISTORY"
  echo "Deploy complete. Server is responding."
else
  printf '%s previous_image=%s previous_version=%s target_image=%s target_version=%s result=readiness-timeout\n' "$TIMESTAMP" "$BEFORE_IMAGE" "${BEFORE_VERSION:-unknown}" "$AFTER_IMAGE" "${AFTER_VERSION:-unknown}" >> "$UPDATE_HISTORY"
  echo "Deploy timed out waiting for the Bedrock server. Attempting rollback..." >&2
  if [ -n "$BEFORE_IMAGE_ID" ] && [ "$BEFORE_IMAGE" != "none" ] && [ -n "$BEFORE_VERSION" ]; then
    docker tag "$BEFORE_IMAGE_ID" "$BEFORE_IMAGE"
    BEDROCK_VERSION="$BEFORE_VERSION" compose up -d --force-recreate
    if wait_for_server "$READY_TIMEOUT_SECONDS"; then
      printf '%s previous_image=%s previous_version=%s result=rollback-success\n' "$TIMESTAMP" "$BEFORE_IMAGE" "$BEFORE_VERSION" >> "$UPDATE_HISTORY"
      echo "Rollback succeeded; the previous Bedrock version is responding." >&2
      exit 1
    fi
  fi
  printf '%s previous_image=%s previous_version=%s result=rollback-failed\n' "$TIMESTAMP" "$BEFORE_IMAGE" "${BEFORE_VERSION:-unknown}" >> "$UPDATE_HISTORY"
  echo "Rollback failed or no previous deployment was available. Use the pre-update backup for recovery." >&2
  exit 1
fi
