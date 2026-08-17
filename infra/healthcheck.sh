#!/bin/bash

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

BACKUP_MAX_AGE_HOURS="${MC_BACKUP_MAX_AGE_HOURS:-26}"
DISK_MAX_USED_PERCENT="${MC_DISK_MAX_USED_PERCENT:-90}"
FAILURES=0

pass() { echo "OK: $1"; }
fail() { echo "FAIL: $1"; FAILURES=$((FAILURES + 1)); }

echo "Minecraft Bedrock Server Health Check"

if systemctl is-active --quiet docker; then pass "Docker is running"; else fail "Docker is not running"; fi
if require_container 2>/dev/null; then pass "Bedrock container exists"; else fail "Bedrock container does not exist"; fi
if is_container_running; then pass "Bedrock container is running"; else fail "Bedrock container is not running"; fi
if is_container_running && server_list >/dev/null 2>&1; then pass "Bedrock server responds to list"; else fail "Bedrock server did not respond to list"; fi
if docker port "$CONTAINER_NAME" 19132/udp 2>/dev/null | grep -q .; then pass "Bedrock UDP port is published"; else fail "Bedrock UDP port is not published"; fi

if [ -d "$BACKUP_DIR" ]; then
  backup_count="$(find "$BACKUP_DIR" -mindepth 1 -maxdepth 1 -type d -name 'world_*' | wc -l)"
  pass "Backup directory exists ($backup_count backups)"
else
  fail "Backup directory is missing"
fi

if systemctl is-active --quiet mc-backup.timer; then pass "Backup timer is active"; else fail "Backup timer is inactive"; fi
SERVICE_RESULT="$(last_service_result mc-backup.service)"
SERVICE_STATUS="$(last_service_status mc-backup.service)"
if [ "$SERVICE_RESULT" = "success" ] || [ "$SERVICE_STATUS" = "0" ]; then pass "Last backup service run succeeded"; else fail "Last backup service run failed or has not run"; fi

LATEST_BACKUP="$(find "$BACKUP_DIR" -mindepth 1 -maxdepth 1 -type d -name 'world_*' -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -n 1)"
if [ -n "$LATEST_BACKUP" ]; then
  BACKUP_TIME="${LATEST_BACKUP%% *}"
  NOW="$(date +%s)"
  BACKUP_AGE_HOURS="$(( (NOW - ${BACKUP_TIME%.*}) / 3600 ))"
  if [ "$BACKUP_AGE_HOURS" -le "$BACKUP_MAX_AGE_HOURS" ]; then pass "Newest backup is ${BACKUP_AGE_HOURS} hours old"; else fail "Newest backup is ${BACKUP_AGE_HOURS} hours old"; fi
else
  fail "No completed backups found"
fi

for mount in / /mnt/c; do
  if [ -d "$mount" ]; then
    USED="$(df -P "$mount" | awk 'NR==2 {gsub(/%/, "", $5); print $5}')"
    if [ "${USED:-100}" -lt "$DISK_MAX_USED_PERCENT" ]; then pass "$mount disk usage is ${USED}%"; else fail "$mount disk usage is ${USED}%"; fi
  fi
done

echo "Health check complete: $FAILURES failure(s)."
exit "$FAILURES"
