#!/bin/bash
set -e

# Check if Playit agent is running
if ! systemctl is-active --quiet playit; then
    echo "[playit-health] Playit agent is NOT running. Restarting..."
    sudo systemctl restart playit
    exit 0
fi

# Check tunnel status using playit CLI
STATUS=$(playit status 2>/dev/null | grep -i "Phase:" | awk '{print $2}')

if [[ "$STATUS" != "running" ]]; then
    echo "[playit-health] Playit agent running but tunnel NOT active. Restarting..."
    sudo systemctl restart playit
    exit 0
fi

# Check for traffic (no traffic = stuck tunnel)
TRAFFIC=$(playit status 2>/dev/null | grep -i "Traffic:" | awk '{print $2}')

if [[ "$TRAFFIC" == "0" ]]; then
    echo "[playit-health] Tunnel stuck (0 traffic). Restarting..."
    sudo systemctl restart playit
    exit 0
fi

echo "[playit-health] Tunnel healthy."