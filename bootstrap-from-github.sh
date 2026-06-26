#!/usr/bin/env bash
set -euo pipefail

if [[ ${EUID:-0} -eq 0 ]]; then
  SUDO=()
else
  SUDO=(sudo)
fi

need_cmd() {
  command -v "$1" >/dev/null 2>&1
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

git_lfs_pull_quiet_warning() {
  local repo_dir="$1"
  local lfs_log

  lfs_log="$(mktemp)"
  if "${SUDO[@]}" git -C "$repo_dir" lfs pull >"$lfs_log" 2>&1; then
    grep -Fv 'appears to use backslashes as path separators' "$lfs_log" || true
    rm -f "$lfs_log"
    return 0
  fi

  cat "$lfs_log" >&2
  rm -f "$lfs_log"
  return 1
}

usage() {
  cat <<'EOF'
用法： ./bootstrap-from-github.sh <REPO_URL> [BRANCH] [TARGET_DIR] [PROJECT_SUBDIR]

也支持环境变量：
  REPO_URL         GitHub 仓库地址
  REPO_BRANCH      分支名，默认 main
  TARGET_DIR       Ubuntu 上的部署目录，默认 /opt/teachingopen-source
  PROJECT_SUBDIR   install.sh 所在子目录，默认 .

示例：
  ./bootstrap-from-github.sh https://github.com/you/repo.git main /opt/teachingopen-source .

公开仓库一键拉取示例：
  wget -O- https://raw.githubusercontent.com/you/repo/main/bootstrap-from-github.sh | \
    sudo bash -s -- https://github.com/you/repo.git main /opt/teachingopen-source .
EOF
}

REPO_URL="${1:-${REPO_URL:-}}"
BRANCH="${2:-${REPO_BRANCH:-main}}"
TARGET_DIR="${3:-${TARGET_DIR:-/opt/teachingopen-source}}"
PROJECT_SUBDIR="${4:-${PROJECT_SUBDIR:-.}}"

backup_local_repo_changes() {
  local repo_dir="$1"
  local backup_root="$repo_dir/backups/repo-local-changes"
  local stamp backup_dir

  if [[ -n "$("${SUDO[@]}" git -C "$repo_dir" status --porcelain --untracked-files=no)" ]]; then
    stamp="$(date +%Y%m%d-%H%M%S)"
    backup_dir="$backup_root/$stamp"
    mkdir -p "$backup_dir"

    "${SUDO[@]}" git -C "$repo_dir" status --short > "$backup_dir/status.txt"
    "${SUDO[@]}" git -C "$repo_dir" diff > "$backup_dir/working-tree.patch"
    "${SUDO[@]}" git -C "$repo_dir" diff --cached > "$backup_dir/index.patch"

    echo "检测到仓库脚本有本地修改，已自动备份到：$backup_dir"
    echo "现在会丢弃这些仓库内的本地修改，继续对齐远端版本。"
    "${SUDO[@]}" git -C "$repo_dir" reset --hard
  fi
}

sync_existing_repo() {
  echo "检测到已存在仓库，开始更新：$TARGET_DIR"
  "${SUDO[@]}" git -C "$TARGET_DIR" remote set-url origin "$REPO_URL"
  "${SUDO[@]}" git -C "$TARGET_DIR" fetch --all --tags

  backup_local_repo_changes "$TARGET_DIR"

  if "${SUDO[@]}" git -C "$TARGET_DIR" show-ref --verify --quiet "refs/heads/$BRANCH"; then
    "${SUDO[@]}" git -C "$TARGET_DIR" checkout "$BRANCH"
  else
    "${SUDO[@]}" git -C "$TARGET_DIR" checkout -B "$BRANCH" "origin/$BRANCH"
  fi

  "${SUDO[@]}" git -C "$TARGET_DIR" reset --hard "origin/$BRANCH"
}

if [[ -z "$REPO_URL" ]]; then
  usage
  exit 1
fi

ensure_git
ensure_git_lfs

if [[ -d "$TARGET_DIR/.git" ]]; then
  sync_existing_repo
else
  echo "开始克隆仓库：$REPO_URL"
  "${SUDO[@]}" git clone --branch "$BRANCH" "$REPO_URL" "$TARGET_DIR"
fi

"${SUDO[@]}" git -C "$TARGET_DIR" lfs install --local
git_lfs_pull_quiet_warning "$TARGET_DIR"

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

echo "开始执行一键部署..."
bash "$DEPLOY_DIR/install.sh"
