#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck disable=SC1091
source "$ROOT_DIR/scripts/common.sh"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "未找到 $ENV_FILE"
  echo "请先执行 ./install.sh 完成首次部署。"
  exit 1
fi

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

load_env() {
  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a
}

parse_public_base_url() {
  local url="$1"
  local rest host_port

  PUBLIC_SCHEME="${url%%://*}"
  if [[ "$url" == "$PUBLIC_SCHEME" ]]; then
    PUBLIC_SCHEME="http"
    rest="$url"
  else
    rest="${url#*://}"
  fi

  PUBLIC_PATH=""
  if [[ "$rest" == */* ]]; then
    PUBLIC_PATH="/${rest#*/}"
    host_port="${rest%%/*}"
  else
    host_port="$rest"
  fi

  if [[ "$host_port" == *:* ]]; then
    PUBLIC_HOST="${host_port%:*}"
    PUBLIC_PORT="${host_port##*:}"
  else
    PUBLIC_HOST="$host_port"
    if [[ "$PUBLIC_SCHEME" == "https" ]]; then
      PUBLIC_PORT="443"
    else
      PUBLIC_PORT="80"
    fi
  fi
}

show_current_config() {
  load_env
  parse_public_base_url "$PUBLIC_BASE_URL"

  echo
  echo "当前配置："
  echo "  本机服务端口 WEB_PORT=$WEB_PORT"
  echo "  本机调试端口 APP_DEBUG_PORT=$APP_DEBUG_PORT"
  echo "  当前外网入口 PUBLIC_BASE_URL=$PUBLIC_BASE_URL"
  echo "  当前外网主机=$PUBLIC_HOST"
  echo "  当前外网端口=$PUBLIC_PORT"
}

set_env_value() {
  local key="$1"
  local value="$2"
  local tmp_file

  tmp_file="$(mktemp)"
  awk -v key="$key" -v value="$value" '
    BEGIN { done = 0 }
    index($0, key "=") == 1 {
      print key "=" value
      done = 1
      next
    }
    { print }
    END {
      if (!done) {
        print key "=" value
      }
    }
  ' "$ENV_FILE" > "$tmp_file"

  mv "$tmp_file" "$ENV_FILE"
}

main() {
  local new_web_port new_app_debug_port
  local new_public_scheme new_public_host new_public_port new_public_path
  local new_public_base_url

  show_current_config

  load_env
  parse_public_base_url "$PUBLIC_BASE_URL"

  echo
  echo "开始修改访问配置。直接按回车可保留当前值。"

  new_web_port="$(prompt_port "本机服务端口 WEB_PORT" "$WEB_PORT")"
  new_app_debug_port="$(prompt_port "本机调试端口 APP_DEBUG_PORT" "$APP_DEBUG_PORT")"
  new_public_scheme="$(prompt_with_default "请输入外网入口协议 (http 或 https)" "$PUBLIC_SCHEME")"
  new_public_scheme="${new_public_scheme%://}"
  new_public_host="$(prompt_with_default "请输入外网入口主机/IP/域名" "$PUBLIC_HOST")"
  new_public_port="$(prompt_port "外网入口端口" "$PUBLIC_PORT")"
  new_public_path="$PUBLIC_PATH"

  new_public_base_url="${new_public_scheme}://${new_public_host}:${new_public_port}${new_public_path}"

  echo
  echo "新配置将改为："
  echo "  WEB_PORT=$new_web_port"
  echo "  APP_DEBUG_PORT=$new_app_debug_port"
  echo "  PUBLIC_BASE_URL=$new_public_base_url"
  echo

  if ! prompt_yes_no "是否写入 .env 并自动重启服务？" Y; then
    echo "已取消修改。"
    exit 0
  fi

  set_env_value "WEB_PORT" "$new_web_port"
  set_env_value "APP_DEBUG_PORT" "$new_app_debug_port"
  set_env_value "PUBLIC_BASE_URL" "$new_public_base_url"

  echo
  echo "已写入 $ENV_FILE"
  echo "正在停止服务..."
  bash "$ROOT_DIR/stop.sh"
  echo "正在重新启动服务..."
  bash "$ROOT_DIR/start.sh"

  echo
  echo "修改完成。当前入口地址："
  echo "  $new_public_base_url"
  echo
  echo "如有路由器端口映射，请记得同步修改外网映射规则。"
}

main "$@"
