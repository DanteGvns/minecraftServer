# backup.sh
#!/bin/bash
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_DIR="$SCRIPT_DIR/backups"
mkdir -p "$BACKUP_DIR"
TIMESTAMP="$(date +"%Y-%m-%d_%H-%M-%S")"
WORLD_BACKUP="$BACKUP_DIR/world_$TIMESTAMP"

echo "Initiating Bedrock world backup..."
docker exec bedrock send-command "save hold"
sleep 5
docker exec bedrock send-command "save query"
sleep 5

mkdir -p "$WORLD_BACKUP/worlds"
sudo cp -r "/var/lib/docker/volumes/infra_bedrock_data/_data/worlds/Bedrock level" "$WORLD_BACKUP/worlds"

docker exec bedrock send-command "save resume"
echo "Local backup created at: $WORLD_BACKUP"