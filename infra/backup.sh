#!/bin/bash

set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
TEMP_BACKUP=""
SAVE_HELD=0
BACKUP_RETENTION="${MC_BACKUP_RETENTION:-4}"
DEFAULT_SAVE_QUERY_PATTERN='ready[[:space:]]+to[[:space:]]+be[[:space:]]+copied|data[[:space:]]+saved'
SAVE_QUERY_PATTERN="${MC_SAVE_QUERY_PATTERN:-$DEFAULT_SAVE_QUERY_PATTERN}"
if [ "$SAVE_QUERY_PATTERN" = 'disabled|paused|hold|not[[:space:]]+saving' ]; then
	echo "Ignoring the unsafe legacy MC_SAVE_QUERY_PATTERN; update infra/.env." >&2
	SAVE_QUERY_PATTERN="$DEFAULT_SAVE_QUERY_PATTERN"
fi

cleanup() {
	local status=$?
	if [ "$SAVE_HELD" -eq 1 ]; then
		docker exec "$CONTAINER_NAME" send-command "save resume" >/dev/null 2>&1 || true
	fi
	if [ -n "$TEMP_BACKUP" ] && [ -d "$TEMP_BACKUP" ]; then
		sudo rm -rf -- "$TEMP_BACKUP"
	fi
	exit "$status"
}
trap cleanup EXIT INT TERM

require_command docker
acquire_operation_lock
is_positive_integer "$BACKUP_RETENTION" || {
	echo "MC_BACKUP_RETENTION must be a positive integer." >&2
	exit 1
}
mkdir -p "$BACKUP_DIR"
WORLD_SOURCE="$(world_mountpoint)"
sudo test -d "$WORLD_SOURCE" || { echo "World directory not found: $WORLD_SOURCE" >&2; exit 1; }
world_is_valid "$WORLD_SOURCE" || { echo "Live world is missing level.dat or a nonempty world database: $WORLD_SOURCE" >&2; exit 1; }
TIMESTAMP="$(date +"%Y-%m-%d_%H-%M-%S")"
FINAL_BACKUP="$BACKUP_DIR/world_$TIMESTAMP"
TEMP_BACKUP="$BACKUP_DIR/.world_$TIMESTAMP.in-progress"
echo "Initiating Bedrock world backup..."
if is_container_running; then
	LOG_SINCE="$(date -u +%Y-%m-%dT%H:%M:%S.%NZ)"
	docker exec "$CONTAINER_NAME" send-command "save hold" >/dev/null
	SAVE_HELD=1
	QUERY_OUTPUT=""
	for attempt in 1 2 3 4 5 6 7 8 9 10; do
		docker exec "$CONTAINER_NAME" send-command "save query" >/dev/null 2>&1 || true
		sleep 1
		QUERY_OUTPUT="$(docker logs --since "$LOG_SINCE" "$CONTAINER_NAME" 2>&1 || true)"
		if [ -n "$QUERY_OUTPUT" ] && printf '%s' "$QUERY_OUTPUT" | grep -Eiq "$SAVE_QUERY_PATTERN"; then
			break
		fi
	done

	printf '%s' "$QUERY_OUTPUT" | grep -Eiq "$SAVE_QUERY_PATTERN" || {
		echo "Could not verify that Bedrock saving is paused." >&2
		exit 1
	}
else
	echo "Container is stopped; copying the offline world."
fi

mkdir -p "$TEMP_BACKUP/worlds"
sudo cp -a "$WORLD_SOURCE" "$TEMP_BACKUP/worlds/"
world_is_valid "$TEMP_BACKUP/worlds/$WORLD_NAME" || {
	echo "Backup copy is missing level.dat or a nonempty world database." >&2
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
