#!/bin/bash
# Usage: pitr-restore-mysql <mysql_container> ["2026-05-21T10:00:00Z"|marker:<name>|LATEST|IMMEDIATE] [backup_name]
#   mysql_container  name of the mysql-walg docker container
#   target_time      RFC3339 timestamp to replay binlogs up to, marker:<name> (a marker made with
#                     pitr-marker: replays up to exactly its binlog position), LATEST (replay everything
#                     archived so far), or IMMEDIATE (base backup only, no binlog replay)
#   backup_name      WAL-G base backup name to restore from, defaults to LATEST; with a marker, LATEST
#                     means the newest base backup that finished before the marker
#
# Unlike Postgres's pitr-restore.sh, MySQL's binlog-replay runs against an already-running
# server (docker exec, not a sibling container) — WALG_MYSQL_BINLOG_REPLAY_COMMAND pipes into
# `mysql` over localhost/socket, so it needs the same network/mount namespace as the live mysqld.
#
#  # Restore to the latest archived binlog
#  pitr-restore-mysql miquido-it-snipeit-main-mysql-1
#
#  # Restore to a specific point in time
#  pitr-restore-mysql miquido-it-snipeit-main-mysql-1 "2026-09-29T08:00:00Z"
#
#  # Restore to a marker made with pitr-marker
#  pitr-restore-mysql miquido-it-snipeit-main-mysql-1 marker:before-migration
#
#  # Restore to just the base backup, no binlog replay
#  pitr-restore-mysql miquido-it-snipeit-main-mysql-1 IMMEDIATE

set -euo pipefail

MYSQL="${1:?Usage: $0 <mysql_container> [target_time|LATEST|IMMEDIATE] [backup_name]}"
TARGET="${2:-LATEST}"
BACKUP="${3:-LATEST}"

