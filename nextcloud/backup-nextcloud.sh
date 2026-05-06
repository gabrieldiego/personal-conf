#!/usr/bin/env bash
set -Eeuo pipefail

# Back up a Docker Compose Nextcloud deployment installed by install-nextcloud.sh.
# Creates one compressed archive containing:
#   - MariaDB SQL dump
#   - Nextcloud config, user data, installed apps, themes
#   - compose.yaml, .env, Caddyfile, helper scripts
#   - /root/nextcloud-credentials.txt, if present
#
# Usage:
#   sudo ./backup-nextcloud.sh
#   sudo INSTALL_DIR=/opt/nextcloud BACKUP_DIR=/mnt/backups ./backup-nextcloud.sh
#   sudo BACKUP_FILE=/mnt/backups/nextcloud-backup.tar.gz ./backup-nextcloud.sh

INSTALL_DIR="${INSTALL_DIR:-/opt/nextcloud}"
BACKUP_DIR="${BACKUP_DIR:-${INSTALL_DIR}/backups}"
BACKUP_FILE="${BACKUP_FILE:-}"
CREDENTIALS_FILE="${CREDENTIALS_FILE:-/root/nextcloud-credentials.txt}"
TIMESTAMP="$(date -u +%Y%m%dT%H%M%SZ)"

if [[ $EUID -ne 0 ]]; then
  echo "Run as root: sudo $0" >&2
  exit 1
fi

if [[ ! -d "$INSTALL_DIR" || ! -f "$INSTALL_DIR/compose.yaml" || ! -f "$INSTALL_DIR/.env" ]]; then
  echo "Could not find a Nextcloud install at: $INSTALL_DIR" >&2
  echo "Expected compose.yaml and .env." >&2
  exit 1
fi

command -v docker >/dev/null 2>&1 || { echo "docker is required." >&2; exit 1; }
command -v tar >/dev/null 2>&1 || { echo "tar is required." >&2; exit 1; }
command -v gzip >/dev/null 2>&1 || { echo "gzip is required." >&2; exit 1; }

service_running() {
  local service="$1"
  docker compose ps --services --filter "status=running" 2>/dev/null | grep -qx "$service"
}

cd "$INSTALL_DIR"

# shellcheck disable=SC1091
set -a
. ./.env
set +a

mkdir -p "$BACKUP_DIR"
chmod 700 "$BACKUP_DIR" || true

if [[ -z "$BACKUP_FILE" ]]; then
  safe_domain="${DOMAIN:-nextcloud}"
  safe_domain="${safe_domain//[^A-Za-z0-9_.-]/_}"
  BACKUP_FILE="${BACKUP_DIR}/nextcloud-backup-${safe_domain}-${TIMESTAMP}.tar.gz"
fi

# Make BACKUP_FILE absolute so later cd/trap behavior cannot confuse it.
BACKUP_PARENT="$(dirname "$BACKUP_FILE")"
mkdir -p "$BACKUP_PARENT"
BACKUP_PARENT="$(cd "$BACKUP_PARENT" && pwd)"
BACKUP_FILE="${BACKUP_PARENT}/$(basename "$BACKUP_FILE")"

TMPDIR="$(mktemp -d)"
MAINTENANCE_WAS_ON=0
APP_WAS_RUNNING=0

cleanup() {
  rm -rf "$TMPDIR"
}

restore_runtime_state() {
  set +e
  cd "$INSTALL_DIR" || exit 0
  docker compose up -d db redis app cron caddy >/dev/null 2>&1
  if [[ "$APP_WAS_RUNNING" == "1" && "$MAINTENANCE_WAS_ON" == "0" ]]; then
    docker compose exec -T -u www-data app php occ maintenance:mode --off >/dev/null 2>&1
  fi
}

trap 'restore_runtime_state; cleanup' EXIT

if [[ -f "$CREDENTIALS_FILE" ]]; then
  cp -a "$CREDENTIALS_FILE" "$TMPDIR/nextcloud-credentials.txt"
  chmod 600 "$TMPDIR/nextcloud-credentials.txt" || true
else
  echo "Credentials file not found at $CREDENTIALS_FILE; backup will not include the plaintext admin password note."
fi

