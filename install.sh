#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ ${EUID:-0} -eq 0 ]]; then
  SUDO=()
else
  SUDO=(sudo)
fi

need_cmd() {
  command -v "$1" >/dev/null 2>&1
}

log() {
  echo "$*"
}

warn() {
  echo "$*" >&2
}

retry() {
  local attempts="$1"
  local delay_seconds="$2"
  shift 2

  local attempt=1
  while true; do
    if "$@"; then
      return 0
    fi

    if (( attempt >= attempts )); then
      return 1
    fi

    warn "命令执行失败，${delay_seconds} 秒后重试（${attempt}/${attempts}）..."
    sleep "$delay_seconds"
    attempt=$((attempt + 1))
  done
}

apt_update() {
  if retry 3 5 "${SUDO[@]}" apt-get update; then
    return 0
  fi

  if [[ -f /etc/apt/sources.list.d/docker.list ]]; then
    warn "apt-get update 失败，尝试移除残留的 Docker CE 软件源后重试。"
    cleanup_official_docker_repo
    retry 3 5 "${SUDO[@]}" apt-get update
    return 0
  fi

  return 1
}

apt_install() {
  retry 3 5 "${SUDO[@]}" apt-get install -y "$@"
}

apt_install_once() {
  "${SUDO[@]}" apt-get install -y "$@"
}

curl_download() {
  local url="$1"
  local output_file="$2"
  retry 3 5 curl -4 -fsSL "$url" -o "$output_file"
}

apt_has_install_candidate() {
  local package_name="$1"
  "${SUDO[@]}" env LC_ALL=C apt-cache show "$package_name" 2>/dev/null | grep -q '^Package: '
}