# A marker is read, validated and matched with a base backup while the container still runs: a bad name
# or a missing marker must not leave the datadir cleared.
MARKER_FILE=""; MARKER_POS=""; MARKER_TIME=""
if [ "${TARGET#marker:}" != "$TARGET" ]; then
  MARKER_NAME="${TARGET#marker:}"
  if ! printf '%s' "$MARKER_NAME" | grep -Eq '^[A-Za-z0-9_.-]{1,63}$'; then
    echo "Invalid marker name '$MARKER_NAME': use letters, digits, '_', '.', '-', at most 63 characters" >&2
    exit 1
  fi
  MARKER=$(docker exec "$MYSQL" wal-g st cat "markers/$MARKER_NAME" 2>/dev/null) \
    || { echo "No marker '$MARKER_NAME' in the storage of $MYSQL" >&2; exit 1; }
  MARKER_FILE=$(printf '%s\n' "$MARKER" | sed -n 's/^file=//p')
  MARKER_POS=$(printf '%s\n' "$MARKER" | sed -n 's/^pos=//p')
  MARKER_TIME=$(printf '%s\n' "$MARKER" | sed -n 's/^time=//p')
  if ! printf '%s' "$MARKER_FILE" | grep -Eq '^[A-Za-z0-9_.-]+\.[0-9]+$' \
     || ! printf '%s' "$MARKER_POS" | grep -Eq '^[0-9]+$' \
     || ! printf '%s' "$MARKER_TIME" | grep -Eq '^[0-9T:Z-]+$'; then
    echo "Marker '$MARKER_NAME' is malformed: $MARKER" >&2
    exit 1
  fi
  if [ "$BACKUP" = "LATEST" ]; then
    BACKUP=$(docker exec "$MYSQL" wal-g backup-list --detail --json 2>/dev/null | python3 -c '
import json, sys
marker = sys.argv[1]
ok = [b for b in json.load(sys.stdin) if b["stop_local_time"][:19] < marker.rstrip("Z")[:19]]
print(max(ok, key=lambda b: b["stop_local_time"])["backup_name"] if ok else "")' "$MARKER_TIME")
    [ -n "$BACKUP" ] || { echo "No base backup finished before marker '$MARKER_NAME' ($MARKER_TIME): nothing to restore it from" >&2; exit 1; }
  fi
  echo "Marker:     $MARKER_NAME = $MARKER_FILE:$MARKER_POS ($MARKER_TIME)"
fi

WALG_IMAGE=$(docker inspect "$MYSQL" --format '{{.Config.Image}}')

WALG_ENV=$(mktemp)
trap 'rm -f "$WALG_ENV"' EXIT   # holds AWS keys: never leave it behind if a step fails
docker inspect "$MYSQL" --format '{{range .Config.Env}}{{println .}}{{end}}' | grep -E '^(WALG_|AWS_)' > "$WALG_ENV"

echo "Container:  $MYSQL ($WALG_IMAGE)"
echo "Backup:     $BACKUP"
echo "Target:     $TARGET"

docker stop "$MYSQL"

echo "Clearing datadir..."
docker run --rm --volumes-from "$MYSQL" --entrypoint /bin/sh \
  "$WALG_IMAGE" -c "find /var/lib/mysql -mindepth 1 -delete"

echo "Fetching base backup: $BACKUP..."
docker run --rm --volumes-from "$MYSQL" --env-file "$WALG_ENV" \
  "$WALG_IMAGE" wal-g backup-fetch "$BACKUP"

echo "Preparing (xtrabackup --prepare)..."
docker run --rm --volumes-from "$MYSQL" --entrypoint /bin/sh \
  "$WALG_IMAGE" -c "xtrabackup --prepare --target-dir=/var/lib/mysql"

rm "$WALG_ENV"

docker start "$MYSQL"
echo "Waiting for mysql to be healthy..."
until docker inspect --format='{{.State.Health.Status}}' "$MYSQL" | grep -q healthy; do sleep 2; done
echo "MySQL is healthy (base backup restored)."

# wal-g doesn't create WALG_MYSQL_BINLOG_DST itself before downloading into it, and refuses to
# overwrite files left there by an earlier (possibly failed) run.
docker exec "$MYSQL" sh -c 'rm -rf /tmp/binlogs && mkdir -p /tmp/binlogs'

# Where the base backup stands in the binlog stream: "<binlog file> <position> [<gtid set>]".
# wal-g (v3.0.3 here) replays whole binlog files starting from the one that was current when the
# backup began, so without this the statements before the backup point get applied a second time
# ("database exists", "duplicate column", ...) and the replay aborts. Skip older binlogs entirely
# and start the first one at the recorded position.
BINLOG_INFO=$(docker exec "$MYSQL" cat /var/lib/mysql/xtrabackup_binlog_info 2>/dev/null || true)
START_BINLOG=$(echo "$BINLOG_INFO" | awk 'NR==1{print $1}')
START_POS=$(echo "$BINLOG_INFO" | awk 'NR==1{print $2}')
REPLAY_ENV=()
if [ -n "$START_BINLOG" ] && [ -n "$START_POS" ]; then
  echo "Base backup ends at $START_BINLOG:$START_POS"
  if [ -n "$MARKER_FILE" ]; then
    # The base backup has to end before the marker, or replaying cannot reach it.
    sn=$(expr "${START_BINLOG##*.}" + 0); mn=$(expr "${MARKER_FILE##*.}" + 0)
    if [ "$sn" -gt "$mn" ] || { [ "$sn" -eq "$mn" ] && [ "$START_POS" -gt "$MARKER_POS" ]; }; then
      echo "Base backup $BACKUP ends at $START_BINLOG:$START_POS, after marker $MARKER_FILE:$MARKER_POS: pick an older backup (backup_name). MySQL is left at that base backup state." >&2
      exit 1
    fi
  fi
  # Pieces of the replay command, run by wal-g for every fetched binlog: skip the ones before the backup
  # point (and, for a marker, after the marker's file), start the first at the recorded position and stop
  # the marker's file at the marker's position.
  RC_SKIP_OLD='b=$(basename "$WALG_MYSQL_CURRENT_BINLOG"); [ "$(expr "${b##*.}" + 0)" -lt "$(expr "'"${START_BINLOG##*.}"'" + 0)" ] && exit 0;'
  RC_SKIP_NEW=''
  RC_STOP=''
  if [ -n "$MARKER_FILE" ]; then
    RC_SKIP_NEW=' [ "$(expr "${b##*.}" + 0)" -gt "$(expr "'"${MARKER_FILE##*.}"'" + 0)" ] && exit 0;'
    RC_STOP=' [ "$b" = "'"$MARKER_FILE"'" ] && pos="$pos --stop-position='"$MARKER_POS"'";'
  fi
  RC_START=' pos=""; [ "$b" = "'"$START_BINLOG"'" ] && pos="--start-position='"$START_POS"'";'
  RC_REPLAY=' mysqlbinlog --stop-datetime="$WALG_MYSQL_BINLOG_END_TS" $pos "$WALG_MYSQL_CURRENT_BINLOG" | mysql -uroot -p"$MYSQL_ROOT_PASSWORD"'
  REPLAY_CMD="$RC_SKIP_OLD$RC_SKIP_NEW$RC_START$RC_STOP$RC_REPLAY"
  REPLAY_ENV=(-e "WALG_MYSQL_BINLOG_REPLAY_COMMAND=$REPLAY_CMD")
else
  if [ -n "$MARKER_FILE" ]; then
    echo "No xtrabackup_binlog_info in the restored datadir: cannot replay up to a marker. MySQL is left at the base backup state." >&2
    exit 1
  fi
  echo "WARNING: no xtrabackup_binlog_info in the restored datadir; replaying with the container's own replay command."
fi

if [ "$TARGET" = "IMMEDIATE" ]; then
  echo "IMMEDIATE requested — skipping binlog replay, left at base backup state."
elif [ -n "$MARKER_FILE" ]; then
  # --until only bounds which binlogs wal-g fetches; the exact end is the position in the replay command.
  # The marker's file was rotated and pushed right after the marker, so a margin after its time is enough.
  UNTIL=$(date -u -d "$MARKER_TIME + 10 minutes" +%Y-%m-%dT%H:%M:%SZ)
  echo "Replaying binlogs since $BACKUP up to $MARKER_FILE:$MARKER_POS..."
  docker exec "${REPLAY_ENV[@]}" "$MYSQL" wal-g binlog-replay --since "$BACKUP" --until "$UNTIL"
  echo "Binlog replay complete."
elif [ "$TARGET" = "LATEST" ]; then
  echo "Replaying binlogs since $BACKUP (latest archived)..."
  docker exec "${REPLAY_ENV[@]}" "$MYSQL" wal-g binlog-replay --since "$BACKUP"
  echo "Binlog replay complete."
else
  echo "Replaying binlogs since $BACKUP up to $TARGET..."
  docker exec "${REPLAY_ENV[@]}" "$MYSQL" wal-g binlog-replay --since "$BACKUP" --until "$TARGET"
  echo "Binlog replay complete."
fi
