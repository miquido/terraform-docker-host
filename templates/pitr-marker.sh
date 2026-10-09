#!/bin/bash
# Usage: pitr-marker <container|compose_project> [name]
#   container        name of a postgres or mysql docker container with WAL-G
#   compose_project  docker compose project name; the postgres or mysql container is found by its compose
#                    label (PGDATA, or WALG_MYSQL_DATASOURCE_NAME, set and a writable data mount), as in
#                    pitr-restore / pitr-restore-mysql. Exactly one such container must be running.
#   name             label of the marker: letters, digits, '_', '.', '-', at most 63 characters;
#                    defaults to marker-<UTC timestamp>
#
# Records a point to restore to and waits until everything up to it is in the WAL-G storage, so the marker
# is safe when the script returns. Take one right before a risky operation (a migration, a bulk update),
# then undo the operation with:
#   pitr-restore <container|compose_project> marker:<name>          (postgres)
#   pitr-restore-mysql <container> marker:<name>                    (mysql)
#
# Postgres: a named restore point in the WAL (pg_create_restore_point); the segment that holds it is
#   archived before the script returns.
# MySQL: the current binlog file and position, written to the storage as markers/<name>, after the binlog
#   was rotated and pushed. MySQL has no named restore points, so the restore replays the binlogs up to
#   exactly that position.

#  pitr-marker my-project before-migration
#  pitr-restore my-project marker:before-migration

set -euo pipefail

ARG="${1:?Usage: $0 <container|compose_project> [name]}"
NAME="${2:-marker-$(date -u +%Y%m%dT%H%M%SZ)}"

if ! printf '%s' "$NAME" | grep -Eq '^[A-Za-z0-9_.-]{1,63}$'; then
  echo "Invalid marker name '$NAME': use letters, digits, '_', '.', '-', at most 63 characters" >&2
  exit 1
fi

# postgres | mysql | empty for a container that is neither
kind_of() {
  local env
  env=$(docker inspect "$1" --format '{{range .Config.Env}}{{println .}}{{end}}')
  if printf '%s\n' "$env" | grep -q '^PGDATA='; then echo postgres
  elif printf '%s\n' "$env" | grep -q '^WALG_MYSQL_DATASOURCE_NAME='; then echo mysql
  fi
}

