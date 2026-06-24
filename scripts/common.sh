#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$ROOT_DIR/.env"

if [[ -f "$ENV_FILE" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a
fi

if [[ ${EUID:-0} -eq 0 ]]; then
  SUDO=()
else
  SUDO=(sudo)
fi

need_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

docker_compose() {
  need_cmd docker
  (
    cd "$ROOT_DIR"
    if "${SUDO[@]}" docker compose version >/dev/null 2>&1; then
      "${SUDO[@]}" docker compose "$@"
      return 0
    fi

    if command -v docker-compose >/dev/null 2>&1; then
      "${SUDO[@]}" docker-compose "$@"
      return 0
    fi

    echo "未检测到 docker compose 或 docker-compose，请先执行 ./install.sh" >&2
    exit 1
  )
}
