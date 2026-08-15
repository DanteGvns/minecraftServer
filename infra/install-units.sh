#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Installing systemd units..."

sudo cp "$SCRIPT_DIR/mc-backup.service" /etc/systemd/system/mc-backup.service
sudo cp "$SCRIPT_DIR/mc-backup.timer" /etc/systemd/system/mc-backup.timer

sudo systemctl daemon-reload
sudo systemctl enable mc-backup.timer
sudo systemctl start mc-backup.timer

echo "Systemd backup units installed and timer started."
