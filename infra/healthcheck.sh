#!/bin/bash
# healthcheck.sh
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_DIR="$SCRIPT_DIR/backups"

echo "Minecraft Bedrock Server Health Check"

echo "Checking Docker..."
if systemctl is-active --quiet docker; then
  echo "Docker: OK"
else
  echo "Docker: NOT RUNNING"
fi

echo "Checking Bedrock container..."
if docker ps --format '{{.Names}}' | grep -q "bedrock"; then
  echo "Bedrock container: RUNNING"
else
  echo "Bedrock container: NOT RUNNING"
fi

echo "Checking Bedrock server responsiveness..."
if docker exec bedrock send-command "list" >/dev/null 2>&1; then
  echo "Bedrock server: RESPONDING"
else
  echo "Bedrock server: NO RESPONSE"
fi

echo "Checking backup directory..."
if [ -d "$BACKUP_DIR" ]; then
  echo "Backup directory: OK"
  COUNT=$(ls -1 "$BACKUP_DIR" | wc -l)
  echo "Backups found: $COUNT"
else
  echo "Backup directory: MISSING"
fi

echo "Checking systemd backup timer..."
if systemctl is-active --quiet mc-backup.timer; then
  echo "Backup timer: ACTIVE"
else
  echo "Backup timer: INACTIVE"
fi

echo "Checking systemd backup service status..."
systemctl --no-pager status mc-backup.service >/dev/null 2>&1 && echo "Backup service: OK" || echo "Backup service: ERROR"

echo "Checking disk space..."
df -h / | awk 'NR==2 {print "Disk usage: " $5 " used (" $4 " free)"}'

echo "Health check complete."