ensure_universe_repository() {
  local version_codename

  if [[ ! -r /etc/os-release ]]; then
    return 0
  fi

  # shellcheck disable=SC1091
  source /etc/os-release
  version_codename="${VERSION_CODENAME:-}"

  if [[ -z "$version_codename" || "${ID:-}" != "ubuntu" ]]; then
    return 0
  fi

  if grep -Rhs "^[^#].* ${version_codename} .*universe" /etc/apt/sources.list /etc/apt/sources.list.d/*.list >/dev/null 2>&1; then
    return 0
  fi

  log "未检测到 Ubuntu universe 软件源，正在自动启用..."
  apt_install software-properties-common
  "${SUDO[@]}" add-apt-repository -y universe
  apt_update
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
    prompt_read reply "$prompt $suffix "
    reply="${reply:-$default}"
    normalized="$(printf '%s' "$reply" | tr '[:upper:]' '[:lower:]')"
    case "$normalized" in
      y|yes) return 0 ;;
      n|no) return 1 ;;
    esac
    echo "请输入 y 或 n。"
  done
}

offer_post_deploy_reconfigure() {
  local reply

  echo
  echo "鍚庣画鎿嶄綔锛"
  echo "  1. 绔嬪嵆閰嶇疆 WEB_PORT / APP_DEBUG_PORT / PUBLIC_BASE_URL"
  echo "  2. 鐩存帴閫€鍑?"

  while true; do
    read -r -p "璇烽€夋嫨 [1/2锛岄粯璁?2]: " reply
    reply="${reply:-2}"
    case "$reply" in
      1)
        bash "$ROOT_DIR/reconfigure.sh"
        return 0
        ;;
      2)
        return 0
        ;;
    esac
    echo "璇疯緭鍏?1 鎴?2銆?"
  done
}

offer_post_deploy_reconfigure() {
  local reply

  echo
  echo "后续操作："
  echo "  1. 立即配置端口和 PUBLIC_BASE_URL"
  echo "  2. 直接退出"

  while true; do
    read -r -p "请选择 [1/2，默认 2]: " reply
    reply="${reply:-2}"
    case "$reply" in
      1)
        bash "$ROOT_DIR/reconfigure.sh"
        return 0
        ;;
      2)
        return 0
        ;;
    esac
    echo "请输入 1 或 2。"
  done
}

prompt_with_default() {
  local prompt="$1"
  local default="$2"
  local reply

  prompt_read reply "$prompt [$default]: "
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
    value="$(prompt_with_default "请输入 ${label}" "$default")"
    if validate_port "$value"; then
      printf '%s' "$value"
      return 0
    fi
    echo "${label} 必须是 1 到 65535 之间的整数。"
  done
}

set_env_value() {
  local key="$1"
  local value="$2"
  local env_file="$3"
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
  ' "$env_file" > "$tmp_file"

  mv "$tmp_file" "$env_file"
}

interactive_modify_ports() {
  local env_file="$1"
  local cur_web_port cur_app_debug_port cur_public_base_url
  local new_web_port new_app_debug_port new_public_base_url
  local ip_addr

  load_env_file "$env_file"
  cur_web_port="${WEB_PORT:-1168}"
  cur_app_debug_port="${APP_DEBUG_PORT:-18080}"
  cur_public_base_url="${PUBLIC_BASE_URL:-}"

  echo
  echo "请输入新的端口值，直接按回车保留当前值。"

  new_web_port="$(prompt_port "WEB_PORT" "$cur_web_port")"
  new_app_debug_port="$(prompt_port "APP_DEBUG_PORT" "$cur_app_debug_port")"

  # 自动根据新的 WEB_PORT 重新计算 PUBLIC_BASE_URL 的默认值
  ip_addr="$(hostname -I 2>/dev/null | awk '{print $1}')"
  ip_addr="${ip_addr:-127.0.0.1}"
  if [[ -n "$cur_public_base_url" ]]; then
    # 把旧 URL 中的端口替换为新端口
    new_public_base_url="$(echo "$cur_public_base_url" | sed "s/:${cur_web_port}/:${new_web_port}/")"
  else
    new_public_base_url="http://${ip_addr}:${new_web_port}"
  fi
  new_public_base_url="$(prompt_with_default "请输入 PUBLIC_BASE_URL" "$new_public_base_url")"

  set_env_value "WEB_PORT" "$new_web_port" "$env_file"
  set_env_value "APP_DEBUG_PORT" "$new_app_debug_port" "$env_file"
  set_env_value "PUBLIC_BASE_URL" "$new_public_base_url" "$env_file"

  echo
  echo "端口已更新完成。"
}

rand_hex() {
  if need_cmd openssl; then
    openssl rand -hex 12
  else
    date +%s%N | sha256sum | awk '{print substr($1, 1, 24)}'
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

show_access_entry() {
  local env_file="$ROOT_DIR/.env"

  if [[ ! -f "$env_file" ]]; then
    return 0
  fi

  load_env_file "$env_file"
  echo "当前访问地址："
  echo "  $PUBLIC_BASE_URL"
}

docker_compose_available() {
  if need_cmd docker && "${SUDO[@]}" docker compose version >/dev/null 2>&1; then
    return 0
  fi

  need_cmd docker-compose
}

docker_compose_cmd() {
  if need_cmd docker && "${SUDO[@]}" docker compose version >/dev/null 2>&1; then
    "${SUDO[@]}" docker compose "$@"
    return 0
  fi

  if need_cmd docker-compose; then
    "${SUDO[@]}" docker-compose "$@"
    return 0
  fi

  warn "未检测到 docker compose 或 docker-compose。"
  return 1
}

cleanup_official_docker_repo() {
  "${SUDO[@]}" rm -f /etc/apt/sources.list.d/docker.list
  "${SUDO[@]}" rm -f /etc/apt/keyrings/docker.asc
}

install_docker_from_official_repo() {
  local arch version_codename temp_keyring

  if [[ ! -r /etc/os-release ]]; then
    return 1
  fi

  # shellcheck disable=SC1091
  source /etc/os-release

  if [[ "${ID:-}" != "ubuntu" ]]; then
    return 1
  fi

  arch="$(dpkg --print-architecture)"
  version_codename="${VERSION_CODENAME:-}"
  if [[ -z "$version_codename" ]]; then
    return 1
  fi

  log "Ubuntu 软件源安装 Docker 失败，正在尝试清华 TUNA 的 Docker CE 软件源..."
  "${SUDO[@]}" install -m 0755 -d /etc/apt/keyrings
  temp_keyring="$(mktemp)"
  curl_download "https://download.docker.com/linux/ubuntu/gpg" "$temp_keyring"
  "${SUDO[@]}" mv "$temp_keyring" /etc/apt/keyrings/docker.asc
  "${SUDO[@]}" chmod a+r /etc/apt/keyrings/docker.asc

  printf 'deb [arch=%s signed-by=/etc/apt/keyrings/docker.asc] https://mirrors.tuna.tsinghua.edu.cn/docker-ce/linux/ubuntu %s stable\n' \
    "$arch" "$version_codename" | "${SUDO[@]}" tee /etc/apt/sources.list.d/docker.list >/dev/null

  apt_update

  if ! apt_has_install_candidate docker-ce; then
    return 1
  fi

  apt_install_once docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
}

install_docker_from_ubuntu_repo() {
  local compose_package=""

  log "正在优先通过 Ubuntu 软件源安装 Docker..."
  cleanup_official_docker_repo
  ensure_universe_repository
  apt_update

  if ! apt_has_install_candidate docker.io; then
    return 1
  fi

  if apt_has_install_candidate docker-compose-plugin; then
    compose_package="docker-compose-plugin"
  elif apt_has_install_candidate docker-compose-v2; then
    compose_package="docker-compose-v2"
  elif apt_has_install_candidate docker-compose; then
    compose_package="docker-compose"
  fi

  if [[ -n "$compose_package" ]]; then
    apt_install_once docker.io "$compose_package"
  else
    apt_install_once docker.io
  fi
}

ensure_compose() {
  if docker_compose_available; then
    return 0
  fi

  log "Docker Compose 尚未就绪，开始补装..."
  ensure_universe_repository
  apt_update

  if apt_has_install_candidate docker-compose-plugin && apt_install_once docker-compose-plugin; then
    return 0
  fi

  if apt_has_install_candidate docker-compose-v2 && apt_install_once docker-compose-v2; then
    return 0
  fi

  if apt_has_install_candidate docker-compose && apt_install_once docker-compose; then
    return 0
  fi

  return 1
}

ensure_base_packages() {
  apt_update
  apt_install ca-certificates curl python3
}

ensure_docker() {
  if ! need_cmd docker; then
    if install_docker_from_ubuntu_repo; then
      log "Docker 已通过 Ubuntu 软件源安装完成。"
    elif install_docker_from_official_repo; then
      log "Docker 已通过清华 TUNA 的 Docker CE 软件源安装完成。"
    else
      warn "Ubuntu 软件源和清华 TUNA 的 Docker CE 软件源都没有安装成功。"
      warn "请先检查 Ubuntu 软件源、universe 仓库以及 mirrors.tuna.tsinghua.edu.cn 的连通性。"
      exit 1
    fi
  else
    log "已检测到现有 Docker，跳过安装。"
  fi

  "${SUDO[@]}" systemctl enable --now docker

  if ! ensure_compose; then
    warn "Docker 已安装，但 Docker Compose 仍不可用。"
    warn "请检查当前 Ubuntu 软件源是否可正常提供 docker-compose 相关软件包。"
    exit 1
  fi

  if need_cmd docker && "${SUDO[@]}" docker compose version >/dev/null 2>&1; then
    log "已检测到 docker compose 插件。"
  elif need_cmd docker-compose; then
    log "已检测到 docker-compose 独立命令。"
  fi
}

prepare_env_file() {
  local env_file="$ROOT_DIR/.env"
  local default_web_port="1168"
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
    if prompt_yes_no "部署前是否修改端口配置？" N; then
      interactive_modify_ports "$env_file"
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

  if prompt_yes_no "启动部署前，是否修改端口配置？" N; then
    interactive_modify_ports "$env_file"
    show_env_summary "$env_file"
  fi
}

prepare_directories() {
  mkdir -p \
    "$ROOT_DIR/data/mysql" \
    "$ROOT_DIR/data/redis" \
    "$ROOT_DIR/data/uploads" \
    "$ROOT_DIR/data/uploads/internalapi/asset" \
    "$ROOT_DIR/data/webapp" \
    "$ROOT_DIR/data/logs" \
    "$ROOT_DIR/data/kkfileview" \
    "$ROOT_DIR/runtime/web-root"
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
    warn "未找到 $ROOT_DIR/configure-docker-mirror.sh，无法自动切换 IPv4。"
    return 1
  fi

  echo "检测到 Docker Hub 拉取疑似走 IPv6 被重置，正在自动切换为优先 IPv4 并重试一次..."
  "${SUDO[@]}" env NONINTERACTIVE=yes PREFER_IPV4=yes bash "$ROOT_DIR/configure-docker-mirror.sh"
}

start_stack() {
  local pull_log attempt

  cd "$ROOT_DIR"
  pull_log="$(mktemp)"

  echo "正在拉取最新容器镜像，首次可能需要几分钟，请耐心等待..."
  if docker_compose_cmd pull 2>&1 | tee "$pull_log"; then
    rm -f "$pull_log"
    SKIP_PREPARE=yes bash "$ROOT_DIR/start.sh"
    return 0
  fi

  # IPv6/网络问题：先尝试切换 IPv4
  if docker_pull_failure_needs_ipv4_retry "$pull_log"; then
    echo
    echo "首次拉取镜像失败，正在自动切换 IPv4 并重试..."
    configure_docker_ipv4_retry || true
    echo "正在拉取最新容器镜像，首次可能需要几分钟，请耐心等待..."
    if docker_compose_cmd pull 2>&1 | tee "$pull_log"; then
      echo "镜像拉取已恢复，前面的网络错误已自动处理。"
      rm -f "$pull_log"
      SKIP_PREPARE=yes bash "$ROOT_DIR/start.sh"
      return 0
    fi
  fi

  # 网络超时/不稳定：额外重试 3 次，每次等待 20 秒
  for attempt in 1 2 3; do
    if ! grep -Eiq 'TLS handshake timeout|i/o timeout|connection reset by peer|read: connection reset' "$pull_log"; then
      break
    fi
    echo
    echo "网络不稳定（超时/重置），20 秒后第 ${attempt}/3 次重试..."
    sleep 20
    echo "正在拉取最新容器镜像，首次可能需要几分钟，请耐心等待..."
    if docker_compose_cmd pull 2>&1 | tee "$pull_log"; then
      echo "镜像拉取已恢复，前面的网络错误已自动处理。"
      rm -f "$pull_log"
      SKIP_PREPARE=yes bash "$ROOT_DIR/start.sh"
      return 0
    fi
  done

  cat "$pull_log"
  rm -f "$pull_log"

  echo
  echo "镜像拉取失败，部署已中断。"
  echo "常见原因及解决方法："
  echo
  echo "  情况 A：Docker 走 IPv6 访问 Docker Hub 导致连接被重置"
  echo "    症状：错误含 'connection reset by peer' 或 'read tcp.*2600:'"
  echo "    解决：脚本已尝试自动切换 IPv4（写入 /etc/hosts），请重新执行："
  echo "      cd $ROOT_DIR && sudo PREFER_IPV4=yes ./configure-docker-mirror.sh"
  echo "      cd $ROOT_DIR && sudo ./install.sh"
  echo
  echo "  情况 B：当前网络完全无法访问 Docker Hub（IPv4/IPv6 均被屏蔽）"
  echo "    症状：自动重试后仍 connection reset 或 i/o timeout"
  echo "    解决：为 Docker daemon 配置 HTTP 代理后重试："
  echo "      sudo DOCKER_HTTP_PROXY=http://127.0.0.1:7890 \\"
  echo "           DOCKER_HTTPS_PROXY=http://127.0.0.1:7890 \\"
  echo "           ./configure-docker-mirror.sh"
  echo "      cd $ROOT_DIR && sudo ./install.sh"
  echo
  echo "  情况 C：镜像加速站返回 403 Forbidden（加速站不支持私有镜像）"
  echo "    解决：请勿在 .env 中为 MYSQL_IMAGE/APP_IMAGE/WEB_IMAGE 设置 daocloud 前缀。"
  return 1
}

prepare_ipv4_preference() {
  # 如果系统 IPv6 已禁用则跳过（幂等）
  if [[ "$(cat /proc/sys/net/ipv6/conf/all/disable_ipv6 2>/dev/null)" == "1" ]]; then
    log "系统 IPv6 已禁用，跳过网络预配置。"
    return 0
  fi

  if [[ ! -f "$ROOT_DIR/configure-docker-mirror.sh" ]]; then
    return 0
  fi

  echo
  echo "检测到系统 IPv6 尚未禁用。"
  echo "正在预先禁用 IPv6 并配置 /etc/hosts，避免 Docker 走 IPv6 连接 Docker Hub 被重置..."
  "${SUDO[@]}" env NONINTERACTIVE=yes PREFER_IPV4=yes bash "$ROOT_DIR/configure-docker-mirror.sh"
}

prompt_read() {
  local __var_name="$1"
  local __prompt="$2"

  if [[ -r /dev/tty ]]; then
    read -r -p "$__prompt" "$__var_name" < /dev/tty
  else
    read -r -p "$__prompt" "$__var_name"
  fi
}

wait_for_enter() {
  if [[ -r /dev/tty ]]; then
    read -r < /dev/tty
  else
    read -r
  fi
}

offer_post_deploy_reconfigure() {
  local reply

  echo
  echo "后续操作："
  echo "  1. 立即配置端口和 PUBLIC_BASE_URL"
  echo "  2. 直接退出"

  while true; do
    prompt_read reply "请选择 [1/2，默认 2]: "
    reply="${reply:-2}"
    case "$reply" in
      1)
        bash "$ROOT_DIR/reconfigure.sh"
        return 0
        ;;
      2)
        return 0
        ;;
    esac
    echo "请输入 1 或 2。"
  done
}

main() {
  ensure_base_packages
  ensure_docker
  prepare_env_file
  prepare_directories

  echo
  echo "当前 Ubuntu 模式是 Docker 容器化部署，不是宿主机原生安装。"
  echo "这样做的目的是尽量不碰你宿主机现有的 MySQL、Redis 和 HUSTOJ 数据目录。"
  echo

  if ! prompt_yes_no "配置已准备完成，是否现在开始部署并启动容器？" Y; then
    echo "已取消本次启动。"
    echo "你可以先修改 $ROOT_DIR/.env，之后再手动执行 ./start.sh。"
    exit 0
  fi

  bash "$ROOT_DIR/scripts/prepare-web.sh"
  prepare_ipv4_preference
  start_stack

  echo
  echo "TeachingOpen 本地部署已启动。"
  echo "第一次初始化可能需要几分钟。"
  echo
  show_access_entry
  echo
  echo "查看状态："
  echo "  cd $ROOT_DIR && ./status.sh"
  echo
  echo "查看日志："
  echo "  cd $ROOT_DIR && ./logs.sh"
  echo
  offer_post_deploy_reconfigure
}

prepare_env_file() {
  local env_file="$ROOT_DIR/.env"
  local default_web_port="1168"
  local default_app_debug_port="18080"
  local ip_addr
  local default_public_base_url

  ip_addr="$(hostname -I 2>/dev/null | awk '{print $1}')"
  ip_addr="${ip_addr:-127.0.0.1}"
  default_public_base_url="http://${ip_addr}:${default_web_port}"

  if [[ -f "$env_file" ]]; then
    echo
    echo "检测到已存在的 .env 文件：$env_file"
    show_env_summary "$env_file"
    echo "如需修改端口或 PUBLIC_BASE_URL，请在部署完成后选择 1 进行配置。"
    return 0
  fi

  echo
  echo "未检测到 .env 文件，将自动创建。"
  echo "默认值如下："
  echo "  WEB_PORT=$default_web_port"
  echo "  APP_DEBUG_PORT=$default_app_debug_port"
  echo "  PUBLIC_BASE_URL=$default_public_base_url"

  write_env_file "$env_file" "$default_web_port" "$default_app_debug_port" "$default_public_base_url"

  echo
  echo "已创建 .env 文件：$env_file"
  show_env_summary "$env_file"
  echo "如需修改端口或 PUBLIC_BASE_URL，请在部署完成后选择 1 进行配置。"
}

main() {
  ensure_base_packages
  ensure_docker
  prepare_env_file
  prepare_directories

  echo
  echo "当前 Ubuntu 模式是 Docker 容器化部署，不是宿主机原生安装。"
  echo "这样做的目的是尽量不碰你宿主机现有的 MySQL、Redis 和 HUSTOJ 数据目录。"
  echo "配置已准备完成，正在开始部署并启动容器..."

  bash "$ROOT_DIR/scripts/prepare-web.sh"
  prepare_ipv4_preference
  start_stack

  echo
  echo "TeachingOpen 本地部署已启动。"
  echo "第一次初始化可能需要几分钟。"
  echo
  show_access_entry
  echo
  echo "查看状态："
  echo "  cd $ROOT_DIR && ./status.sh"
  echo
  echo "查看日志："
  echo "  cd $ROOT_DIR && ./logs.sh"
  echo
  offer_post_deploy_reconfigure
}

main "$@"
