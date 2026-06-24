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

docker_pull_failure_needs_ipv4_retry() {
  local log_file="$1"

  # 403 Forbidden 是镜像加速站权限问题，不是网络问题，不应触发 IPv4 重试
  if grep -Eiq '403 Forbidden' "$log_file"; then
    return 1
  fi

  grep -Eiq \
    'registry-1\.docker\.io|docker\.io/|connection reset by peer|failed to resolve reference|TLS handshake timeout|i/o timeout|read tcp .*2600:' \
    "$log_file"
}

configure_docker_ipv4_retry() {
  if [[ ! -f "$ROOT_DIR/configure-docker-mirror.sh" ]]; then
    echo "未找到 $ROOT_DIR/configure-docker-mirror.sh，无法自动切换 IPv4。" >&2
    return 1
  fi

  echo "检测到 Docker Hub 拉取疑似走 IPv6 被重置，正在自动切换为优先 IPv4 并重试一次..."
  "${SUDO[@]}" env NONINTERACTIVE=yes PREFER_IPV4=yes bash "$ROOT_DIR/configure-docker-mirror.sh"
}

docker_compose_pull_with_retry() {
  local pull_log attempt

  pull_log="$(mktemp)"

  if docker_compose pull >"$pull_log" 2>&1; then
    cat "$pull_log"
    rm -f "$pull_log"
    return 0
  fi

  cat "$pull_log"

  # IPv6/网络问题：先尝试切换 IPv4
  if docker_pull_failure_needs_ipv4_retry "$pull_log"; then
    echo
    configure_docker_ipv4_retry || true
    if docker_compose pull >"$pull_log" 2>&1; then
      cat "$pull_log"
      rm -f "$pull_log"
      return 0
    fi
    cat "$pull_log"
  fi

  # 网络超时/不稳定：额外重试 3 次，每次等待 20 秒
  for attempt in 1 2 3; do
    if ! grep -Eiq 'TLS handshake timeout|i/o timeout|connection reset by peer|read: connection reset' "$pull_log"; then
      break
    fi
    echo
    echo "网络不稳定（超时/重置），${20} 秒后第 ${attempt}/3 次重试..."
    sleep 20
    if docker_compose pull >"$pull_log" 2>&1; then
      cat "$pull_log"
      rm -f "$pull_log"
      return 0
    fi
    cat "$pull_log"
  done

  rm -f "$pull_log"
  return 1
}
