#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVICE="${1:-}"

# shellcheck disable=SC1091
source "$ROOT_DIR/scripts/common.sh"

if [[ -n "$SERVICE" ]]; then
  docker_compose logs -f --tail=200 "$SERVICE"
else
  docker_compose logs -f --tail=200
fi
