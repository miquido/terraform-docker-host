#!/bin/bash
# Usage: ./pitr-restore.sh <postgres_container> ["2026-05-21 10:00:00+00"|IMMEDIATE] [backup_name]
#   postgres_container  name of the postgres docker container
#   target_time         ISO 8601 timestamp for PITR, IMMEDIATE (backup state, no WAL replay),
#                       or omit for latest consistent state
#   backup_name         WAL-G backup name (e.g. base_00000002...), defaults to LATEST

#  # Restore to LATEST
#  ./pitr-restore.sh <postgres_container>
#
#  # Restore to a specific point in time
#  ./pitr-restore.sh <postgres_container> "2026-05-21 06:00:00+00"
#
#  # Restore to the state from a specific backup (zero WAL replay)
#  ./pitr-restore.sh <postgres_container> IMMEDIATE base_000000020000000100000067
#
#  # Restore to a specific point in time from a specific backup
#  ./pitr-restore.sh <postgres_container> "2026-05-21 06:00:00+00" base_000000020000000100000067


set -euo pipefail

PG="${1:?Usage: $0 <postgres_container> [target_time] [backup_name]}"
TARGET="${2:-LATEST}"
BACKUP="${3:-LATEST}"

WALG_IMAGE=$(docker inspect "$PG" --format '{{.Config.Image}}')

docker inspect "$PG" --format '{{range .Config.Env}}{{println .}}{{end}}' | grep -E '^(WALG_|AWS_)' > /tmp/walg-restore.env
PGDATA=$(docker inspect "$PG" --format '{{range .Config.Env}}{{println .}}{{end}}' | grep '^PGDATA=' | cut -d= -f2)
VOL_SRC=$(docker inspect "$PG" --format '{{(index .Mounts 0).Source}}')
VOL_DST=$(docker inspect "$PG" --format '{{(index .Mounts 0).Destination}}')
HOST_PGDATA="$VOL_SRC${PGDATA#$VOL_DST}"

echo "Container:  $PG ($WALG_IMAGE)"
echo "PGDATA:     $PGDATA (host: $HOST_PGDATA)"
echo "Target:     $TARGET"
echo "Backup:     $BACKUP"

docker stop "$PG"

echo "Clearing PGDATA..."
find "$HOST_PGDATA" -mindepth 1 -delete

echo "Fetching base backup: $BACKUP..."
docker run --rm --volumes-from "$PG" --env-file /tmp/walg-restore.env \
  "$WALG_IMAGE" wal-g backup-fetch "$PGDATA" "$BACKUP"

{
  echo "restore_command = 'wal-g wal-fetch \"%f\" \"%p\"'"
  echo "recovery_target_action = promote"
  if [ "$TARGET" = "IMMEDIATE" ]; then
    echo "recovery_target = 'immediate'"
  elif [ "$TARGET" != "LATEST" ]; then
    echo "recovery_target_time = '$TARGET'"
  fi
} > "$HOST_PGDATA/postgresql.auto.conf"

touch "$HOST_PGDATA/recovery.signal"
rm /tmp/walg-restore.env

docker start "$PG"
echo "Waiting for postgres to be healthy..."
until docker inspect --format='{{.State.Health.Status}}' "$PG" | grep -q healthy; do sleep 2; done
echo "Postgres is healthy."