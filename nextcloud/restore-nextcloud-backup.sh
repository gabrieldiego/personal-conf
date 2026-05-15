#!/usr/bin/env bash
set -Eeuo pipefail

# Restore a backup created by backup-nextcloud.sh into a freshly installed
# Docker Compose Nextcloud deployment.
#
# This overwrites the restored deployment's data/config/apps/database, but it
# preserves the fresh target machine's local DOMAIN plus the public canonical
# Nextcloud URL. This supports a local HTTP server behind a public HTTPS reverse
# proxy / SSH tunnel, e.g. local http://192.168.50.55 and public
# https://nc.gt8projects.com.
#
# Usage:
#   sudo ./restore-nextcloud-backup.sh /path/to/nextcloud-backup.tar.gz
#
# Optional target overrides:
#   sudo DOMAIN=192.168.50.55 LOCAL_HTTP=1 ./restore-nextcloud-backup.sh backup.tar.gz
#   sudo DOMAIN=192.168.50.55 LOCAL_HTTP=1 PUBLIC_DOMAIN=nc.example.com ./restore-nextcloud-backup.sh backup.tar.gz
#   sudo PUBLIC_URL=https://nc.example.com ./restore-nextcloud-backup.sh backup.tar.gz
#   sudo OVERWRITECLIURL=https://nc.example.com ./restore-nextcloud-backup.sh backup.tar.gz

INSTALL_DIR="${INSTALL_DIR:-/opt/nextcloud}"
BACKUP_FILE="${1:-}"
REQUESTED_DOMAIN="${DOMAIN:-}"
REQUESTED_LOCAL_HTTP="${LOCAL_HTTP:-}"
REQUESTED_PUBLIC_DOMAIN="${PUBLIC_DOMAIN:-}"
REQUESTED_PUBLIC_PROTOCOL="${PUBLIC_PROTOCOL:-}"
REQUESTED_PUBLIC_URL="${PUBLIC_URL:-}"
REQUESTED_OVERWRITEHOST="${OVERWRITEHOST:-}"
REQUESTED_PROTOCOL="${OVERWRITEPROTOCOL:-}"
REQUESTED_CLI_URL="${OVERWRITECLIURL:-}"
REQUESTED_TRUSTED_DOMAINS="${NEXTCLOUD_TRUSTED_DOMAINS:-}"
REQUESTED_TRUSTED_PROXIES="${TRUSTED_PROXIES:-}"
REQUESTED_TRUSTED_PROXIES_EXTRA="${TRUSTED_PROXIES_EXTRA:-}"
REQUESTED_CADDY_SITE_ADDRESS="${CADDY_SITE_ADDRESS:-}"
TARGET_CREDENTIALS_FILE="${TARGET_CREDENTIALS_FILE:-/root/nextcloud-credentials.txt}"

if [[ $EUID -ne 0 ]]; then
  echo "Run as root: sudo $0 /path/to/nextcloud-backup.tar.gz" >&2
  exit 1
fi

if [[ -z "$BACKUP_FILE" ]]; then
  echo "Usage: sudo $0 /path/to/nextcloud-backup.tar.gz" >&2
  exit 1
fi

if [[ ! -f "$BACKUP_FILE" ]]; then
  echo "Backup file not found: $BACKUP_FILE" >&2
  exit 1
fi

# Convert relative backup paths before cd-ing into INSTALL_DIR.
BACKUP_FILE="$(readlink -f "$BACKUP_FILE")"

if [[ ! -d "$INSTALL_DIR" || ! -f "$INSTALL_DIR/compose.yaml" || ! -f "$INSTALL_DIR/.env" ]]; then
  echo "Could not find a fresh Nextcloud install at: $INSTALL_DIR" >&2
  echo "Run the installer first, then run this restore script." >&2
  exit 1
fi

command -v docker >/dev/null 2>&1 || { echo "docker is required." >&2; exit 1; }
command -v tar >/dev/null 2>&1 || { echo "tar is required." >&2; exit 1; }
command -v gzip >/dev/null 2>&1 || { echo "gzip is required." >&2; exit 1; }

service_running() {
  local service="$1"
  docker compose ps --services --filter "status=running" 2>/dev/null | grep -qx "$service"
}

