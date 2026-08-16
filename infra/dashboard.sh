#!/bin/bash
# dashboard.sh
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_DIR="$SCRIPT_DIR/backups"

echo "=============================="
echo " Minecraft Bedrock Dashboard"
echo "=============================="

echo "Docker:"
systemctl is-active --quiet docker && echo "  Docker: RUNNING" || echo "  Docker: NOT RUNNING"

echo "Bedrock Container:"
if docker ps --format '{{.Names}}' | grep -q "bedrock"; then
  echo "  Container: RUNNING"
else
  echo "  Container: NOT RUNNING"
fi

echo "Bedrock Uptime:"
docker ps --format '{{.Names}} {{.RunningFor}}' | grep bedrock | awk '{print "  Uptime: " $2 " " $3 " " $4}'

echo "Player Count:"
COUNT=$(docker logs bedrock 2>/dev/null | grep -i "There are" | tail -n 1 | grep -o '[0-9]\+' | head -n 1)
echo "  Players Online: ${COUNT:-0}"

echo "Player List:"
PLAYER_LIST=$(docker logs bedrock 2>/dev/null | grep -A1 "There are" | tail -n 1)
if [[ -z "$PLAYER_LIST" ]] || [[ "$PLAYER_LIST" == "There"* ]]; then
  echo "  No players online."
else
  echo "  $PLAYER_LIST"
fi

echo "Backups:"
if [ -d "$BACKUP_DIR" ]; then
  COUNT=$(ls -1 "$BACKUP_DIR" | wc -l)
  LAST=$(ls -1t "$BACKUP_DIR" | head -n 1)
  echo "  Total Backups: $COUNT"
  echo "  Last Backup: $LAST"
else
  echo "  Backup directory missing."
fi

echo "Systemd Backup Timer:"
systemctl is-active --quiet mc-backup.timer && echo "  Timer: ACTIVE" || echo "  Timer: INACTIVE"

echo "Systemd Backup Service:"
systemctl is-active --quiet mc-backup.service && echo "  Service: OK" || echo "  Service: ERROR"

echo "Playit Agent:"
systemctl is-active --quiet playit && echo "  Agent: RUNNING" || echo "  Agent: NOT RUNNING"

echo "Playit Tunnel Health:"
systemctl is-active --quiet playit-health.service && echo "  Health Check: OK" || echo "  Health Check: ERROR"

echo "Playit Tunnel Status:"
PHASE=$(playit status 2>/dev/null | grep -i "Phase:" | awk '{print $2}')
TRAFFIC=$(playit status 2>/dev/null | grep -i "Traffic:" | awk '{print $2}')
echo "  Phase: ${PHASE:-unknown}"
echo "  Traffic: ${TRAFFIC:-unknown}"

echo "WSL Disk Usage:"
df -h / | awk 'NR==2 {print "  WSL: " $5 " used (" $4 " free)"}'

echo "Windows Disk Usage:"
df -h /mnt/c | awk 'NR==2 {print "  C: Drive: " $5 " used (" $4 " free)"}'

echo "Memory Usage:"
free -h | awk 'NR==2 {print "  RAM: " $3 " used (" $4 " free)"}'

echo "CPU Load:"
uptime | awk -F'load average:' '{print "  Load Avg:" $2}'

echo "=============================="
echo " Dashboard Complete"
echo "=============================="
