#!/bin/bash

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

echo "=============================="
echo " Minecraft Bedrock Dashboard"
echo "=============================="

if systemctl is-active --quiet docker; then echo "Docker: RUNNING"; else echo "Docker: NOT RUNNING"; fi
if is_container_running; then
  echo "Container: RUNNING"
  docker ps --format '{{.Names}} {{.RunningFor}}' | awk -v name="$CONTAINER_NAME" '$1 == name {print "Uptime: " $2 " " $3 " " $4}'
else
  echo "Container: NOT RUNNING"
fi

echo "Player Status:"
if LIST_OUTPUT="$(server_list 2>/dev/null)"; then
  COUNT="$(printf '%s\n' "$LIST_OUTPUT" | sed -nE 's/.*There are ([0-9]+) of a max.*/\1/p' | tail -n 1)"
  [ -n "$COUNT" ] || COUNT="$(printf '%s\n' "$LIST_OUTPUT" | sed -nE 's/.*([0-9]+) players? online.*/\1/p' | tail -n 1)"
  echo "  Players Online: ${COUNT:-unknown}"
  echo "  Response: $(printf '%s' "$LIST_OUTPUT" | tr '\n' ' ')"
else
  echo "  Players Online: unknown (server unavailable)"
fi

echo "Backups:"
if [ -d "$BACKUP_DIR" ]; then
  COUNT="$(find "$BACKUP_DIR" -mindepth 1 -maxdepth 1 -type d -name 'world_*' | wc -l)"
  LAST="$(find "$BACKUP_DIR" -mindepth 1 -maxdepth 1 -type d -name 'world_*' -printf '%T@ %f\n' | sort -rn | awk 'NR==1 {$1=""; sub(/^ /, ""); print}')"
  echo "  Total Backups: $COUNT"
  echo "  Last Backup: ${LAST:-none}"
else
  echo "  Backup directory missing"
fi

echo "Backup Automation:"
systemctl is-active --quiet mc-backup.timer && echo "  Timer: ACTIVE" || echo "  Timer: INACTIVE"
echo "  Last Result: $(last_service_result mc-backup.service)"
echo "  Last Exit Code: $(last_service_status mc-backup.service)"

echo "Playit:"
systemctl is-active --quiet playit && echo "  Agent: RUNNING" || echo "  Agent: NOT RUNNING"
systemctl is-active --quiet playit-health.timer && echo "  Health Timer: ACTIVE" || echo "  Health Timer: INACTIVE"
PHASE="$(playit status 2>/dev/null | awk -F: 'tolower($1) ~ /phase/ {gsub(/^[[:space:]]+/, "", $2); print $2; exit}')"
echo "  Phase: ${PHASE:-unknown}"

echo "System:"
df -h / | awk 'NR==2 {print "  WSL: " $5 " used (" $4 " free)"}'
[ -d /mnt/c ] && df -h /mnt/c | awk 'NR==2 {print "  C: " $5 " used (" $4 " free)"}'
free -h | awk 'NR==2 {print "  RAM: " $3 " used (" $4 " free)"}'
uptime | awk -F'load average:' '{print "  Load Avg:" $2}'

echo "=============================="
