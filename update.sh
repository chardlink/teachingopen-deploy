#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ ${EUID:-0} -ne 0 && ! -w "$ROOT_DIR" ]]; then
  exec sudo bash "$0" "$@"
fi

# shellcheck disable=SC1091
source "$ROOT_DIR/scripts/common.sh"

BRANCH="${1:-}"

backup_local_repo_changes() {
  local backup_root="$ROOT_DIR/backups/repo-local-changes"
  local stamp backup_dir

  if [[ -n "$(git -C "$ROOT_DIR" status --porcelain --untracked-files=no)" ]]; then
    stamp="$(date +%Y%m%d-%H%M%S)"
    backup_dir="$backup_root/$stamp"
    mkdir -p "$backup_dir"

    git -C "$ROOT_DIR" status --short > "$backup_dir/status.txt"
    git -C "$ROOT_DIR" diff > "$backup_dir/working-tree.patch"
    git -C "$ROOT_DIR" diff --cached > "$backup_dir/index.patch"

    echo "检测到仓库脚本有本地修改，已自动备份到：$backup_dir"
    echo "现在会丢弃这些仓库内修改，继续对齐远端版本。"
    git -C "$ROOT_DIR" reset --hard
  fi
}

resolve_branch() {
  if [[ -n "$BRANCH" ]]; then
    printf '%s' "$BRANCH"
    return 0
  fi

  BRANCH="$(git -C "$ROOT_DIR" branch --show-current)"
  if [[ -z "$BRANCH" ]]; then
    BRANCH="main"
  fi

  printf '%s' "$BRANCH"
}

git_lfs_pull_quiet_warning() {
  local lfs_log

  lfs_log="$(mktemp)"
  if git -C "$ROOT_DIR" lfs pull >"$lfs_log" 2>&1; then
    grep -Fv 'appears to use backslashes as path separators' "$lfs_log" || true
    rm -f "$lfs_log"
    return 0
  fi

  cat "$lfs_log" >&2
  rm -f "$lfs_log"
  return 1
}

main() {
  local target_branch
  local before_rev
  local after_rev

  if [[ ! -d "$ROOT_DIR/.git" ]]; then
    echo "当前目录不是 Git 仓库：$ROOT_DIR" >&2
    exit 1
  fi

  if [[ ! -f "$ROOT_DIR/.env" ]]; then
    echo "未找到 $ROOT_DIR/.env，请先完成首次部署。" >&2
    exit 1
  fi

  need_cmd git
  need_cmd docker

  target_branch="$(resolve_branch)"
  before_rev="$(git -C "$ROOT_DIR" rev-parse HEAD)"

  echo "开始更新仓库分支：$target_branch"
  git -C "$ROOT_DIR" fetch --all --tags
  backup_local_repo_changes

  if git -C "$ROOT_DIR" show-ref --verify --quiet "refs/heads/$target_branch"; then
    git -C "$ROOT_DIR" checkout "$target_branch"
  else
    git -C "$ROOT_DIR" checkout -B "$target_branch" "origin/$target_branch"
  fi

  git -C "$ROOT_DIR" reset --hard "origin/$target_branch"
  after_rev="$(git -C "$ROOT_DIR" rev-parse HEAD)"
  if [[ "$before_rev" != "$after_rev" && "${TEACHINGOPEN_UPDATE_REEXEC:-0}" != "1" ]]; then
    echo "已拉取到新的更新脚本，正在自动重启 update 引擎..."
    exec env TEACHINGOPEN_UPDATE_REEXEC=1 bash "$ROOT_DIR/update.sh" "$target_branch"
  fi

  git -C "$ROOT_DIR" lfs install --local
  git_lfs_pull_quiet_warning

  echo "重新准备前端静态文件..."
  bash "$ROOT_DIR/scripts/prepare-web.sh"

  echo "拉取最新容器镜像..."
  if ! docker_compose_pull_with_retry; then
    echo
    echo "镜像拉取失败，更新已中断。"
    echo "如果当前网络一直无法访问 Docker Hub，请手动执行："
    echo "  cd $ROOT_DIR && sudo PREFER_IPV4=yes ./configure-docker-mirror.sh"
    echo "然后再重新执行："
    echo "  cd $ROOT_DIR && sudo ./update.sh"
    exit 1
  fi

  echo "重建并启动服务..."
  SKIP_PREPARE=yes bash "$ROOT_DIR/start.sh" refresh

  echo
  echo "更新完成。"
  echo "可执行以下命令确认状态："
  echo "  cd $ROOT_DIR && ./status.sh"
  echo "  cd $ROOT_DIR && ./logs.sh"
}

main "$@"
