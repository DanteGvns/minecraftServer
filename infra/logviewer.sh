#!/bin/bash
# logviewer.sh
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Minecraft Bedrock Log Viewer"
echo "Select a log source:"
echo "1) Bedrock server (docker logs)"
echo "2) Backup script output (infra/backups/)"
echo "3) Systemd backup service logs"
echo "4) Follow Bedrock server logs (live tail)"
echo "5) Exit"

read -p "Choice: " CHOICE

case "$CHOICE" in
  1)
    echo "Showing Bedrock server logs..."
    docker logs bedrock
    ;;
  2)
    echo "Available backups:"
    ls -1 "$SCRIPT_DIR/backups"
    echo
    read -p "Enter backup folder name: " FOLDER
    LOGFILE="$SCRIPT_DIR/backups/$FOLDER"
    if [ -d "$LOGFILE" ]; then
      echo "Backup folder contents:"
      ls -1 "$LOGFILE"
    else
      echo "Backup not found."
    fi
    ;;
  3)
    echo "Showing systemd backup service logs..."
    sudo journalctl -u mc-backup.service --no-pager
    ;;
  4)
    echo "Following Bedrock server logs (Ctrl+C to stop)..."
    docker logs -f bedrock
    ;;
  5)
    echo "Exiting."
    exit 0
    ;;
  *)
    echo "Invalid choice."
    ;;
esac
