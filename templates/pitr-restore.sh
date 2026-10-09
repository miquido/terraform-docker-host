#!/bin/bash
# Usage: pitr-restore <postgres_container|compose_project> ["2026-05-21 10:00:00+00"|IMMEDIATE] [backup_name]
#   postgres_container  name of the postgres docker container
#   compose_project     docker compose project name; the postgres container is found by its
#                       compose label (the one with PGDATA set and a writable data mount), and the project's other running
#                       containers are stopped for the restore and started again afterwards
#   target_time         ISO 8601 timestamp for PITR, marker:<name> (a restore point made with pitr-marker),
#                       IMMEDIATE (backup state, no WAL replay), or omit for latest consistent state
#   backup_name         WAL-G backup name (e.g. base_00000002...), defaults to LATEST

#  # Restore to LATEST
#  pitr-restore <postgres_container>
#
#  # Restore to a specific point in time
#  pitr-restore <postgres_container> "2026-05-21 06:00:00+00"
#
#  # Restore to a marker made with pitr-marker
#  pitr-restore <postgres_container> marker:before-migration
#
#  # Restore to the state from a specific backup (zero WAL replay)
#  pitr-restore <postgres_container> IMMEDIATE base_000000020000000100000067
#
#  # Restore to a specific point in time from a specific backup
#  pitr-restore <postgres_container> "2026-05-21 06:00:00+00" base_000000020000000100000067

set -euo pipefail

ARG="${1:?Usage: $0 <postgres_container|compose_project> [target_time] [backup_name]}"
TARGET="${2:-LATEST}"
BACKUP="${3:-LATEST}"

# Checked before anything is stopped or cleared: a bad name must not leave the database emptied.
if [ "${TARGET#marker:}" != "$TARGET" ] && ! printf '%s' "${TARGET#marker:}" | grep -Eq '^[A-Za-z0-9_.-]{1,63}$'; then
  echo "Invalid marker name '${TARGET#marker:}': use letters, digits, '_', '.', '-', at most 63 characters" >&2
  exit 1
fi

# In compose-project mode the project's other running containers are stopped for the restore and started
# again at the very end. If the script dies in between they stay stopped on purpose: starting applications
# against a half-restored database is worse than an outage. Start them by hand once the database is sound.
OTHERS=""
if docker container inspect "$ARG" >/dev/null 2>&1; then
  PG="$ARG"
else
  PROJECT_FILTER="label=com.docker.compose.project=$ARG"
  CANDIDATES=""
  # The postgres container is the one with PGDATA set AND a writable mount holding it; helper
  # containers on the same image (e.g. a read-only backup job) share PGDATA but not the write access.
  for c in $(docker ps -a --filter "$PROJECT_FILTER" --format '{{.Names}}'); do
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
    echo "Expected exactly one postgres container in compose project '$ARG', found $#: ${CANDIDATES:-none}" >&2
    exit 1
  fi
  PG="$1"
  PG_ID=$(docker inspect "$PG" --format '{{.Id}}')
  OTHERS=$(docker ps --no-trunc --filter "$PROJECT_FILTER" --format '{{.ID}}' | grep -v "$PG_ID" || true)
fi

WALG_IMAGE=$(docker inspect "$PG" --format '{{.Config.Image}}')

WALG_ENV=$(mktemp)
trap 'rm -f "$WALG_ENV"' EXIT   # holds AWS keys: never leave it behind if a step fails
docker inspect "$PG" --format '{{range .Config.Env}}{{println .}}{{end}}' | grep -E '^(WALG_|AWS_)' > "$WALG_ENV"
PGDATA=$(docker inspect "$PG" --format '{{range .Config.Env}}{{println .}}{{end}}' | grep '^PGDATA=' | cut -d= -f2)

echo "Container:  $PG ($WALG_IMAGE)"
echo "PGDATA:     $PGDATA"
echo "Target:     $TARGET"
echo "Backup:     $BACKUP"

if [ -n "$OTHERS" ]; then
  echo "Stopping the rest of the project..."
  docker stop $OTHERS >/dev/null
fi
docker stop "$PG"

echo "Clearing PGDATA..."
docker run --rm --volumes-from "$PG" --entrypoint /bin/sh \
  "$WALG_IMAGE" -c "find $PGDATA -mindepth 1 -delete"

echo "Fetching base backup: $BACKUP..."
docker run --rm --volumes-from "$PG" --env-file "$WALG_ENV" \
  "$WALG_IMAGE" wal-g backup-fetch "$PGDATA" "$BACKUP"

EXTRA=""
if [ "$TARGET" = "IMMEDIATE" ]; then
  EXTRA="recovery_target = \047immediate\047\n"
elif [ "${TARGET#marker:}" != "$TARGET" ]; then
  EXTRA="recovery_target_name = \047${TARGET#marker:}\047\n"
elif [ "$TARGET" != "LATEST" ]; then
  EXTRA="recovery_target_time = \047$TARGET\047\n"
fi
docker run --rm --volumes-from "$PG" --entrypoint /bin/sh "$WALG_IMAGE" \
  -c "printf 'restore_command = \047wal-g wal-fetch %%f %%p\047\nrecovery_target_action = promote\n${EXTRA}' \
      > $PGDATA/postgresql.auto.conf"

docker run --rm --volumes-from "$PG" --entrypoint /bin/sh \
  "$WALG_IMAGE" -c "touch $PGDATA/recovery.signal"

rm "$WALG_ENV"

docker start "$PG"
echo "Waiting for postgres to be healthy..."
until docker inspect --format='{{.State.Health.Status}}' "$PG" | grep -q healthy; do sleep 2; done
echo "Postgres is healthy."
if [ -n "$OTHERS" ]; then
  echo "Starting the rest of the project..."
  docker start $OTHERS >/dev/null
fi
