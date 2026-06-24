#!/usr/bin/env bash
set -euo pipefail

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

ensure_git() {
  if ! need_cmd git; then
    "${SUDO[@]}" apt-get update
    "${SUDO[@]}" apt-get install -y git
  fi
}

ensure_git_lfs() {
  if need_cmd git-lfs; then
    return 0
  fi

  "${SUDO[@]}" apt-get update
  "${SUDO[@]}" apt-get install -y git-lfs
}

usage() {
  cat <<'EOF'
用法：
  ./bootstrap-from-github.sh <REPO_URL> [BRANCH] [TARGET_DIR] [PROJECT_SUBDIR]

也支持环境变量：
  REPO_URL         GitHub 仓库地址
  REPO_BRANCH      分支名，默认 main
  TARGET_DIR       在 Ubuntu 上拉取到的目录，默认 /opt/teachingopen-source
  PROJECT_SUBDIR   install.sh 所在子目录，默认 .

参数说明：
  REPO_URL        GitHub 仓库地址，例如 https://github.com/you/repo.git
  BRANCH          分支名，默认 main
  TARGET_DIR      在 Ubuntu 上拉取到的目录，默认 /opt/teachingopen-source
  PROJECT_SUBDIR  install.sh 所在子目录，默认 .

示例：
  ./bootstrap-from-github.sh https://github.com/you/repo.git main /opt/teachingopen-source .

公开仓库一键拉取示例：
  wget -O- https://raw.githubusercontent.com/you/repo/main/bootstrap-from-github.sh | \
    sudo bash -s -- https://github.com/you/repo.git main /opt/teachingopen-source .

私有仓库建议：
  先给服务器配置 GitHub SSH Key，然后使用 git@github.com:you/repo.git
EOF
}

REPO_URL="${1:-${REPO_URL:-}}"
BRANCH="${2:-${REPO_BRANCH:-main}}"
TARGET_DIR="${3:-${TARGET_DIR:-/opt/teachingopen-source}}"
PROJECT_SUBDIR="${4:-${PROJECT_SUBDIR:-.}}"

if [[ -z "$REPO_URL" ]]; then
  usage
  exit 1
fi

ensure_git
ensure_git_lfs

if [[ -d "$TARGET_DIR/.git" ]]; then
  echo "检测到已存在仓库，开始更新：$TARGET_DIR"
  "${SUDO[@]}" git -C "$TARGET_DIR" fetch --all --tags
  "${SUDO[@]}" git -C "$TARGET_DIR" checkout "$BRANCH"
  "${SUDO[@]}" git -C "$TARGET_DIR" pull --ff-only origin "$BRANCH"
else
  echo "开始克隆仓库：$REPO_URL"
  "${SUDO[@]}" git clone --branch "$BRANCH" "$REPO_URL" "$TARGET_DIR"
fi

"${SUDO[@]}" git -C "$TARGET_DIR" lfs install
"${SUDO[@]}" git -C "$TARGET_DIR" lfs pull

DEPLOY_DIR="$TARGET_DIR/$PROJECT_SUBDIR"

if [[ ! -d "$DEPLOY_DIR" ]]; then
  echo "未找到部署目录：$DEPLOY_DIR"
  exit 1
fi

if [[ ! -f "$DEPLOY_DIR/install.sh" ]]; then
  echo "未找到 $DEPLOY_DIR/install.sh"
  echo "请确认 PROJECT_SUBDIR 是否填写正确。"
  exit 1
fi

echo "进入部署目录：$DEPLOY_DIR"
cd "$DEPLOY_DIR"

chmod +x install.sh start.sh stop.sh logs.sh status.sh backup.sh reconfigure.sh configure-docker-mirror.sh bootstrap-from-github.sh scripts/*.sh

echo "开始执行一键部署..."
"${SUDO[@]}" ./install.sh
