#!/bin/bash

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

FAILURE_THRESHOLD="${PLAYIT_FAILURE_THRESHOLD:-3}"
COOLDOWN_SECONDS="${PLAYIT_RESTART_COOLDOWN_SECONDS:-300}"
STATE_FILE="${PLAYIT_HEALTH_STATE_FILE:-/run/playit-health.state}"

is_positive_integer "$FAILURE_THRESHOLD" || {
  echo "[playit-health] PLAYIT_FAILURE_THRESHOLD must be a positive integer." >&2
  exit 1
}
is_nonnegative_integer "$COOLDOWN_SECONDS" || {
  echo "[playit-health] PLAYIT_RESTART_COOLDOWN_SECONDS must be a nonnegative integer." >&2
  exit 1
}

mkdir -p "$(dirname "$STATE_FILE")" 2>/dev/null || true
now="$(date +%s)"
failures=0
last_restart=0
if [ -f "$STATE_FILE" ]; then
  read -r failures last_restart < "$STATE_FILE" || true
fi
failures="${failures:-0}"
last_restart="${last_restart:-0}"
is_nonnegative_integer "$failures" || failures=0
is_nonnegative_integer "$last_restart" || last_restart=0

status_output="$(playit status 2>/dev/null || true)"
phase="$(printf '%s\n' "$status_output" | awk -F: 'tolower($1) ~ /phase/ {gsub(/^[[:space:]]+/, "", $2); print tolower($2); exit}')"
forwarding="$(printf '%s\n' "$status_output" | awk -F: 'tolower($1) ~ /forward/ {gsub(/^[[:space:]]+/, "", $2); print tolower($2); exit}')"

if systemctl is-active --quiet playit && {
  [ "$phase" = "running" ] || [ "$phase" = "connected" ] || [ "$phase" = "online" ] ||
  [ "$phase" = "active" ] || [ "$phase" = "established" ] || [ "$phase" = "ready" ] ||
  [ "$forwarding" = "true" ] || [ "$forwarding" = "enabled" ] ||
  [ "$forwarding" = "active" ] || [ "$forwarding" = "yes" ];
}; then
  printf '0 %s\n' "$last_restart" > "$STATE_FILE"
  echo "[playit-health] Tunnel healthy."
  exit 0
fi

failures=$((failures + 1))
printf '%s %s\n' "$failures" "$last_restart" > "$STATE_FILE"
if [ "$failures" -lt "$FAILURE_THRESHOLD" ]; then
  echo "[playit-health] Unhealthy status ($failures/$FAILURE_THRESHOLD); waiting before restart."
  exit 0
fi

if [ "$((now - last_restart))" -lt "$COOLDOWN_SECONDS" ]; then
  echo "[playit-health] Restart suppressed by cooldown."
  exit 1
fi

echo "[playit-health] Tunnel unhealthy after $failures checks. Restarting agent..."
if sudo systemctl restart playit; then
  printf '0 %s\n' "$now" > "$STATE_FILE"
  exit 0
fi

echo "[playit-health] Agent restart failed." >&2
exit 1
