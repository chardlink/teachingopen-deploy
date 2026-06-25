#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STACK_MODE="${1:-up}"
SKIP_PREPARE="${SKIP_PREPARE:-no}"

if [[ "$SKIP_PREPARE" != "yes" ]]; then
  bash "$ROOT_DIR/scripts/prepare-web.sh"
fi

# shellcheck disable=SC1091
source "$ROOT_DIR/scripts/common.sh"

prepare_default_upload_assets

case "$STACK_MODE" in
  up|start|"")
    docker_compose_up_compat
    ;;
  refresh|recreate|restart)
    docker_compose_recreate_compat
    ;;
  *)
    echo "Unsupported stack mode: $STACK_MODE" >&2
    echo "Usage: ./start.sh [up|refresh]" >&2
    exit 1
    ;;
esac

normalize_sys_file_location_for_local_mode
normalize_default_user_avatars_for_local_mode
