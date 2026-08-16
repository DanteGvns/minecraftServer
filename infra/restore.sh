#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_DIR="$SCRIPT_DIR/backups"

echo "Minecraft Bedrock Restore Utility"

echo "Available backups:"
ls -1 "$BACKUP_DIR"
echo
read -p "Enter backup folder name to restore: " FOLDER

TARGET="$BACKUP_DIR/$FOLDER/worlds"

if [ ! -d "$TARGET" ]; then
  echo "Backup world folder not found."
  exit 1
fi

echo "Stopping Bedrock container..."
docker stop bedrock

# Wait until container is fully stopped
while docker ps | grep -q bedrock; do
    sleep 1
done

echo "Restoring world data from: $TARGET"

sudo rm -rf /var/lib/docker/volumes/infra_bedrock_data/_data/worlds/*
sudo cp -r "$TARGET"/* /var/lib/docker/volumes/infra_bedrock_data/_data/worlds/

echo "Starting Bedrock container..."
docker start bedrock

echo "Restore complete. World has been replaced with backup: $FOLDER"