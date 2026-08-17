#!/bin/bash

set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
CONTAINER_WAS_RUNNING=0
RESTORE_STARTED=0
STAGING_DIR=""
OLD_WORLD=""
LOCK_DIR=""

cleanup() {
  local status=$?
  if [ -n "$STAGING_DIR" ] && [ -d "$STAGING_DIR" ]; then
    sudo rm -rf -- "$STAGING_DIR"
  fi
  if [ -n "$LOCK_DIR" ] && [ -d "$LOCK_DIR" ]; then
    rmdir -- "$LOCK_DIR" 2>/dev/null || true
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
mkdir -p "$BACKUP_DIR" "$PRERESTORE_DIR"
LOCK_DIR="$BACKUP_DIR/.backup.lock"
if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  echo "Another backup or restore operation is already in progress." >&2
  exit 1
fi

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
[ -d "$TARGET" ] || { echo "Backup world folder not found: $TARGET" >&2; exit 1; }
[ -f "$TARGET/level.dat" ] || { echo "Backup is missing level.dat." >&2; exit 1; }
[ -d "$TARGET/db" ] || { echo "Backup is missing the world database." >&2; exit 1; }

LIVE_WORLD="$(world_mountpoint)"
WORLD_PARENT="$(dirname "$LIVE_WORLD")"
[ -d "$WORLD_PARENT" ] || { echo "Live worlds directory not found: $WORLD_PARENT" >&2; exit 1; }

STAGING_DIR="$(sudo mktemp -d "$WORLD_PARENT/.restore.XXXXXX")"
sudo mkdir -p "$STAGING_DIR/worlds"
sudo cp -a "$TARGET" "$STAGING_DIR/worlds/"
[ -f "$STAGING_DIR/worlds/$WORLD_NAME/level.dat" ] || { echo "Staged restore is incomplete." >&2; exit 1; }

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

OLD_WORLD="$WORLD_PARENT/.world-before-restore-$TIMESTAMP"
sudo mv -- "$LIVE_WORLD" "$OLD_WORLD"
if ! sudo mv -- "$STAGING_DIR/worlds/$WORLD_NAME" "$LIVE_WORLD"; then
  sudo mv -- "$OLD_WORLD" "$LIVE_WORLD"
  echo "Restore failed; original world was put back." >&2
  exit 1
fi
STAGING_DIR=""
sudo rm -rf -- "$OLD_WORLD"

if [ "$CONTAINER_WAS_RUNNING" -eq 1 ]; then
  echo "Starting Bedrock container..."
  docker start "$CONTAINER_NAME" >/dev/null
fi

find "$PRERESTORE_DIR" -mindepth 1 -maxdepth 1 -type d -name 'world_*' -printf '%T@ %p\n' \
  | sort -rn | tail -n +6 | cut -d' ' -f2- | xargs -r sudo rm -rf --

echo "Restore complete. World replaced with backup: $FOLDER"
echo "Undo snapshot retained at: $PRERESTORE_PATH"
