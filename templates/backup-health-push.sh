#!/bin/bash
# backup-health-push: checks WAL-G backup health on this host and pushes ONE status to a Gatus heartbeat
# (external endpoint). Gatus alerts when a push reports failure, or when no push arrives within the
# endpoint's heartbeat interval (host down, timer dead).
#
# Config: /etc/docker-host/gatus-push.env (root, 0600), read by the systemd unit and by this script:
#   GATUS_PUSH_URL    base URL, e.g. https://gatus.example.com (no trailing slash)
#   GATUS_PUSH_KEY    Gatus endpoint key, <group>_<name> as returned by the registrar (e.g. hosts_dynamic-env-prod)
#   GATUS_PUSH_TOKEN  bearer token of that endpoint
#   MAX_BASE_BACKUP_AGE_HOURS  (default 26)  base backup older than this is a failure
#   DISK_WARN_PERCENT          (default 85)  usage of DATA_MOUNT above this is a failure
#   DATA_MOUNT                 (default /mnt/data)
#   DRY_RUN=1                  print the verdict and what would be pushed, push nothing
#
# Checked for every running container that has WALG_S3_PREFIX in its environment and a postgres inside:
#   - the newest base backup (wal-g backup-list) is not older than MAX_BASE_BACKUP_AGE_HOURS, and exists
#   - WAL archiving is not currently failing (pg_stat_archiver: last_failed_time newer than last_archived_time)
# Historic failed_count is ignored on purpose: only a failure that is still the latest event alerts.
# MySQL containers (WALG_MYSQL_DATASOURCE_NAME) are not checked yet.
set -uo pipefail

ENV_FILE="${GATUS_PUSH_ENV_FILE:-/etc/docker-host/gatus-push.env}"
# shellcheck disable=SC1090
[ -r "$ENV_FILE" ] && . "$ENV_FILE"

: "${MAX_BASE_BACKUP_AGE_HOURS:=26}"
: "${DISK_WARN_PERCENT:=85}"
: "${DATA_MOUNT:=/mnt/data}"
DRY_RUN="${DRY_RUN:-0}"

errors=()
checked=0

while read -r c; do
  [ -z "$c" ] && continue
  # only containers that run WAL-G for postgres
  env_dump="$(docker inspect "$c" --format '{{range .Config.Env}}{{println .}}{{end}}' 2>/dev/null)" || continue
  printf '%s\n' "$env_dump" | grep -q '^WALG_S3_PREFIX=\|^WALG_AZ_PREFIX=\|^WALG_GS_PREFIX=' || continue
  docker exec "$c" sh -c 'command -v psql >/dev/null && command -v wal-g >/dev/null' 2>/dev/null || continue
  checked=$((checked + 1))
  name="$c"

  # newest base backup: last line of `wal-g backup-list`, 2nd column is an RFC3339 timestamp
  last_line="$(docker exec "$c" wal-g backup-list 2>/dev/null | grep '^base_' | tail -1)"
  if [ -z "$last_line" ]; then
    errors+=("$name: no base backup")
  else
    modified="$(printf '%s' "$last_line" | awk '{print $2}')"
    ts="$(date -u -d "$modified" +%s 2>/dev/null || true)"
    if [ -z "$ts" ]; then
      errors+=("$name: cannot read backup time")
    else
      age_h=$(( ( $(date -u +%s) - ts ) / 3600 ))
      [ "$age_h" -gt "$MAX_BASE_BACKUP_AGE_HOURS" ] && errors+=("$name: base backup ${age_h}h old")
    fi
  fi

  # archiver: failing now = the latest event is a failure
  arch="$(docker exec -u postgres "$c" psql -Atc \
    "select coalesce(last_failed_time > last_archived_time, last_failed_time is not null and last_archived_time is null) from pg_stat_archiver" 2>/dev/null | tr -d '[:space:]')"
  case "$arch" in
    t) errors+=("$name: WAL archiving failing") ;;
    f) ;;
    *) errors+=("$name: cannot query pg_stat_archiver") ;;
  esac
done < <(docker ps --format '{{.Names}}' 2>/dev/null)

# disk
if mountpoint -q "$DATA_MOUNT" 2>/dev/null; then
  pct="$(df --output=pcent "$DATA_MOUNT" | tail -1 | tr -dc '0-9')"
  [ -n "$pct" ] && [ "$pct" -ge "$DISK_WARN_PERCENT" ] && errors+=("disk $DATA_MOUNT ${pct}% full")
fi

if [ "${#errors[@]}" -eq 0 ]; then
  success=true; msg=""
else
  success=false; msg="$(printf '%s; ' "${errors[@]}")"; msg="${msg%; }"; msg="${msg:0:300}"
fi

echo "backup-health: databases checked=$checked success=$success${msg:+ error=$msg}"

if [ "$DRY_RUN" = "1" ]; then
  echo "DRY_RUN: nothing pushed"; exit 0
fi

: "${GATUS_PUSH_URL:?GATUS_PUSH_URL not set}" "${GATUS_PUSH_KEY:?GATUS_PUSH_KEY not set}" "${GATUS_PUSH_TOKEN:?GATUS_PUSH_TOKEN not set}"

# 404 right after registering the endpoint is normal for about a minute: retry. The token goes in a header
# read from stdin (-H @-) so it never shows in the process list.
args=(-X POST -G "${GATUS_PUSH_URL}/api/v1/endpoints/${GATUS_PUSH_KEY}/external" --data-urlencode "success=${success}")
[ -n "$msg" ] && args+=(--data-urlencode "error=${msg}")
curl -fsS -o /dev/null --max-time 20 --retry 5 --retry-delay 15 --retry-all-errors "${args[@]}" \
  -H @- <<<"Authorization: Bearer ${GATUS_PUSH_TOKEN}" \
  || { echo "backup-health: push to Gatus failed" >&2; exit 1; }
