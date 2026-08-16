#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

sudo cp "$SCRIPT_DIR/playit-health.service" /etc/systemd/system/
sudo cp "$SCRIPT_DIR/playit-health.timer" /etc/systemd/system/

sudo systemctl daemon-reload
sudo systemctl enable playit-health.timer
sudo systemctl start playit-health.timer

echo "Playit auto-heal system installed."
