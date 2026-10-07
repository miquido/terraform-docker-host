#!/bin/bash
# Usage: pitr-restore-mysql <mysql_container> ["2026-05-21T10:00:00Z"|LATEST|IMMEDIATE] [backup_name]
#   mysql_container  name of the mysql-walg docker container
#   target_time      RFC3339 timestamp to replay binlogs up to, LATEST (replay everything
#                     archived so far), or IMMEDIATE (base backup only, no binlog replay)
#   backup_name      WAL-G base backup name to restore from, defaults to LATEST
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
#  # Restore to just the base backup, no binlog replay
#  pitr-restore-mysql miquido-it-snipeit-main-mysql-1 IMMEDIATE

set -euo pipefail

MYSQL="${1:?Usage: $0 <mysql_container> [target_time|LATEST|IMMEDIATE] [backup_name]}"
TARGET="${2:-LATEST}"
BACKUP="${3:-LATEST}"

WALG_IMAGE=$(docker inspect "$MYSQL" --format '{{.Config.Image}}')

WALG_ENV=$(mktemp)
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
  REPLAY_CMD='b=$(basename "$WALG_MYSQL_CURRENT_BINLOG"); [ "$(expr "${b##*.}" + 0)" -lt "$(expr "'"${START_BINLOG##*.}"'" + 0)" ] && exit 0; pos=""; [ "$b" = "'"$START_BINLOG"'" ] && pos="--start-position='"$START_POS"'"; mysqlbinlog --stop-datetime="$WALG_MYSQL_BINLOG_END_TS" $pos "$WALG_MYSQL_CURRENT_BINLOG" | mysql -uroot -p"$MYSQL_ROOT_PASSWORD"'
  REPLAY_ENV=(-e "WALG_MYSQL_BINLOG_REPLAY_COMMAND=$REPLAY_CMD")
else
  echo "WARNING: no xtrabackup_binlog_info in the restored datadir; replaying with the container's own replay command."
fi

if [ "$TARGET" = "IMMEDIATE" ]; then
  echo "IMMEDIATE requested — skipping binlog replay, left at base backup state."
elif [ "$TARGET" = "LATEST" ]; then
  echo "Replaying binlogs since $BACKUP (latest archived)..."
  docker exec "${REPLAY_ENV[@]}" "$MYSQL" wal-g binlog-replay --since "$BACKUP"
  echo "Binlog replay complete."
else
  echo "Replaying binlogs since $BACKUP up to $TARGET..."
  docker exec "${REPLAY_ENV[@]}" "$MYSQL" wal-g binlog-replay --since "$BACKUP" --until "$TARGET"
  echo "Binlog replay complete."
fi
