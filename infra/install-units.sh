#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPOSITORY_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "Installing systemd units..."

sed "s|/REPOSITORY|$REPOSITORY_DIR|g" "$SCRIPT_DIR/mc-backup.service" | sudo tee /etc/systemd/system/mc-backup.service >/dev/null
sudo cp "$SCRIPT_DIR/mc-backup.timer" /etc/systemd/system/mc-backup.timer

sudo systemctl daemon-reload
sudo systemctl reset-failed mc-backup.service 2>/dev/null || true
sudo systemctl enable --now mc-backup.timer
sudo systemctl restart mc-backup.timer

echo "Systemd backup units installed and timer started."
