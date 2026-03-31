#!/usr/bin/env bash
set -euo pipefail

# Dangerous cleanup utility:
# - stops Docker Compose stacks for this repository
# - removes ~/openclaw_z

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_DIR="${HOME}/openclaw_z"
ASSUME_YES="${1:-}"

warn() {
  printf 'WARNING: %s\n' "$*" >&2
}

run_compose_down() {
  local compose_file="$ROOT_DIR/docker-compose.yml"
  if [[ ! -f "$compose_file" ]]; then
    return 0
  fi

  echo "==> docker compose -f $compose_file down --remove-orphans --volumes"
  docker compose -f "$compose_file" down --remove-orphans --volumes || true
}

confirm() {
  if [[ "$ASSUME_YES" == "--yes" ]]; then
    return 0
  fi

  warn "This will stop Docker Compose stacks and remove: $TARGET_DIR"
  printf 'Type DELETE to continue: '
  read -r answer
  if [[ "$answer" != "DELETE" ]]; then
    echo "Aborted."
    exit 1
  fi
}

confirm_global_docker_wipe() {
  if [[ "$ASSUME_YES" == "--yes" ]]; then
    return 0
  fi

  warn "Global wipe will remove ALL Docker containers, custom networks, and volumes on this machine."
  printf 'Type WIPE to continue global Docker cleanup: '
  read -r answer
  if [[ "$answer" != "WIPE" ]]; then
    echo "Aborted before global Docker cleanup."
    exit 1
  fi
}

confirm

cd "$ROOT_DIR"

# Bring down compose stack from the main compose file.
run_compose_down

confirm_global_docker_wipe

all_container_ids="$(docker ps -aq || true)"
if [[ -n "$all_container_ids" ]]; then
  echo "==> Removing all Docker containers"
  docker rm -f $all_container_ids >/dev/null || true
else
  echo "==> No containers to remove"
fi

all_network_ids="$(docker network ls -q --filter type=custom || true)"
if [[ -n "$all_network_ids" ]]; then
  echo "==> Removing all custom Docker networks"
  docker network rm $all_network_ids >/dev/null || true
else
  echo "==> No custom networks to remove"
fi

all_volume_ids="$(docker volume ls -q || true)"
if [[ -n "$all_volume_ids" ]]; then
  echo "==> Removing all Docker volumes"
  docker volume rm $all_volume_ids >/dev/null || true
else
  echo "==> No volumes to remove"
fi

if [[ -d "$TARGET_DIR" ]]; then
  echo "==> Removing $TARGET_DIR"
  rm -rf "$TARGET_DIR"
else
  echo "==> Skipping removal: $TARGET_DIR does not exist"
fi

echo "Cleanup complete."
