#!/bin/sh
# Creates the 5 project databases and loads each one's PostgreSQL DDL + seed
# data, skipping any database that already exists. Safe to run twice:
#  - on first container boot, Postgres runs every /docker-entrypoint-initdb.d/*
#    script automatically against an empty data volume.
#  - `make check-dbs` (and `make up`) also exec this script directly against
#    an already-running container to create any database that is missing,
#    without touching the ones that already exist.
set -eu

DATABASES="library cinema school bicycle_rental pos"
SQL_ROOT="${SQL_ROOT:-/workspace}"
PSQL="psql -v ON_ERROR_STOP=1 --username ${POSTGRES_USER:-postgres}"

created=0
skipped=0

for db in $DATABASES; do
  exists=$($PSQL -tAc "SELECT 1 FROM pg_database WHERE datname = '${db}'")

  if [ "$exists" = "1" ]; then
    echo "[skip]   database '${db}' already exists"
    skipped=$((skipped + 1))
    continue
  fi

  echo "[create] database '${db}'"
  $PSQL -c "CREATE DATABASE \"${db}\";"

  # library is split into mysql/postgresql/postgresql_denormalized/migration
  # subfolders, cinema into mysql/postgresql/postgresql_denormalization/migration
  # school into mysql/postgresql/postgresql_denormalization, bicycle_rental
  # into mysql/postgresql/postgresql_denormalization/migration and pos into
  # mysql/postgresql.
  # Only the original (normalized) PostgreSQL schema is loaded here; the
  # denormalized variants are applied by hand (bicycle_rental's needs its
  # summary-trigger steps, see bicycle_rental/estimation_response_time_and_resource.sh).
  if [ "$db" = "library" ]; then
    ddl_path="$SQL_ROOT/$db/postgresql/create_ddl.sql"
    insert_path="$SQL_ROOT/$db/postgresql/insert_data.sql"
  else
    ddl_path="$SQL_ROOT/$db/postgresql/postgresql_create_ddl.sql"
    insert_path="$SQL_ROOT/$db/postgresql/postgresql_insert_data.sql"
  fi

  echo "[load]   ${ddl_path#"$SQL_ROOT/"}"
  $PSQL -d "$db" -f "$ddl_path"

  echo "[load]   ${insert_path#"$SQL_ROOT/"}"
  $PSQL -d "$db" -f "$insert_path"

  created=$((created + 1))
done

echo "==> databases ready: $((created + skipped))/5 (created: ${created}, already present: ${skipped})"