# Is $2 (a path inside the container) on a writable mount of container $1?
writable_data() {
  local dest
  for dest in $(docker inspect "$1" --format '{{range .Mounts}}{{if .RW}}{{.Destination}} {{end}}{{end}}'); do
    case "$2/" in "$dest"/*) return 0 ;; esac
  done
  return 1
}

if docker container inspect "$ARG" >/dev/null 2>&1; then
  CTR="$ARG"
  KIND=$(kind_of "$CTR")
  [ -n "$KIND" ] || { echo "$CTR is neither a postgres (PGDATA) nor a mysql (WALG_MYSQL_DATASOURCE_NAME) container" >&2; exit 1; }
else
  CANDIDATES=""
  for c in $(docker ps --filter "label=com.docker.compose.project=$ARG" --format '{{.Names}}'); do
    k=$(kind_of "$c")
    case "$k" in
      postgres)
        pgdata=$(docker inspect "$c" --format '{{range .Config.Env}}{{println .}}{{end}}' | sed -n 's/^PGDATA=//p')
        writable_data "$c" "$pgdata" && CANDIDATES="$CANDIDATES $c" ;;
      mysql)
        writable_data "$c" /var/lib/mysql && CANDIDATES="$CANDIDATES $c" ;;
    esac
  done
  set -- $CANDIDATES
  if [ "$#" -ne 1 ]; then
    echo "Expected exactly one running postgres or mysql container in compose project '$ARG', found $#: ${CANDIDATES:-none}" >&2
    exit 1
  fi
  CTR="$1"
  KIND=$(kind_of "$CTR")
fi

postgres_marker() {
  psql_in() {
    docker exec "$CTR" sh -c 'psql -X -At -U "${POSTGRES_USER:-${PGUSER:-postgres}}" -d postgres -c "$1"' sh "$1"
  }

  if [ "$(psql_in "select pg_is_in_recovery()")" != "f" ]; then
    echo "$CTR is in recovery: a restore point can only be created on a primary" >&2
    exit 1
  fi
  if [ "$(psql_in "show archive_mode")" != "on" ]; then
    echo "archive_mode is off in $CTR: a marker that is not archived cannot be restored to" >&2
    exit 1
  fi

  local lsn walfile last
  lsn=$(psql_in "select pg_create_restore_point('$NAME')")
  walfile=$(psql_in "select pg_walfile_name('$lsn')")
  psql_in "select pg_switch_wal()" >/dev/null   # close the segment so that it gets archived now, not at archive_timeout

  echo "Marker '$NAME' at $lsn (WAL file $walfile), waiting for it to be archived..."
  for _ in $(seq 1 60); do
    last=$(psql_in "select coalesce(last_archived_wal, '') from pg_stat_archiver")
    # WAL file names are fixed-width hex (timeline, log, segment), so a plain string comparison orders them.
    if [ -n "$last" ] && [[ ! "$last" < "$walfile" ]]; then
      echo "Archived (last archived WAL: $last). Restore with: pitr-restore $ARG marker:$NAME"
      return 0
    fi
    sleep 2
  done
  echo "The marker was written but its WAL file is not archived after 120s (last archived: ${last:-none}); check archive_command and 'select * from pg_stat_archiver' in $CTR" >&2
  exit 1
}

mysql_marker() {
  mysql_in() {
    docker exec "$CTR" sh -c 'mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -N -B -e "$1" 2>/dev/null' sh "$1"
  }

  if [ "$(mysql_in "select @@log_bin")" != "1" ]; then
    echo "log_bin is off in $CTR: without binlogs there is nothing to restore to" >&2
    exit 1
  fi
  if docker exec "$CTR" wal-g st ls markers/ 2>/dev/null | awk '{print $NF}' | grep -qx "$NAME"; then
    echo "Marker '$NAME' already exists in the storage; pick another name" >&2
    exit 1
  fi

  local ts status file pos
  ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  # SHOW BINARY LOG STATUS replaced SHOW MASTER STATUS in MySQL 8.4
  status=$(mysql_in "show binary log status" || mysql_in "show master status")
  file=$(printf '%s\n' "$status" | awk 'NR==1{print $1}')
  pos=$(printf '%s\n' "$status" | awk 'NR==1{print $2}')
  if [ -z "$file" ] || [ -z "$pos" ]; then
    echo "Could not read the binlog position of $CTR" >&2
    exit 1
  fi

  # Rotate, so that the file holding the marker is closed and binlog-push uploads it now (it never uploads
  # the file the server is still writing to).
  mysql_in "flush binary logs" >/dev/null
  docker exec "$CTR" wal-g binlog-push >/dev/null 2>&1 || { echo "wal-g binlog-push failed in $CTR" >&2; exit 1; }
  if ! docker exec "$CTR" wal-g st ls binlog_005/ 2>/dev/null | awk '{print $NF}' | grep -q "^$file"; then
    echo "$file is not in the storage after binlog-push; not recording the marker" >&2
    exit 1
  fi

  # Plain text under its own name: without these flags wal-g would store it compressed as markers/<name>.lz4.
  printf 'file=%s\npos=%s\ntime=%s\n' "$file" "$pos" "$ts" \
    | docker exec -i "$CTR" wal-g st put --no-compress --no-encrypt --read-stdin "markers/$NAME" >/dev/null 2>&1 \
    || { echo "Could not write markers/$NAME to the storage" >&2; exit 1; }

  echo "Marker '$NAME' at $file:$pos ($ts), binlog archived. Restore with: pitr-restore-mysql $CTR marker:$NAME"
}

case "$KIND" in
  postgres) postgres_marker ;;
  mysql) mysql_marker ;;
esac
