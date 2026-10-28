#!/bin/sh
set -e

create_database() {
  db_name="$1"
  exists=$(psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" -tAc "SELECT 1 FROM pg_database WHERE datname = '$db_name'")
  if [ "$exists" != "1" ]; then
    echo "Creating database: $db_name"
    psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" -c "CREATE DATABASE \"$db_name\";"
  else
    echo "Database already exists, skipping: $db_name"
  fi
}

create_database "${POSTGRES_DB_QA:-mylogbook_qa}"
create_database "${POSTGRES_DB_PROD:-mylogbook_prod}"
