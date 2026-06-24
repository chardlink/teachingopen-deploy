#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="$ROOT_DIR/backups/$STAMP"

# shellcheck disable=SC1091
source "$ROOT_DIR/scripts/common.sh"

mkdir -p "$BACKUP_DIR"

docker_compose exec -T mysql sh -c \
  'exec mysqldump --default-character-set=utf8mb4 -uroot -p"$MYSQL_ROOT_PASSWORD" "$MYSQL_DATABASE"' \
  > "$BACKUP_DIR/teachingopen.sql"

tar -czf "$BACKUP_DIR/uploads.tgz" -C "$ROOT_DIR/data" uploads
cp "$ROOT_DIR/.env" "$BACKUP_DIR/.env"

echo "Backup written to $BACKUP_DIR"
