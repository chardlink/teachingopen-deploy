#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ ${EUID:-0} -eq 0 ]]; then
  SUDO=()
else
  SUDO=(sudo)
fi

need_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    return 1
  fi
}

prompt_yes_no() {
  local prompt="$1"
  local default="${2:-Y}"
  local suffix reply normalized

  if [[ "$default" == "Y" ]]; then
    suffix="[Y/n]"
  else
    suffix="[y/N]"
  fi

  while true; do
    read -r -p "$prompt $suffix " reply
    reply="${reply:-$default}"
    normalized="$(printf '%s' "$reply" | tr '[:upper:]' '[:lower:]')"
    case "$normalized" in
      y|yes) return 0 ;;
      n|no) return 1 ;;
    esac
    echo "请输入 y 或 n。"
  done
}

prompt_with_default() {
  local prompt="$1"
  local default="$2"
  local reply

  read -r -p "$prompt [$default]: " reply
  printf '%s' "${reply:-$default}"
}

validate_port() {
  local port="$1"
  [[ "$port" =~ ^[0-9]+$ ]] && (( port >= 1 && port <= 65535 ))
}

prompt_port() {
  local label="$1"
  local default="$2"
  local value

  while true; do
    value="$(prompt_with_default "请输入 $label" "$default")"
    if validate_port "$value"; then
      printf '%s' "$value"
      return 0
    fi
    echo "$label 必须是 1 到 65535 之间的整数。"
  done
}

find_editor() {
  if [[ -n "${EDITOR:-}" ]] && command -v "${EDITOR}" >/dev/null 2>&1; then
    printf '%s' "${EDITOR}"
    return 0
  fi

  for editor in nano vim vi; do
    if command -v "$editor" >/dev/null 2>&1; then
      printf '%s' "$editor"
      return 0
    fi
  done

  return 1
}

edit_env_file() {
  local env_file="$1"
  local editor

  if editor="$(find_editor)"; then
    echo
    echo "正在使用 $editor 打开 $env_file"
    "$editor" "$env_file"
  else
    echo
    echo "未找到可用的文本编辑器。"
    echo "请在另一个终端里手动修改 $env_file，完成后按回车继续。"
    read -r
  fi
}

write_env_file() {
  local env_file="$1"
  local web_port="$2"
  local app_debug_port="$3"
  local public_base_url="$4"

  cat > "$env_file" <<EOF
TZ=Asia/Shanghai
WEB_PORT=${web_port}
APP_DEBUG_PORT=${app_debug_port}
PUBLIC_BASE_URL=${public_base_url}
MYSQL_ROOT_PASSWORD=$(rand_hex)
MYSQL_DATABASE=teachingopen
MYSQL_USER=teachingopen
MYSQL_PASSWORD=$(rand_hex)
REDIS_PASSWORD=$(rand_hex)
JAVA_OPTS="-Xms512m -Xmx2048m -Dfile.encoding=UTF-8"
EOF
}

load_env_file() {
  local env_file="$1"
  set -a
  # shellcheck disable=SC1090
  source "$env_file"
  set +a
}

show_env_summary() {
  local env_file="$1"

  load_env_file "$env_file"

  echo
  echo "当前部署配置："
  echo "  WEB_PORT=$WEB_PORT"
  echo "  APP_DEBUG_PORT=$APP_DEBUG_PORT"
  echo "  PUBLIC_BASE_URL=$PUBLIC_BASE_URL"
}

rand_hex() {
  if need_cmd openssl; then
    openssl rand -hex 12
  else
    date +%s%N | sha256sum | awk '{print substr($1, 1, 24)}'
  fi
}

ensure_base_packages() {
  "${SUDO[@]}" apt-get update
  "${SUDO[@]}" apt-get install -y ca-certificates curl unzip
}

ensure_docker() {
  if ! need_cmd docker; then
    curl -fsSL https://get.docker.com | "${SUDO[@]}" sh
  fi

  if ! "${SUDO[@]}" docker compose version >/dev/null 2>&1; then
    "${SUDO[@]}" apt-get update
    "${SUDO[@]}" apt-get install -y docker-compose-plugin
  fi

  "${SUDO[@]}" systemctl enable --now docker
}

prepare_env_file() {
  local env_file="$ROOT_DIR/.env"
  local default_web_port="8080"
  local default_app_debug_port="18080"
  local ip_addr
  local default_public_base_url
  local web_port
  local app_debug_port
  local public_base_url

  ip_addr="$(hostname -I 2>/dev/null | awk '{print $1}')"
  ip_addr="${ip_addr:-127.0.0.1}"
  default_public_base_url="http://${ip_addr}:${default_web_port}"

  if [[ -f "$env_file" ]]; then
    echo
    echo "检测到已存在的 .env 文件：$env_file"
    show_env_summary "$env_file"
    if prompt_yes_no "部署前是否先手动修改 .env？" N; then
      edit_env_file "$env_file"
      show_env_summary "$env_file"
    fi
    return 0
  fi

  echo
  echo "未检测到 .env 文件，将自动创建。"
  echo "默认值如下："
  echo "  WEB_PORT=$default_web_port"
  echo "  APP_DEBUG_PORT=$default_app_debug_port"
  echo "  PUBLIC_BASE_URL=$default_public_base_url"

  if prompt_yes_no "是否使用以上默认值？" Y; then
    web_port="$default_web_port"
    app_debug_port="$default_app_debug_port"
    public_base_url="$default_public_base_url"
  else
    web_port="$(prompt_port "WEB_PORT" "$default_web_port")"
    app_debug_port="$(prompt_port "APP_DEBUG_PORT" "$default_app_debug_port")"
    public_base_url="$(prompt_with_default "请输入 PUBLIC_BASE_URL" "http://${ip_addr}:${web_port}")"
  fi

  write_env_file "$env_file" "$web_port" "$app_debug_port" "$public_base_url"

  echo
  echo "已创建 .env 文件：$env_file"
  show_env_summary "$env_file"

  if prompt_yes_no "启动部署前，是否现在手动打开 .env 再修改一次？" N; then
    edit_env_file "$env_file"
    show_env_summary "$env_file"
  fi
}

prepare_directories() {
  mkdir -p \
    "$ROOT_DIR/data/mysql" \
    "$ROOT_DIR/data/redis" \
    "$ROOT_DIR/data/uploads" \
    "$ROOT_DIR/data/webapp" \
    "$ROOT_DIR/data/logs" \
    "$ROOT_DIR/data/kkfileview" \
    "$ROOT_DIR/runtime/web-root"
}

start_stack() {
  (
    cd "$ROOT_DIR"
    "${SUDO[@]}" docker compose pull
    "${SUDO[@]}" docker compose up -d
  )
}

main() {
  ensure_base_packages
  ensure_docker
  prepare_env_file
  prepare_directories
  echo
  if ! prompt_yes_no "配置已准备完成，是否现在开始部署并启动容器？" Y; then
    echo "已取消本次启动。"
    echo "你可以先修改 $ROOT_DIR/.env，之后再手动执行 ./start.sh。"
    exit 0
  fi
  bash "$ROOT_DIR/scripts/prepare-web.sh"
  start_stack

  echo
  echo "TeachingOpen 本地部署已启动。"
  echo "第一次初始化可能需要几分钟。"
  echo
  echo "查看状态："
  echo "  cd $ROOT_DIR && ./status.sh"
  echo
  echo "查看日志："
  echo "  cd $ROOT_DIR && ./logs.sh"
  echo
  echo "访问地址："
  echo "  读取 $ROOT_DIR/.env 里的 PUBLIC_BASE_URL"
}

main "$@"