if service_running app; then
  APP_WAS_RUNNING=1
  if docker compose exec -T -u www-data app php occ maintenance:mode --status 2>/dev/null | grep -qi 'enabled'; then
    MAINTENANCE_WAS_ON=1
  fi

  echo "Putting Nextcloud into maintenance mode..."
  docker compose exec -T -u www-data app php occ maintenance:mode --on >/dev/null

  : > "$TMPDIR/occ-status.txt"
  docker compose exec -T -u www-data app php occ status > "$TMPDIR/occ-status.txt" 2>/dev/null || true

  : > "$TMPDIR/app-list.txt"
  docker compose exec -T -u www-data app php occ app:list > "$TMPDIR/app-list.txt" 2>/dev/null || true
else
  echo "Nextcloud app container is not running; continuing with filesystem/database backup only."
fi

if ! service_running db; then
  echo "Starting MariaDB so it can be dumped..."
  docker compose up -d db >/dev/null
fi

echo "Waiting for MariaDB..."
for i in {1..120}; do
  if docker compose exec -T db sh -c '
    MYSQL_BIN="$(command -v mariadb || command -v mysql)"
    "$MYSQL_BIN" -uroot -p"$MARIADB_ROOT_PASSWORD" -e "SELECT 1" >/dev/null 2>&1
  ' >/dev/null 2>&1; then
    break
  fi
  sleep 2
  if [[ "$i" == "120" ]]; then
    echo "MariaDB did not become ready in time." >&2
    docker compose logs --tail=120 db >&2 || true
    exit 1
  fi
done

echo "Stopping web-facing containers during backup..."
docker compose stop cron caddy app >/dev/null 2>&1 || true

echo "Dumping MariaDB database..."
docker compose exec -T db sh -c '
  DUMP_BIN="$(command -v mariadb-dump || command -v mysqldump)"
  exec "$DUMP_BIN" \
    --single-transaction \
    --quick \
    --routines \
    --triggers \
    --events \
    -uroot \
    -p"$MARIADB_ROOT_PASSWORD" \
    "$MARIADB_DATABASE"
' | gzip -9 > "$TMPDIR/db.sql.gz"

cat > "$TMPDIR/manifest.env" <<EOF_MANIFEST
BACKUP_FORMAT=nextcloud-docker-compose-v1
BACKUP_CREATED_UTC=${TIMESTAMP}
SOURCE_INSTALL_DIR=${INSTALL_DIR}
SOURCE_DOMAIN=${DOMAIN:-}
SOURCE_OVERWRITEPROTOCOL=${OVERWRITEPROTOCOL:-}
SOURCE_OVERWRITECLIURL=${OVERWRITECLIURL:-}
MYSQL_DATABASE=${MYSQL_DATABASE:-nextcloud}
MYSQL_USER=${MYSQL_USER:-nextcloud}
HAS_CREDENTIALS_FILE=$([[ -s "$TMPDIR/nextcloud-credentials.txt" ]] && echo 1 || echo 0)
EOF_MANIFEST

echo "Archiving Nextcloud files, config, data, and apps..."
paths=()
for p in \
  .env \
  compose.yaml \
  Caddyfile \
  occ \
  update-nextcloud.sh \
  html \
  custom_apps \
  config \
  data \
  themes; do
  [[ -e "$p" ]] && paths+=("$p")
done

if [[ ${#paths[@]} -eq 0 ]]; then
  echo "No files found to archive; refusing to create an empty backup." >&2
  exit 1
fi

tar --numeric-owner \
  --exclude='./db' \
  --exclude='./redis' \
  --exclude='./caddy/data' \
  --exclude='./caddy/config' \
  --exclude='./backups' \
  -czf "$TMPDIR/install-files.tar.gz" \
  "${paths[@]}"

echo "Creating single compressed backup file..."
backup_members=(manifest.env db.sql.gz install-files.tar.gz)
[[ -s "$TMPDIR/occ-status.txt" ]] && backup_members+=(occ-status.txt)
[[ -s "$TMPDIR/app-list.txt" ]] && backup_members+=(app-list.txt)
[[ -s "$TMPDIR/nextcloud-credentials.txt" ]] && backup_members+=(nextcloud-credentials.txt)

tar -C "$TMPDIR" -czf "$BACKUP_FILE" "${backup_members[@]}"
chmod 600 "$BACKUP_FILE"

# Restore services before reporting success.
restore_runtime_state
trap cleanup EXIT

cat <<EOF_DONE

Backup complete.
File: $BACKUP_FILE

Restore with:
  sudo ./restore-nextcloud-backup.sh "$BACKUP_FILE"

Keep this file private. It contains your Nextcloud data, database, app config, credentials note, and secrets.
EOF_DONE
