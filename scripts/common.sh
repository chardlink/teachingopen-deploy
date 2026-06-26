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
    echo "缺少必须命令: $1" >&2
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

docker_compose_mode() {
  need_cmd docker

  if "${SUDO[@]}" docker compose version >/dev/null 2>&1; then
    printf '%s' "v2"
    return 0
  fi

  if command -v docker-compose >/dev/null 2>&1; then
    local version
    version="$("${SUDO[@]}" docker-compose version --short 2>/dev/null || true)"
    if printf '%s' "$version" | grep -q '^1\.'; then
      printf '%s' "v1"
    else
      printf '%s' "standalone"
    fi
    return 0
  fi

  echo "未检测到 docker compose 或 docker-compose，请先执行 ./install.sh" >&2
  exit 1
}

docker_compose_is_legacy_v1() {
  [[ "$(docker_compose_mode)" == "v1" ]]
}

docker_compose_has_existing_containers() {
  local ids
  ids="$(docker_compose ps -aq 2>/dev/null || true)"
  [[ -n "${ids//[$'\r\n\t ']}" ]]
}

docker_compose_up_compat() {
  if docker_compose_is_legacy_v1 && docker_compose_has_existing_containers; then
    echo "检测到旧版 docker-compose v1，使用兼容模式重建服务（down + up）..."
    docker_compose down --remove-orphans || true
  fi

  docker_compose up -d "$@"
}

docker_compose_recreate_compat() {
  if docker_compose_is_legacy_v1; then
    echo "检测到旧版 docker-compose v1，使用兼容模式重新创建服务（down + up）..."
    docker_compose down --remove-orphans || true
    docker_compose up -d
    return 0
  fi

  docker_compose up -d --force-recreate --remove-orphans
}

prepare_default_upload_assets() {
  local source_dir="$ROOT_DIR/assets/default-uploads"
  local target_dir="$ROOT_DIR/data/uploads"
  local source_file target_file

  [[ -d "$source_dir" ]] || return 0

  mkdir -p "$target_dir"

  while IFS= read -r -d '' source_file; do
    target_file="$target_dir/$(basename "$source_file")"
    if [[ ! -s "$target_file" ]]; then
      cp "$source_file" "$target_file"
    fi
  done < <(find "$source_dir" -maxdepth 1 -type f -print0)
}

normalize_sys_file_location_for_local_mode() {
  local attempt

  if [[ ! -f "$ROOT_DIR/config/application-prod.yml" ]]; then
    return 0
  fi

  if ! grep -Eq '^[[:space:]]*uploadType:[[:space:]]*local([[:space:]]|$)' "$ROOT_DIR/config/application-prod.yml"; then
    return 0
  fi

  echo
  echo "正在修正本地部署中的历史 sys_file 存储位置..."

  for attempt in 1 2 3 4 5 6 7 8 9 10 11 12; do
    if docker_compose exec -T mysql sh -c \
      'exec mysql --default-character-set=utf8mb4 -uroot -p"$MYSQL_ROOT_PASSWORD" "$MYSQL_DATABASE" -e "UPDATE sys_file SET file_location = 1 WHERE file_location = 2;"' \
      >/dev/null 2>&1; then
      echo "历史 sys_file 存储位置已修正完成。"
      return 0
    fi
    sleep 5
  done

  echo "暂时未能自动修正 sys_file.file_location，稍后可重新执行 ./start.sh 或 ./update.sh 再试。" >&2
  return 0
}

normalize_default_user_avatars_for_local_mode() {
  local attempt
  local sql="
UPDATE sys_user
SET avatar = 'c76eda530e5b42328008c0d2268964a8.png'
WHERE
  avatar IS NULL
  OR avatar = ''
  OR avatar = '[]'
  OR avatar IN (
    '459b0970dd82460bb7292b6e7a50e2ed.png',
    'c80c1b5bdd86435094e0ae37f3add6cb.png',
    'fff10d3ca7024635a4f8e9bb512ca137.png'
  );
"

  if [[ ! -f "$ROOT_DIR/config/application-prod.yml" ]]; then
    return 0
  fi

  if ! grep -Eq '^[[:space:]]*uploadType:[[:space:]]*local([[:space:]]|$)' "$ROOT_DIR/config/application-prod.yml"; then
    return 0
  fi

  for attempt in 1 2 3 4 5 6 7 8 9 10 11 12; do
    if docker_compose exec -T mysql sh -c \
      "exec mysql --default-character-set=utf8mb4 -uroot -p\"\$MYSQL_ROOT_PASSWORD\" \"\$MYSQL_DATABASE\" -e \"$sql\"" \
      >/dev/null 2>&1; then
      return 0
    fi
    sleep 5
  done

  return 0
}

docker_pull_failure_needs_ipv4_retry() {
  local log_file="$1"

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

  echo "检测到 Docker Hub 拉取疑似走 IPv6 被重置，正在自动切换为优先 IPv4 并重试..."
  "${SUDO[@]}" env NONINTERACTIVE=yes PREFER_IPV4=yes bash "$ROOT_DIR/configure-docker-mirror.sh"
}

docker_compose_pull_with_retry() {
  local pull_log
  local attempt

  pull_log="$(mktemp)"

  if docker_compose pull >"$pull_log" 2>&1; then
    cat "$pull_log"
    rm -f "$pull_log"
    return 0
  fi

  if docker_pull_failure_needs_ipv4_retry "$pull_log"; then
    echo
    echo "首次拉取镜像失败，正在自动切换 IPv4 并重试..."
    configure_docker_ipv4_retry || true
    if docker_compose pull >"$pull_log" 2>&1; then
      echo "镜像拉取已恢复，前面的网络错误已自动处理。"
      cat "$pull_log"
      rm -f "$pull_log"
      return 0
    fi
  fi

  for attempt in 1 2 3; do
    if ! grep -Eiq 'TLS handshake timeout|i/o timeout|connection reset by peer|read: connection reset' "$pull_log"; then
      break
    fi
    echo
    echo "网络仍不稳定，20 秒后进行第 ${attempt}/3 次重试..."
    sleep 20
    if docker_compose pull >"$pull_log" 2>&1; then
      echo "镜像拉取已恢复，前面的网络错误已自动处理。"
      cat "$pull_log"
      rm -f "$pull_log"
      return 0
    fi
  done

  cat "$pull_log"
  rm -f "$pull_log"
  return 1
}
