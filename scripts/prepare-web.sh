#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WEB_ZIP="$ROOT_DIR/assets/teaching-open-web-2.8.0.zip"
OVERLAY_DIR="$ROOT_DIR/assets/web-overlay"
WEB_ROOT="$ROOT_DIR/runtime/web-root"
INDEX_FILE="$WEB_ROOT/index.html"

if ! command -v python3 >/dev/null 2>&1; then
  echo "Missing required command: python3" >&2
  exit 1
fi

if [[ ! -f "$WEB_ZIP" ]]; then
  echo "Missing frontend package: $WEB_ZIP" >&2
  exit 1
fi

WEB_ZIP="$WEB_ZIP" \
WEB_ROOT="$WEB_ROOT" \
WEB_OVERLAY_DIR="$OVERLAY_DIR" \
python3 "$ROOT_DIR/scripts/prepare-web.py"

if [[ ! -f "$INDEX_FILE" ]]; then
  echo "Frontend extraction failed: $INDEX_FILE not found" >&2
  exit 1
fi
