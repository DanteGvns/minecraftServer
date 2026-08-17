#!/bin/bash

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${MC_ENV_FILE:-$SCRIPT_DIR/.env}"

load_environment() {
  local key value
  [ -f "$ENV_FILE" ] || return 0
  while IFS='=' read -r key value || [ -n "$key" ]; do
    key="$(printf '%s' "$key" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
    case "$key" in
      ''|'#'*) continue ;;
      [A-Za-z_][A-Za-z0-9_]*) ;;
      *) continue ;;
    esac
    if [ -z "${!key+x}" ]; then
      value="${value%$'\r'}"
      value="${value#\"}"
      value="${value%\"}"
      value="${value#\'}"
      value="${value%\'}"
      export "$key=$value"
    fi
  done < "$ENV_FILE"
}

load_environment

CONTAINER_NAME="${MC_CONTAINER_NAME:-bedrock}"
COMPOSE_FILE="${MC_COMPOSE_FILE:-$SCRIPT_DIR/docker-compose.yml}"
BACKUP_DIR="${MC_BACKUP_DIR:-$SCRIPT_DIR/backups}"
PRERESTORE_DIR="${MC_PRERESTORE_DIR:-$BACKUP_DIR/prerestored}"
WORLD_NAME="${MC_WORLD_NAME:-Bedrock level}"
WORLD_PATH="worlds/$WORLD_NAME"
COMPOSE_PROJECT="${COMPOSE_PROJECT_NAME:-infra}"
SERVER_PORT="${MC_SERVER_PORT:-${SERVER_PORT:-19132}}"
STATUS_TIMEOUT_SECONDS="${MC_STATUS_TIMEOUT_SECONDS:-5}"
OPERATION_LOCK_FILE="${MC_OPERATION_LOCK_FILE:-$BACKUP_DIR/.operation.lock}"

compose() {
  if [ -f "$ENV_FILE" ]; then
    docker compose --env-file "$ENV_FILE" -p "$COMPOSE_PROJECT" -f "$COMPOSE_FILE" "$@"
  else
    docker compose -p "$COMPOSE_PROJECT" -f "$COMPOSE_FILE" "$@"
  fi
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Required command not found: $1" >&2
    return 1
  }
}

is_positive_integer() {
  [[ "$1" =~ ^[1-9][0-9]*$ ]]
}

is_nonnegative_integer() {
  [[ "$1" =~ ^[0-9]+$ ]]
}

is_valid_port() {
  is_positive_integer "$1" && [ "$1" -le 65535 ]
}

acquire_operation_lock() {
  [ "${MC_OPERATION_LOCK_HELD:-0}" = "1" ] && return 0
  require_command flock || return 1
  sudo mkdir -p "$(dirname "$OPERATION_LOCK_FILE")"
  sudo touch "$OPERATION_LOCK_FILE"
  sudo chmod 0666 "$OPERATION_LOCK_FILE"
  exec {OPERATION_LOCK_FD}>"$OPERATION_LOCK_FILE"
  if ! flock -n "$OPERATION_LOCK_FD"; then
    echo "Another backup, restore, or deployment operation is already in progress." >&2
    return 1
  fi
}

require_container() {
  docker inspect "$CONTAINER_NAME" >/dev/null 2>&1 || {
    echo "Container not found: $CONTAINER_NAME" >&2
    return 1
  }
}

volume_name() {
  local mounted_volume volume_key
  mounted_volume="$(docker inspect -f '{{range .Mounts}}{{if eq .Destination "/data"}}{{.Name}}{{end}}{{end}}' "$CONTAINER_NAME" 2>/dev/null || true)"
  if [ -n "$mounted_volume" ]; then
    printf '%s\n' "$mounted_volume"
  else
    volume_key="$(compose config --volumes | head -n 1)"
    [ -n "$volume_key" ] || return 1
    docker volume ls \
      --filter "label=com.docker.compose.project=$COMPOSE_PROJECT" \
      --filter "label=com.docker.compose.volume=$volume_key" \
      --format '{{.Name}}' | head -n 1
  fi
}

volume_mountpoint() {
  local volume
  volume="$(volume_name)"
  [ -n "$volume" ] || {
    echo "Could not determine the Compose data volume." >&2
    return 1
  }
  docker volume inspect -f '{{.Mountpoint}}' "$volume"
}

world_mountpoint() {
  printf '%s/%s\n' "$(volume_mountpoint)" "$WORLD_PATH"
}

is_container_running() {
  [ "$(docker inspect -f '{{.State.Running}}' "$CONTAINER_NAME" 2>/dev/null || true)" = "true" ]
}

server_status() {
  timeout "$STATUS_TIMEOUT_SECONDS" docker exec "$CONTAINER_NAME" mc-monitor status-bedrock --host 127.0.0.1 --port "$SERVER_PORT"
}

wait_for_server() {
  local timeout_seconds="$1"
  local deadline=$((SECONDS + timeout_seconds))
  while [ "$SECONDS" -lt "$deadline" ]; do
    if is_container_running && server_status >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done
  return 1
}

world_is_valid() {
  local world_dir="$1"
  sudo test -f "$world_dir/level.dat" &&
    sudo test -d "$world_dir/db" &&
    [ -n "$(sudo find "$world_dir/db" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null)" ]
}

last_service_result() {
  systemctl show "$1" -p Result --value 2>/dev/null || true
}

last_service_status() {
  systemctl show "$1" -p ExecMainStatus --value 2>/dev/null || true
}

last_service_started() {
  systemctl show "$1" -p ExecMainStartTimestamp --value 2>/dev/null || true
}