primary_ipv4() {
  local ip=""
  ip="$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for (i=1;i<=NF;i++) if ($i=="src") {print $(i+1); exit}}' || true)"
  if [[ -z "$ip" ]]; then
    ip="$(hostname -I 2>/dev/null | awk '{print $1}' || true)"
  fi
  printf '%s\n' "$ip"
}

load_env_file() {
  local file="$1"
  set -a
  # shellcheck disable=SC1090
  . "$file"
  set +a
}

env_get() {
  local file="$1"
  local key="$2"
  if [[ -f "$file" ]]; then
    grep -E "^${key}=" "$file" | tail -n1 | cut -d= -f2- || true
  fi
}

occ_get() {
  local key="$1"
  if service_running app; then
    docker compose exec -T -u www-data app php occ config:system:get "$key" 2>/dev/null || true
  fi
}

url_scheme() {
  printf '%s\n' "$1" | sed -nE 's|^([A-Za-z][A-Za-z0-9+.-]*)://.*|\1|p'
}

url_host() {
  printf '%s\n' "$1" | sed -nE 's|^[A-Za-z][A-Za-z0-9+.-]*://([^/]+).*|\1|p'
}

append_unique_words() {
  local result="$1"
  shift
  local word
  for word in "$@"; do
    [[ -z "$word" ]] && continue
    if ! printf ' %s ' "$result" | grep -Fq " $word "; then
      result="${result:+$result }$word"
    fi
  done
  printf '%s' "$result"
}

repair_compose_for_reverse_proxy_env() {
  [[ -f compose.yaml ]] || return 0
  sed -i -E 's/(OVERWRITEHOST:[[:space:]]*)\$\{DOMAIN\}/\1${OVERWRITEHOST}/' compose.yaml
  sed -i -E 's/(TRUSTED_PROXIES:[[:space:]]*)caddy/\1${TRUSTED_PROXIES}/' compose.yaml
}

upsert_env() {
  local file="$1"
  local key="$2"
  local value="$3"
  local escaped
  escaped="$(printf '%s' "$value" | sed -e 's/[&/\\]/\\&/g')"
  if grep -qE "^${key}=" "$file"; then
    sed -i "s/^${key}=.*/${key}=${escaped}/" "$file"
  else
    printf '%s=%s\n' "$key" "$value" >> "$file"
  fi
}

label_get() {
  local file="$1"
  local label="$2"
  if [[ -f "$file" ]]; then
    sed -nE "s/^${label}:[[:space:]]*//p" "$file" | head -n1 || true
  fi
}

write_credentials_file() {
  local source_credentials="$TMPDIR/nextcloud-credentials.txt"
  local admin_user=""
  local admin_password=""
  local mysql_database=""
  local mysql_user=""
  local mysql_password=""
  local mysql_root_password=""

  if [[ -f "$source_credentials" ]]; then
    admin_user="$(label_get "$source_credentials" "Admin user")"
    admin_password="$(label_get "$source_credentials" "Admin password")"
    mysql_database="$(label_get "$source_credentials" "MariaDB database")"
    mysql_user="$(label_get "$source_credentials" "MariaDB user")"
    mysql_password="$(label_get "$source_credentials" "MariaDB password")"
    mysql_root_password="$(label_get "$source_credentials" "MariaDB root password")"
  fi

  # The restored .env is authoritative for DB credentials because Compose uses it.
  admin_user="${admin_user:-$(env_get .env NEXTCLOUD_ADMIN_USER)}"
  admin_password="${admin_password:-$(env_get .env NEXTCLOUD_ADMIN_PASSWORD)}"
  mysql_database="$(env_get .env MYSQL_DATABASE)"
  mysql_user="$(env_get .env MYSQL_USER)"
  mysql_password="$(env_get .env MYSQL_PASSWORD)"
  mysql_root_password="$(env_get .env MYSQL_ROOT_PASSWORD)"

  admin_user="${admin_user:-admin}"
  admin_password="${admin_password:-UNKNOWN - not found in backup; reset with: cd ${INSTALL_DIR} && sudo ./occ user:resetpassword ${admin_user}}"
  mysql_database="${mysql_database:-nextcloud}"
  mysql_user="${mysql_user:-nextcloud}"
  mysql_password="${mysql_password:-UNKNOWN - see ${INSTALL_DIR}/.env}"
  mysql_root_password="${mysql_root_password:-UNKNOWN - see ${INSTALL_DIR}/.env}"

  cat > "$TARGET_CREDENTIALS_FILE" <<EOF_CREDS
Nextcloud URL: ${TARGET_CLI_URL}
Local HTTP URL: http://${TARGET_DOMAIN}
Install dir: ${INSTALL_DIR}

Admin user: ${admin_user}
Admin password: ${admin_password}

MariaDB database: ${mysql_database}
MariaDB user: ${mysql_user}
MariaDB password: ${mysql_password}
MariaDB root password: ${mysql_root_password}

Restored from backup: ${BACKUP_FILE}
Credentials file regenerated at UTC: $(date -u +%Y-%m-%dT%H:%M:%SZ)
EOF_CREDS
  chmod 600 "$TARGET_CREDENTIALS_FILE"
}


