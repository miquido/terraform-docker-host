#!/bin/bash
# Usage: pitr-marker <postgres_container|compose_project> [name]
#   postgres_container  name of the postgres docker container
#   compose_project     docker compose project name; the postgres container is found by its compose label
#                       (the one with PGDATA set and a writable data mount), as in pitr-restore
#   name                label of the marker: letters, digits, '_', '.', '-', at most 63 characters;
#                       defaults to marker-<UTC timestamp>
#
# Writes a named restore point into the WAL and waits until the WAL segment that holds it is archived, so
# the marker is safe in the WAL-G storage when the script returns. Take one right before a risky operation
# (a migration, a bulk update), then undo the operation with:
#   pitr-restore <container|compose_project> marker:<name>

#  pitr-marker my-project before-migration
#  pitr-restore my-project marker:before-migration

set -euo pipefail

ARG="${1:?Usage: $0 <postgres_container|compose_project> [name]}"
NAME="${2:-marker-$(date -u +%Y%m%dT%H%M%SZ)}"

if ! printf '%s' "$NAME" | grep -Eq '^[A-Za-z0-9_.-]{1,63}$'; then
  echo "Invalid marker name '$NAME': use letters, digits, '_', '.', '-', at most 63 characters" >&2
  exit 1
fi

if docker container inspect "$ARG" >/dev/null 2>&1; then
  PG="$ARG"
else
  CANDIDATES=""
  for c in $(docker ps --filter "label=com.docker.compose.project=$ARG" --format '{{.Names}}'); do
    cdata=$(docker inspect "$c" --format '{{range .Config.Env}}{{println .}}{{end}}' | sed -n 's/^PGDATA=//p')
    [ -n "$cdata" ] || continue
    rw_dests=$(docker inspect "$c" --format '{{range .Mounts}}{{if .RW}}{{.Destination}} {{end}}{{end}}')
    for dest in $rw_dests; do
      case "$cdata/" in
        "$dest"/*) CANDIDATES="$CANDIDATES $c"; break ;;
      esac
    done
  done
  set -- $CANDIDATES
  if [ "$#" -ne 1 ]; then
    echo "Expected exactly one running postgres container in compose project '$ARG', found $#: ${CANDIDATES:-none}" >&2
    exit 1
  fi
  PG="$1"
fi

psql_in() {
  docker exec "$PG" sh -c 'psql -X -At -U "${POSTGRES_USER:-${PGUSER:-postgres}}" -d postgres -c "$1"' sh "$1"
}

if [ "$(psql_in "select pg_is_in_recovery()")" != "f" ]; then
  echo "$PG is in recovery: a restore point can only be created on a primary" >&2
  exit 1
fi
if [ "$(psql_in "show archive_mode")" != "on" ]; then
  echo "archive_mode is off in $PG: a marker that is not archived cannot be restored to" >&2
  exit 1
fi

LSN=$(psql_in "select pg_create_restore_point('$NAME')")
WALFILE=$(psql_in "select pg_walfile_name('$LSN')")
psql_in "select pg_switch_wal()" >/dev/null   # close the segment so that it gets archived now, not at archive_timeout

echo "Marker '$NAME' at $LSN (WAL file $WALFILE), waiting for it to be archived..."
for _ in $(seq 1 60); do
  LAST=$(psql_in "select coalesce(last_archived_wal, '') from pg_stat_archiver")
  # WAL file names are fixed-width hex (timeline, log, segment), so a plain string comparison orders them.
  if [ -n "$LAST" ] && [[ ! "$LAST" < "$WALFILE" ]]; then
    echo "Archived (last archived WAL: $LAST). Restore with: pitr-restore $ARG marker:$NAME"
    exit 0
  fi
  sleep 2
done
echo "The marker was written but its WAL file is not archived after 120s (last archived: ${LAST:-none}); check archive_command and 'select * from pg_stat_archiver' in $PG" >&2
exit 1
