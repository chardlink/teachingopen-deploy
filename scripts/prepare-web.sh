#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WEB_ZIP="$ROOT_DIR/assets/teaching-open-web-2.8.0.zip"
OVERLAY_DIR="$ROOT_DIR/assets/web-overlay"
WEB_ROOT="$ROOT_DIR/runtime/web-root"
INDEX_FILE="$WEB_ROOT/index.html"

if ! command -v unzip >/dev/null 2>&1; then
  echo "Missing required command: unzip" >&2
  exit 1
fi

if [[ ! -f "$WEB_ZIP" ]]; then
  echo "Missing frontend package: $WEB_ZIP" >&2
  exit 1
fi

mkdir -p "$WEB_ROOT"
find "$WEB_ROOT" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
unzip -oq "$WEB_ZIP" -d "$WEB_ROOT"

if [[ -d "$OVERLAY_DIR" ]]; then
  cp -R "$OVERLAY_DIR"/. "$WEB_ROOT"/
fi

if [[ ! -f "$INDEX_FILE" ]]; then
  echo "Frontend extraction failed: $INDEX_FILE not found" >&2
  exit 1
fi

sed -i "s|<script async src=//api.paas.plus/js/errlog.js></script>||g" "$INDEX_FILE"
sed -i "s|window._CONFIG\\['onlinePreviewDomainURL'\\] = 'http://fileview.jeecg.com/onlinePreview'|window._CONFIG['onlinePreviewDomainURL'] = window._CONFIG['webURL'] + '/preview/onlinePreview'|g" "$INDEX_FILE"
