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

require_container() {
  docker inspect "$CONTAINER_NAME" >/dev/null 2>&1 || {
    echo "Container not found: $CONTAINER_NAME" >&2
    return 1
  }
}

volume_name() {
  local mounted_volume
  mounted_volume="$(docker inspect -f '{{range .Mounts}}{{if eq .Destination "/data"}}{{.Name}}{{end}}{{end}}' "$CONTAINER_NAME" 2>/dev/null || true)"
  if [ -n "$mounted_volume" ]; then
    printf '%s\n' "$mounted_volume"
  else
    compose config --volumes | head -n 1
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

server_list() {
  docker exec "$CONTAINER_NAME" send-command "list"
}

last_service_result() {
  systemctl show "$1" -p Result --value 2>/dev/null || true
}

last_service_status() {
  systemctl show "$1" -p ExecMainStatus --value 2>/dev/null || true
}