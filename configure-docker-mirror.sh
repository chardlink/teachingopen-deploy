#!/usr/bin/env bash
set -euo pipefail

if [[ ${EUID:-0} -eq 0 ]]; then
  SUDO=()
else
  SUDO=(sudo)
fi

prompt_with_default() {
  local prompt="$1"
  local default="$2"
  local reply

  read -r -p "$prompt [$default]: " reply
  printf '%s' "${reply:-$default}"
}

prompt_optional() {
  local prompt="$1"
  local reply

  read -r -p "$prompt " reply
  printf '%s' "$reply"
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

trim() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

apply_prefer_ipv4() {
  local gai_file="/etc/gai.conf"
  local backup_file=""

  "${SUDO[@]}" touch "$gai_file"
  backup_file="${gai_file}.bak.$(date +%Y%m%d-%H%M%S)"
  "${SUDO[@]}" cp "$gai_file" "$backup_file"

  if "${SUDO[@]}" grep -Eq '^[[:space:]]*precedence[[:space:]]+::ffff:0:0/96[[:space:]]+100' "$gai_file"; then
    echo "已检测到 /etc/gai.conf 中存在 IPv4 优先规则。"
    return 0
  fi

  if "${SUDO[@]}" grep -Eq '^[[:space:]]*#[[:space:]]*precedence[[:space:]]+::ffff:0:0/96[[:space:]]+100' "$gai_file"; then
    "${SUDO[@]}" sed -i 's/^[[:space:]]*#[[:space:]]*precedence[[:space:]]\+::ffff:0:0\/96[[:space:]]\+100/precedence ::ffff:0:0\/96 100/' "$gai_file"
  else
    printf '\nprecedence ::ffff:0:0/96 100\n' | "${SUDO[@]}" tee -a "$gai_file" >/dev/null
  fi

  echo "已写入 IPv4 优先规则到 $gai_file"
  echo "备份文件：$backup_file"
}

main() {
  local daemon_dir="/etc/docker"
  local daemon_file="$daemon_dir/daemon.json"
  local backup_file=""
  local mirrors_raw="${REGISTRY_MIRRORS:-}"
  local http_proxy_value="${DOCKER_HTTP_PROXY:-}"
  local https_proxy_value="${DOCKER_HTTPS_PROXY:-}"
  local no_proxy_value="${DOCKER_NO_PROXY:-}"
  local prefer_ipv4_value="${PREFER_IPV4:-}"
  local old_ifs
  local item
  local first
  local has_mirrors=0
  local has_proxy=0
  local use_ipv4_preference=0

  echo "这个脚本用于给 Docker daemon 配置镜像加速、代理，以及优先 IPv4。"
  echo "支持三种方式："
  echo "  1. 配置 registry-mirrors"
  echo "  2. 配置 Docker daemon 的 HTTP/HTTPS 代理"
  echo "  3. 遇到 Docker Hub IPv6 被重置时，切换为系统优先 IPv4"
  echo
  echo "也支持环境变量直接执行，例如："
  echo '  sudo REGISTRY_MIRRORS="https://你的加速地址" ./configure-docker-mirror.sh'
  echo '  sudo DOCKER_HTTP_PROXY="http://127.0.0.1:7890" DOCKER_HTTPS_PROXY="http://127.0.0.1:7890" ./configure-docker-mirror.sh'
  echo '  sudo PREFER_IPV4=yes ./configure-docker-mirror.sh'
  echo

  if [[ -z "$mirrors_raw" ]]; then
    mirrors_raw="$(prompt_optional "请输入 registry mirror 地址，多个用英文逗号分隔；如果暂时不配镜像加速，直接回车跳过：")"
  fi

  if [[ -z "$http_proxy_value" ]]; then
    http_proxy_value="$(prompt_optional "如需给 Docker daemon 配置 HTTP 代理，请输入地址；否则直接回车跳过：")"
  fi

  if [[ -z "$https_proxy_value" ]]; then
    if [[ -n "$http_proxy_value" ]]; then
      https_proxy_value="$(prompt_with_default "如需给 Docker daemon 配置 HTTPS 代理，请输入地址" "$http_proxy_value")"
    else
      https_proxy_value="$(prompt_optional "如需给 Docker daemon 配置 HTTPS 代理，请输入地址；否则直接回车跳过：")"
    fi
  fi

  if [[ -z "$no_proxy_value" ]]; then
    no_proxy_value="$(prompt_optional "如需设置 NO_PROXY，请输入逗号分隔地址；否则直接回车跳过：")"
  fi

  if [[ -z "$prefer_ipv4_value" ]]; then
    if prompt_yes_no "是否启用系统优先 IPv4（建议当前这种 Docker Hub IPv6 被重置时开启）？" Y; then
      prefer_ipv4_value="yes"
    else
      prefer_ipv4_value="no"
    fi
  fi

  if [[ -n "$mirrors_raw" ]]; then
    has_mirrors=1
  fi

  if [[ -n "$http_proxy_value" || -n "$https_proxy_value" || -n "$no_proxy_value" ]]; then
    has_proxy=1
  fi

  case "$(printf '%s' "$prefer_ipv4_value" | tr '[:upper:]' '[:lower:]')" in
    y|yes|true|1|on)
      use_ipv4_preference=1
      ;;
  esac

  if [[ $has_mirrors -eq 0 && $has_proxy -eq 0 && $use_ipv4_preference -eq 0 ]]; then
    echo
    echo "你没有填写任何镜像加速、代理或 IPv4 优先配置。"
    echo "请重新执行并至少填写一项。"
    exit 1
  fi

  "${SUDO[@]}" mkdir -p "$daemon_dir"

  if [[ -f "$daemon_file" ]]; then
    backup_file="${daemon_file}.bak.$(date +%Y%m%d-%H%M%S)"
    "${SUDO[@]}" cp "$daemon_file" "$backup_file"
    echo "已备份现有 Docker 配置到：$backup_file"
  fi

  {
    echo "{"
    first=1

    if [[ $has_mirrors -eq 1 ]]; then
      echo '  "registry-mirrors": ['
      old_ifs="$IFS"
      IFS=','
      first=1
      for item in $mirrors_raw; do
        item="$(trim "$item")"
        [[ -z "$item" ]] && continue
        if [[ $first -eq 0 ]]; then
          echo ","
        fi
        printf '    "%s"' "$item"
        first=0
      done
      IFS="$old_ifs"
      echo
      echo -n "  ]"
      first=0
    fi

    if [[ $has_proxy -eq 1 ]]; then
      if [[ $first -eq 0 ]]; then
        echo ","
      fi
      echo '  "proxies": {'
      local proxy_first=1
      if [[ -n "$http_proxy_value" ]]; then
        printf '    "http-proxy": "%s"' "$http_proxy_value"
        proxy_first=0
      fi
      if [[ -n "$https_proxy_value" ]]; then
        if [[ $proxy_first -eq 0 ]]; then
          echo ","
        fi
        printf '    "https-proxy": "%s"' "$https_proxy_value"
        proxy_first=0
      fi
      if [[ -n "$no_proxy_value" ]]; then
        if [[ $proxy_first -eq 0 ]]; then
          echo ","
        fi
        printf '    "no-proxy": "%s"' "$no_proxy_value"
      fi
      echo
      echo "  }"
    else
      echo
    fi
    echo "}"
  } | "${SUDO[@]}" tee "$daemon_file" >/dev/null

  echo
  echo "已写入 $daemon_file"

  if [[ $use_ipv4_preference -eq 1 ]]; then
    apply_prefer_ipv4
  fi

  echo "正在重启 Docker..."
  "${SUDO[@]}" systemctl restart docker
  "${SUDO[@]}" systemctl --no-pager --full status docker | sed -n '1,8p'

  echo
  echo "配置完成。"
  echo "现在请重新执行："
  echo "  cd /opt/teachingopen-source && sudo ./install.sh"
  echo
  echo "如果只是重试拉镜像，也可以执行："
  echo "  cd /opt/teachingopen-source && ./start.sh"
}

main "$@"
