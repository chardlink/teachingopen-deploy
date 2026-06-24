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

trim() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

main() {
  local daemon_dir="/etc/docker"
  local daemon_file="$daemon_dir/daemon.json"
  local backup_file=""
  local mirrors_raw
  local old_ifs
  local item
  local first=1

  echo "这个脚本用于给 Docker daemon 配置 registry mirror。"
  echo "请粘贴一个或多个可用镜像加速地址，多个地址用英文逗号分隔。"
  echo

  mirrors_raw="$(prompt_with_default "请输入 registry mirror 地址" "https://example-mirror-1,https://example-mirror-2")"

  if [[ "$mirrors_raw" == "https://example-mirror-1,https://example-mirror-2" ]]; then
    echo
    echo "你还没有填写真实 mirror 地址。"
    echo "请重新执行并填入你自己的 Docker 镜像加速地址。"
    exit 1
  fi

  "${SUDO[@]}" mkdir -p "$daemon_dir"

  if [[ -f "$daemon_file" ]]; then
    backup_file="${daemon_file}.bak.$(date +%Y%m%d-%H%M%S)"
    "${SUDO[@]}" cp "$daemon_file" "$backup_file"
    echo "已备份现有配置到：$backup_file"
  fi

  {
    echo "{"
    echo '  "registry-mirrors": ['
    old_ifs="$IFS"
    IFS=','
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
    echo "  ]"
    echo "}"
  } | "${SUDO[@]}" tee "$daemon_file" >/dev/null

  echo
  echo "已写入 $daemon_file"
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