write_caddyfile() {
  local file="$1"
  local domain="$2"
  local local_http="$3"
  local site_address="$4"

  if [[ "$local_http" == "1" ]]; then
    cat > "$file" <<EOF_CADDY_HTTP
${site_address:-:80} {
	encode zstd gzip

	redir /.well-known/carddav /remote.php/dav 301
	redir /.well-known/caldav /remote.php/dav 301

	reverse_proxy app:80
}
EOF_CADDY_HTTP
  else
    cat > "$file" <<EOF_CADDY_HTTPS
${site_address:-$domain} {
	encode zstd gzip

	redir /.well-known/carddav /remote.php/dav 301
	redir /.well-known/caldav /remote.php/dav 301

	header {
		Strict-Transport-Security "max-age=15552000; includeSubDomains"
	}

	reverse_proxy app:80
}
EOF_CADDY_HTTPS
  fi
}

detect_target_url_config() {
  # Precedence:
  #   1. Explicit restore-time env overrides
  #   2. Fresh target .env written by the installer
  #   3. Fresh target Nextcloud occ config, if app is running
  #   4. Parsed public/overwrite URL values
  #   5. Machine primary IPv4 + local HTTP fallback

  local env_domain env_local_http env_public_domain env_public_protocol env_public_url
  local env_overwritehost env_protocol env_cli_url env_trusted_domains env_trusted_proxies env_caddy_site_address
  local occ_protocol occ_cli_url
  local parsed_public_domain parsed_public_protocol parsed_cli_domain parsed_cli_protocol

  env_domain="$(env_get .env DOMAIN)"
  env_local_http="$(env_get .env LOCAL_HTTP)"
  env_public_domain="$(env_get .env PUBLIC_DOMAIN)"
  env_public_protocol="$(env_get .env PUBLIC_PROTOCOL)"
  env_public_url="$(env_get .env PUBLIC_URL)"
  env_overwritehost="$(env_get .env OVERWRITEHOST)"
  env_protocol="$(env_get .env OVERWRITEPROTOCOL)"
  env_cli_url="$(env_get .env OVERWRITECLIURL)"
  env_trusted_domains="$(env_get .env NEXTCLOUD_TRUSTED_DOMAINS)"
  env_trusted_proxies="$(env_get .env TRUSTED_PROXIES)"
  env_caddy_site_address="$(env_get .env CADDY_SITE_ADDRESS)"

  occ_protocol="$(occ_get overwriteprotocol)"
  occ_cli_url="$(occ_get overwrite.cli.url)"

  TARGET_DOMAIN="${REQUESTED_DOMAIN:-$env_domain}"
  TARGET_DOMAIN="${TARGET_DOMAIN:-$(primary_ipv4)}"

  TARGET_LOCAL_HTTP="${REQUESTED_LOCAL_HTTP:-$env_local_http}"
  TARGET_LOCAL_HTTP="${TARGET_LOCAL_HTTP:-0}"

  TARGET_PUBLIC_DOMAIN="${REQUESTED_PUBLIC_DOMAIN:-$env_public_domain}"
  TARGET_PUBLIC_PROTOCOL="${REQUESTED_PUBLIC_PROTOCOL:-$env_public_protocol}"
  TARGET_PUBLIC_PROTOCOL="${TARGET_PUBLIC_PROTOCOL:-https}"
  TARGET_PUBLIC_URL="${REQUESTED_PUBLIC_URL:-$env_public_url}"

  if [[ -n "$TARGET_PUBLIC_URL" ]]; then
    parsed_public_domain="$(url_host "$TARGET_PUBLIC_URL")"
    parsed_public_protocol="$(url_scheme "$TARGET_PUBLIC_URL")"
    TARGET_PUBLIC_DOMAIN="${TARGET_PUBLIC_DOMAIN:-$parsed_public_domain}"
    TARGET_PUBLIC_PROTOCOL="${parsed_public_protocol:-$TARGET_PUBLIC_PROTOCOL}"
  fi

  TARGET_OVERWRITEHOST="${REQUESTED_OVERWRITEHOST:-$env_overwritehost}"
  TARGET_OVERWRITEHOST="${TARGET_OVERWRITEHOST:-${TARGET_PUBLIC_DOMAIN:-$TARGET_DOMAIN}}"

  TARGET_PROTOCOL="${REQUESTED_PROTOCOL:-$env_protocol}"
  if [[ -z "$TARGET_PROTOCOL" && -n "$occ_protocol" ]]; then
    TARGET_PROTOCOL="$occ_protocol"
  fi
  if [[ -z "$TARGET_PROTOCOL" ]]; then
    if [[ -n "$TARGET_PUBLIC_DOMAIN" || -n "$TARGET_PUBLIC_URL" ]]; then
      TARGET_PROTOCOL="$TARGET_PUBLIC_PROTOCOL"
    elif [[ "$TARGET_LOCAL_HTTP" == "1" ]]; then
      TARGET_PROTOCOL="http"
    else
      TARGET_PROTOCOL="https"
    fi
  fi

  TARGET_CLI_URL="${REQUESTED_CLI_URL:-$env_cli_url}"
  if [[ -z "$TARGET_CLI_URL" && -n "$TARGET_PUBLIC_URL" ]]; then
    TARGET_CLI_URL="$TARGET_PUBLIC_URL"
  fi
  if [[ -z "$TARGET_CLI_URL" && -n "$occ_cli_url" ]]; then
    TARGET_CLI_URL="$occ_cli_url"
  fi
  if [[ -z "$TARGET_CLI_URL" || -n "$REQUESTED_DOMAIN" || -n "$REQUESTED_PUBLIC_DOMAIN" || -n "$REQUESTED_PUBLIC_URL" || -n "$REQUESTED_PROTOCOL" || -n "$REQUESTED_OVERWRITEHOST" ]]; then
    TARGET_CLI_URL="${TARGET_PROTOCOL}://${TARGET_OVERWRITEHOST}"
  fi

  parsed_cli_domain="$(url_host "$TARGET_CLI_URL")"
  parsed_cli_protocol="$(url_scheme "$TARGET_CLI_URL")"
  TARGET_OVERWRITEHOST="${TARGET_OVERWRITEHOST:-$parsed_cli_domain}"
  TARGET_PROTOCOL="${TARGET_PROTOCOL:-$parsed_cli_protocol}"

  TARGET_TRUSTED_DOMAINS="${REQUESTED_TRUSTED_DOMAINS:-$env_trusted_domains}"
  TARGET_TRUSTED_DOMAINS="${TARGET_TRUSTED_DOMAINS:-$TARGET_DOMAIN}"
  TARGET_TRUSTED_DOMAINS="$(append_unique_words "$TARGET_TRUSTED_DOMAINS" "$TARGET_OVERWRITEHOST" "$TARGET_PUBLIC_DOMAIN" "$parsed_cli_domain")"

  TARGET_TRUSTED_PROXIES="${REQUESTED_TRUSTED_PROXIES:-$env_trusted_proxies}"
  TARGET_TRUSTED_PROXIES="${TARGET_TRUSTED_PROXIES:-caddy}"
  TARGET_TRUSTED_PROXIES="$(append_unique_words "$TARGET_TRUSTED_PROXIES" $REQUESTED_TRUSTED_PROXIES_EXTRA)"

  TARGET_CADDY_SITE_ADDRESS="${REQUESTED_CADDY_SITE_ADDRESS:-$env_caddy_site_address}"
  if [[ -z "$TARGET_CADDY_SITE_ADDRESS" ]]; then
    if [[ "$TARGET_LOCAL_HTTP" == "1" ]]; then
      TARGET_CADDY_SITE_ADDRESS=":80"
    else
      TARGET_CADDY_SITE_ADDRESS="$TARGET_DOMAIN"
    fi
  fi

  if [[ -z "$TARGET_DOMAIN" ]]; then
    echo "Could not determine target DOMAIN. Set DOMAIN=... and retry." >&2
    exit 1
  fi
}

