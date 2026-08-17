#!/bin/bash

set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
CONTAINER_WAS_RUNNING=0
RESTORE_STARTED=0
STAGING_DIR=""
OLD_WORLD=""
PRERESTORE_PATH=""
PRERESTORE_COMPLETE=0
WORLD_REPLACED=0
RESTORE_VERIFIED=0
RESTORE_READY_TIMEOUT_SECONDS="${MC_RESTORE_READY_TIMEOUT_SECONDS:-120}"

cleanup() {
  local status=$?
  trap - EXIT INT TERM
  if [ "$WORLD_REPLACED" -eq 1 ] && [ "$RESTORE_VERIFIED" -eq 0 ] && [ -n "$OLD_WORLD" ] && sudo test -d "$OLD_WORLD"; then
    if is_container_running; then
      docker stop "$CONTAINER_NAME" >/dev/null 2>&1 || true
    fi
    sudo rm -rf -- "$LIVE_WORLD"
    sudo mv -- "$OLD_WORLD" "$LIVE_WORLD" || true
    OLD_WORLD=""
  fi
  if [ -n "$STAGING_DIR" ] && [ -d "$STAGING_DIR" ]; then
    sudo rm -rf -- "$STAGING_DIR"
  fi
  if [ -n "$PRERESTORE_PATH" ] && [ "$PRERESTORE_COMPLETE" -eq 0 ] && [ -d "$PRERESTORE_PATH" ]; then
    sudo rm -rf -- "$PRERESTORE_PATH"
  fi
  if [ "$CONTAINER_WAS_RUNNING" -eq 1 ] && [ "$RESTORE_STARTED" -eq 1 ]; then
    if ! is_container_running; then
      docker start "$CONTAINER_NAME" >/dev/null 2>&1 || true
    fi
  fi
  exit "$status"
}
trap cleanup EXIT INT TERM

require_command docker
require_container
is_positive_integer "$RESTORE_READY_TIMEOUT_SECONDS" || {
  echo "MC_RESTORE_READY_TIMEOUT_SECONDS must be a positive integer." >&2
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
mkdir -p "$BACKUP_DIR" "$PRERESTORE_DIR"
acquire_operation_lock

echo "Minecraft Bedrock Restore Utility"
printf 'Available backups:\n'
find "$BACKUP_DIR" -mindepth 1 -maxdepth 1 -type d -name 'world_*' -printf '%f\n' | sort
find "$PRERESTORE_DIR" -mindepth 1 -maxdepth 1 -type d -name 'world_*' -printf 'prerestored/%f\n' | sort
printf '\nEnter backup folder name to restore: '
read -r FOLDER

case "$FOLDER" in
  world_[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]_[0-9][0-9]-[0-9][0-9]-[0-9][0-9])
    BACKUP_PATH="$BACKUP_DIR/$FOLDER"
    ;;
  prerestored/world_[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]_[0-9][0-9]-[0-9][0-9]-[0-9][0-9])
    BACKUP_PATH="$PRERESTORE_DIR/${FOLDER#prerestored/}"
    ;;
  *) echo "Invalid backup folder name." >&2; exit 1 ;;
esac
TARGET="$BACKUP_PATH/worlds/$WORLD_NAME"
world_is_valid "$TARGET" || { echo "Backup is missing level.dat or a nonempty world database: $TARGET" >&2; exit 1; }

LIVE_WORLD="$(world_mountpoint)"
WORLD_PARENT="$(dirname "$LIVE_WORLD")"
sudo test -d "$WORLD_PARENT" || { echo "Live worlds directory not found: $WORLD_PARENT" >&2; exit 1; }

STAGING_DIR="$(sudo mktemp -d "$WORLD_PARENT/.restore.XXXXXX")"
sudo mkdir -p "$STAGING_DIR/worlds"
sudo cp -a "$TARGET" "$STAGING_DIR/worlds/"
world_is_valid "$STAGING_DIR/worlds/$WORLD_NAME" || { echo "Staged restore is incomplete." >&2; exit 1; }

TIMESTAMP="$(date +"%Y-%m-%d_%H-%M-%S")"
PRERESTORE_PATH="$PRERESTORE_DIR/world_$TIMESTAMP"
mkdir -p "$PRERESTORE_PATH/worlds"

if is_container_running; then
  CONTAINER_WAS_RUNNING=1
  echo "Stopping Bedrock container..."
  docker stop "$CONTAINER_NAME" >/dev/null
fi
RESTORE_STARTED=1

echo "Saving pre-restore world to: $PRERESTORE_PATH"
sudo cp -a "$LIVE_WORLD" "$PRERESTORE_PATH/worlds/"
world_is_valid "$PRERESTORE_PATH/worlds/$WORLD_NAME" || { echo "Pre-restore snapshot is incomplete." >&2; exit 1; }
PRERESTORE_COMPLETE=1

OLD_WORLD="$WORLD_PARENT/.world-before-restore-$TIMESTAMP"
sudo mv -- "$LIVE_WORLD" "$OLD_WORLD"
if ! sudo mv -- "$STAGING_DIR/worlds/$WORLD_NAME" "$LIVE_WORLD"; then
  sudo mv -- "$OLD_WORLD" "$LIVE_WORLD"
  OLD_WORLD=""
  echo "Restore failed; original world was put back." >&2
  exit 1
fi
WORLD_REPLACED=1
sudo rmdir -- "$STAGING_DIR/worlds" "$STAGING_DIR" || true
STAGING_DIR=""

if [ "$CONTAINER_WAS_RUNNING" -eq 1 ]; then
  echo "Starting Bedrock container..."
  if ! docker start "$CONTAINER_NAME" >/dev/null 2>&1 || ! wait_for_server "$RESTORE_READY_TIMEOUT_SECONDS"; then
    echo "Restored world did not become ready; putting the original world back." >&2
    if is_container_running; then
      docker stop "$CONTAINER_NAME" >/dev/null 2>&1 || true
    fi
    sudo rm -rf -- "$LIVE_WORLD"
    sudo mv -- "$OLD_WORLD" "$LIVE_WORLD"
    OLD_WORLD=""
    WORLD_REPLACED=0
    if docker start "$CONTAINER_NAME" >/dev/null 2>&1 && wait_for_server "$RESTORE_READY_TIMEOUT_SECONDS"; then
      echo "Original world restored and responding." >&2
    else
      echo "Original world was restored on disk but the server did not become ready." >&2
    fi
    exit 1
  fi
fi

RESTORE_VERIFIED=1
sudo rm -rf -- "$OLD_WORLD"
OLD_WORLD=""

find "$PRERESTORE_DIR" -mindepth 1 -maxdepth 1 -type d -name 'world_*' -printf '%T@ %p\n' \
  | sort -rn | tail -n +6 | cut -d' ' -f2- \
  | while IFS= read -r old_snapshot; do
      [ -n "$old_snapshot" ] && sudo rm -rf -- "$old_snapshot"
    done

echo "Restore complete. World replaced with backup: $FOLDER"
echo "Undo snapshot retained at: $PRERESTORE_PATH"
