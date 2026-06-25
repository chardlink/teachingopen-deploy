#!/usr/bin/env bash
set -euo pipefail

raw_sql="/seed/teachingopen2.8.sql"
clean_sql="/tmp/teachingopen-init.sql"

if [[ ! -f "$raw_sql" ]]; then
  echo "Missing SQL seed file: $raw_sql" >&2
  exit 1
fi

sed -E \
  -e 's/`teachingopendemo`\.`([^`]+)`/`\1`/g' \
  -e '/^CREATE DATABASE /Id' \
  -e '/^USE /Id' \
  "$raw_sql" > "$clean_sql"

mysql --default-character-set=utf8mb4 \
  -uroot \
  -p"${MYSQL_ROOT_PASSWORD}" \
  "${MYSQL_DATABASE}" < "$clean_sql"

mysql --default-character-set=utf8mb4 \
  -uroot \
  -p"${MYSQL_ROOT_PASSWORD}" \
  "${MYSQL_DATABASE}" \
  -e "UPDATE sys_file SET file_location = 1 WHERE file_location = 2;"