cd "$INSTALL_DIR"

# Capture target URL settings BEFORE restoring the backup's config/database.
detect_target_url_config

TMPDIR="$(mktemp -d)"
cleanup() {
  rm -rf "$TMPDIR"
}
trap cleanup EXIT

echo "Extracting backup container..."
tar -xzf "$BACKUP_FILE" -C "$TMPDIR"

for required in manifest.env db.sql.gz install-files.tar.gz; do
  if [[ ! -f "$TMPDIR/$required" ]]; then
    echo "Invalid backup: missing $required" >&2
    exit 1
  fi
done

if ! grep -Eq '^BACKUP_FORMAT=nextcloud-docker-compose-v1$' "$TMPDIR/manifest.env"; then
  echo "Unsupported or unknown backup format." >&2
  exit 1
fi

# Basic path traversal check before extracting the file payload.
if tar -tzf "$TMPDIR/install-files.tar.gz" | grep -Eq '(^/|(^|/)\.\.(/|$))'; then
  echo "Refusing to restore: backup contains unsafe paths." >&2
  exit 1
fi

cat <<EOF_WARN
About to overwrite this Nextcloud deployment:
  Install dir: $INSTALL_DIR
  Preserved local domain: $TARGET_DOMAIN
  Preserved local HTTP mode: $TARGET_LOCAL_HTTP
  Preserved public/canonical host: $TARGET_OVERWRITEHOST
  Preserved public/canonical protocol: $TARGET_PROTOCOL
  Preserved public/canonical URL: $TARGET_CLI_URL
  Preserved trusted domains: $TARGET_TRUSTED_DOMAINS
  Preserved trusted proxies: $TARGET_TRUSTED_PROXIES

