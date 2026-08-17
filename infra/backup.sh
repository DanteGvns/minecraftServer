#!/bin/bash

set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
TEMP_BACKUP=""
LOCK_DIR=""
SAVE_HELD=0
BACKUP_RETENTION="${MC_BACKUP_RETENTION:-4}"
SAVE_QUERY_PATTERN="${MC_SAVE_QUERY_PATTERN:-disabled|paused|hold|not[[:space:]]+saving}"

cleanup() {
	local status=$?
	if [ "$SAVE_HELD" -eq 1 ]; then
		docker exec "$CONTAINER_NAME" send-command "save resume" >/dev/null 2>&1 || true
	fi
	if [ -n "$TEMP_BACKUP" ] && [ -d "$TEMP_BACKUP" ]; then
		sudo rm -rf -- "$TEMP_BACKUP"
	fi
	if [ -n "$LOCK_DIR" ] && [ -d "$LOCK_DIR" ]; then
		rmdir -- "$LOCK_DIR" 2>/dev/null || true
	fi
	exit "$status"
}
trap cleanup EXIT INT TERM

require_command docker
require_container
is_container_running || { echo "Container is not running: $CONTAINER_NAME" >&2; exit 1; }
[ "$BACKUP_RETENTION" -ge 1 ] 2>/dev/null || {
	echo "MC_BACKUP_RETENTION must be a positive integer." >&2
	exit 1
}
mkdir -p "$BACKUP_DIR"
LOCK_DIR="$BACKUP_DIR/.backup.lock"
if ! mkdir "$LOCK_DIR" 2>/dev/null; then
	echo "Another backup or restore operation is already in progress." >&2
	exit 1
fi
WORLD_SOURCE="$(world_mountpoint)"
[ -d "$WORLD_SOURCE" ] || { echo "World directory not found: $WORLD_SOURCE" >&2; exit 1; }
TIMESTAMP="$(date +"%Y-%m-%d_%H-%M-%S")"
FINAL_BACKUP="$BACKUP_DIR/world_$TIMESTAMP"
TEMP_BACKUP="$BACKUP_DIR/.world_$TIMESTAMP.in-progress"
echo "Initiating Bedrock world backup..."
docker exec "$CONTAINER_NAME" send-command "save hold" >/dev/null
SAVE_HELD=1
QUERY_OUTPUT=""
for attempt in 1 2 3 4 5 6 7 8 9 10; do
	QUERY_OUTPUT="$(docker exec "$CONTAINER_NAME" send-command "save query" 2>/dev/null || true)"
	if [ -n "$QUERY_OUTPUT" ] && printf '%s' "$QUERY_OUTPUT" | grep -Eiq "$SAVE_QUERY_PATTERN"; then
		break
	fi
	[ "$attempt" -eq 10 ] || sleep 1
done

printf '%s' "$QUERY_OUTPUT" | grep -Eiq "$SAVE_QUERY_PATTERN" || {
	echo "Could not verify that Bedrock saving is paused." >&2
	exit 1
}

mkdir -p "$TEMP_BACKUP/worlds"
sudo cp -a "$WORLD_SOURCE" "$TEMP_BACKUP/worlds/"
[ -d "$TEMP_BACKUP/worlds/$WORLD_NAME" ] || {
	echo "Backup copy did not contain the expected world." >&2
	exit 1
}
 [ -e "$FINAL_BACKUP" ] && {
	echo "Backup destination already exists: $FINAL_BACKUP" >&2
	exit 1
}
sudo mv -- "$TEMP_BACKUP" "$FINAL_BACKUP"
TEMP_BACKUP=""

find "$BACKUP_DIR" -mindepth 1 -maxdepth 1 -type d -name 'world_*' -printf '%T@ %p\n' \
	| sort -rn | tail -n +$((BACKUP_RETENTION + 1)) | cut -d' ' -f2- \
	| while IFS= read -r old_backup; do
			[ -n "$old_backup" ] && sudo rm -rf -- "$old_backup"
		done

echo "Local backup created at: $FINAL_BACKUP"
