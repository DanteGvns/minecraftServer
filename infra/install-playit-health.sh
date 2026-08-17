#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPOSITORY_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SED_REPOSITORY_DIR="$(printf '%s' "$REPOSITORY_DIR" | sed 's/[\\&|]/\\&/g')"

sed "s|/REPOSITORY|$SED_REPOSITORY_DIR|g" "$SCRIPT_DIR/playit-health.service" | sudo tee /etc/systemd/system/playit-health.service >/dev/null
sudo cp "$SCRIPT_DIR/playit-health.timer" /etc/systemd/system/

sudo systemctl daemon-reload
sudo systemctl reset-failed playit-health.service 2>/dev/null || true
sudo systemctl enable --now playit-health.timer
sudo systemctl restart playit-health.timer

echo "Playit auto-heal system installed."