EOF_WARN

if [[ "${ASSUME_YES:-0}" != "1" ]]; then
  read -r -p "Type RESTORE to continue: " answer
  if [[ "$answer" != "RESTORE" ]]; then
    echo "Restore cancelled."
    exit 1
  fi
fi

echo "Stopping current deployment..."
docker compose down >/dev/null

STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
mkdir -p "restore-safety-${STAMP}"
for p in .env Caddyfile compose.yaml config; do
  if [[ -e "$p" ]]; then
    cp -a "$p" "restore-safety-${STAMP}/" 2>/dev/null || true
  fi
done
if [[ -f "$TARGET_CREDENTIALS_FILE" ]]; then
  cp -a "$TARGET_CREDENTIALS_FILE" "restore-safety-${STAMP}/nextcloud-credentials.before-restore.txt" 2>/dev/null || true
fi

echo "Removing existing restored paths..."
rm -rf html custom_apps config data themes redis db

echo "Restoring files, config, data, apps, and compose metadata..."
tar --numeric-owner -xzf "$TMPDIR/install-files.tar.gz" -C "$INSTALL_DIR"

if [[ ! -f .env ]]; then
  echo "Restored backup did not contain .env; cannot continue." >&2
  exit 1
fi

# Keep restored DB/app secrets, but replace network identity with the fresh target's values.
repair_compose_for_reverse_proxy_env
upsert_env .env DOMAIN "$TARGET_DOMAIN"
upsert_env .env LOCAL_HTTP "$TARGET_LOCAL_HTTP"
upsert_env .env PUBLIC_DOMAIN "$TARGET_PUBLIC_DOMAIN"
upsert_env .env PUBLIC_PROTOCOL "$TARGET_PUBLIC_PROTOCOL"
upsert_env .env PUBLIC_URL "$TARGET_PUBLIC_URL"
upsert_env .env NEXTCLOUD_TRUSTED_DOMAINS "$TARGET_TRUSTED_DOMAINS"
upsert_env .env TRUSTED_PROXIES "$TARGET_TRUSTED_PROXIES"
upsert_env .env OVERWRITEHOST "$TARGET_OVERWRITEHOST"
upsert_env .env OVERWRITEPROTOCOL "$TARGET_PROTOCOL"
upsert_env .env OVERWRITECLIURL "$TARGET_CLI_URL"
upsert_env .env CADDY_SITE_ADDRESS "$TARGET_CADDY_SITE_ADDRESS"
chmod 600 .env

