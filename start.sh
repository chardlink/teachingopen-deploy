#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

bash "$ROOT_DIR/scripts/prepare-web.sh"

# shellcheck disable=SC1091
source "$ROOT_DIR/scripts/common.sh"
docker_compose up -d