write_caddyfile Caddyfile "$TARGET_DOMAIN" "$TARGET_LOCAL_HTTP" "$TARGET_CADDY_SITE_ADDRESS"

# Reload restored .env so Compose initializes MariaDB with the restored credentials.
load_env_file ./.env

echo "Starting MariaDB for clean initialization..."
docker compose up -d db >/dev/null

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

echo "Importing Nextcloud database..."
# Import as MariaDB root through the container's local Unix socket.
gzip -dc "$TMPDIR/db.sql.gz" | docker compose exec -T db sh -c '
  MYSQL_BIN="$(command -v mariadb || command -v mysql)"
  exec "$MYSQL_BIN" -uroot -p"$MARIADB_ROOT_PASSWORD" "$MARIADB_DATABASE"
'

echo "Starting full deployment..."
docker compose up -d >/dev/null

echo "Waiting for Nextcloud app container..."
for i in {1..120}; do
  if docker compose exec -T -u www-data app php occ status >/dev/null 2>&1; then
    break
  fi
  sleep 2
  if [[ "$i" == "120" ]]; then
    echo "Nextcloud app did not become ready in time." >&2
    docker compose logs --tail=120 app >&2 || true
    exit 1
  fi
done

echo "Reapplying target domain settings inside Nextcloud..."
idx=0
for domain in $TARGET_TRUSTED_DOMAINS; do
  docker compose exec -T -u www-data app php occ config:system:set trusted_domains "$idx" --value="$domain" >/dev/null || true
  idx=$((idx + 1))
done
for i in $(seq "$idx" 20); do
  docker compose exec -T -u www-data app php occ config:system:delete trusted_domains "$i" >/dev/null 2>&1 || true
done

docker compose exec -T -u www-data app php occ config:system:set overwritehost --value="$TARGET_OVERWRITEHOST" >/dev/null || true
docker compose exec -T -u www-data app php occ config:system:set overwriteprotocol --value="$TARGET_PROTOCOL" >/dev/null || true
docker compose exec -T -u www-data app php occ config:system:set overwrite.cli.url --value="$TARGET_CLI_URL" >/dev/null || true

idx=0
for proxy in $TARGET_TRUSTED_PROXIES; do
  docker compose exec -T -u www-data app php occ config:system:set trusted_proxies "$idx" --value="$proxy" >/dev/null || true
  idx=$((idx + 1))
done
for i in $(seq "$idx" 20); do
  docker compose exec -T -u www-data app php occ config:system:delete trusted_proxies "$i" >/dev/null 2>&1 || true
done

docker compose exec -T -u www-data app php occ maintenance:mode --off >/dev/null || true
docker compose exec -T -u www-data app php occ maintenance:update:htaccess >/dev/null || true
docker compose exec -T -u www-data app php occ maintenance:repair >/dev/null || true

echo "Writing restored credentials note..."
write_credentials_file

cat <<EOF_DONE

Restore complete.
URL: $TARGET_CLI_URL

A small pre-restore safety copy of .env/Caddyfile/compose/config, if present, was saved in:
  $INSTALL_DIR/restore-safety-${STAMP}

Credentials saved at: $TARGET_CREDENTIALS_FILE

Check status with:
  cd $INSTALL_DIR
  sudo docker compose ps
  sudo ./occ status
EOF_DONE
