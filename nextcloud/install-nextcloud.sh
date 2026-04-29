#!/usr/bin/env bash
set -Eeuo pipefail

# Required:
#   DOMAIN=nc.example.com sudo ./install-nextcloud.sh
#
# Optional:
#   EMAIL=you@example.com
#   INSTALL_DIR=/opt/nextcloud
#   ADMIN_USER=admin
#   ADMIN_PASSWORD='your-password'
#   PHP_MEMORY_LIMIT=512M
#   PHP_UPLOAD_LIMIT=10G
#   DEFAULT_PHONE_REGION=US

DOMAIN="${DOMAIN:-}"
EMAIL="${EMAIL:-admin@example.com}"
INSTALL_DIR="${INSTALL_DIR:-/opt/nextcloud}"
ADMIN_USER="${ADMIN_USER:-admin}"
ADMIN_PASSWORD="${ADMIN_PASSWORD:-}"
MYSQL_DATABASE="${MYSQL_DATABASE:-nextcloud}"
MYSQL_USER="${MYSQL_USER:-nextcloud}"
PHP_MEMORY_LIMIT="${PHP_MEMORY_LIMIT:-512M}"
PHP_UPLOAD_LIMIT="${PHP_UPLOAD_LIMIT:-10G}"
APACHE_BODY_LIMIT="${APACHE_BODY_LIMIT:-0}"
DEFAULT_PHONE_REGION="${DEFAULT_PHONE_REGION:-US}"
LOCAL_HTTP="${LOCAL_HTTP:-0}"
OVERWRITEPROTOCOL="${OVERWRITEPROTOCOL:-https}"
FORCE_REINSTALL="${FORCE_REINSTALL:-0}"
OVERWRITECLIURL="${OVERWRITECLIURL:-}"
CADDY_SITE_ADDRESS="${CADDY_SITE_ADDRESS:-}"

if [[ $EUID -ne 0 ]]; then
  echo "Run as root: sudo DOMAIN=nc.example.com LOCAL_HTTP=1 $0" >&2
  exit 1
fi

if [[ -z "$DOMAIN" ]]; then
  echo "Missing DOMAIN. Example:" >&2
  echo "  sudo DOMAIN=nc.example.com LOCAL_HTTP=1 EMAIL=you@example.com $0" >&2
  exit 1
fi

random_secret() {
  openssl rand -base64 36 | tr -d '\n'
}

ensure_openssl() {
  if ! command -v openssl >/dev/null 2>&1; then
    apt-get update
    apt-get install -y openssl
  fi
}

ensure_openssl

MYSQL_ROOT_PASSWORD="$(random_secret)"
MYSQL_PASSWORD="$(random_secret)"

if [[ -z "$ADMIN_PASSWORD" ]]; then
  ADMIN_PASSWORD="$(random_secret)"
fi

install_docker() {
  if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
    systemctl enable --now docker >/dev/null 2>&1 || true
    return
  fi

  apt-get update
  apt-get install -y ca-certificates curl openssl rsync gnupg lsb-release

  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc

  CODENAME="$(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")"
  ARCH="$(dpkg --print-architecture)"

  cat >/etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: ${CODENAME}
Components: stable
Architectures: ${ARCH}
Signed-By: /etc/apt/keyrings/docker.asc
EOF

  apt-get update
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  systemctl enable --now docker
}

configure_firewall_best_effort() {
  if command -v ufw >/dev/null 2>&1 && ufw status | grep -q "Status: active"; then
    ufw allow 80/tcp || true
    ufw allow 443/tcp || true
  fi
}

install_docker
configure_firewall_best_effort

if [[ -e "$INSTALL_DIR/compose.yaml" || -e "$INSTALL_DIR/.env" || -d "$INSTALL_DIR/db/mysql" ]]; then
  if [[ "$FORCE_REINSTALL" != "1" ]]; then
    echo "Existing Nextcloud install appears to exist at: $INSTALL_DIR" >&2
    echo "Refusing to overwrite it because rerunning would generate new DB passwords." >&2
    echo "Use the uninstall script first, or run with FORCE_REINSTALL=1 only if you know what you are doing." >&2
    exit 1
  fi
fi

if [[ "$LOCAL_HTTP" == "1" ]]; then
  OVERWRITEPROTOCOL="http"
  OVERWRITECLIURL="${OVERWRITECLIURL:-http://${DOMAIN}}"
  CADDY_SITE_ADDRESS="${CADDY_SITE_ADDRESS:-:80}"
else
  OVERWRITEPROTOCOL="https"
  OVERWRITECLIURL="${OVERWRITECLIURL:-https://${DOMAIN}}"
  CADDY_SITE_ADDRESS="${CADDY_SITE_ADDRESS:-${DOMAIN}}"
fi

mkdir -p "$INSTALL_DIR"/{db,redis,html,custom_apps,config,data,themes,caddy/data,caddy/config}
cd "$INSTALL_DIR"

cat >.env <<EOF
DOMAIN=${DOMAIN}
EMAIL=${EMAIL}

MYSQL_ROOT_PASSWORD=${MYSQL_ROOT_PASSWORD}
MYSQL_DATABASE=${MYSQL_DATABASE}
MYSQL_USER=${MYSQL_USER}
MYSQL_PASSWORD=${MYSQL_PASSWORD}

NEXTCLOUD_ADMIN_USER=${ADMIN_USER}
NEXTCLOUD_ADMIN_PASSWORD=${ADMIN_PASSWORD}
NEXTCLOUD_TRUSTED_DOMAINS=${DOMAIN}

PHP_MEMORY_LIMIT=${PHP_MEMORY_LIMIT}
PHP_UPLOAD_LIMIT=${PHP_UPLOAD_LIMIT}
APACHE_BODY_LIMIT=${APACHE_BODY_LIMIT}
OVERWRITEPROTOCOL=${OVERWRITEPROTOCOL}
OVERWRITECLIURL=${OVERWRITECLIURL}
EOF

chmod 600 .env

if [[ "$LOCAL_HTTP" == "1" ]]; then
  cat >Caddyfile <<EOF
${CADDY_SITE_ADDRESS} {
	encode zstd gzip

	redir /.well-known/carddav /remote.php/dav 301
	redir /.well-known/caldav /remote.php/dav 301

	reverse_proxy app:80
}
EOF
else
  cat >Caddyfile <<EOF
${CADDY_SITE_ADDRESS} {
	encode zstd gzip

	redir /.well-known/carddav /remote.php/dav 301
	redir /.well-known/caldav /remote.php/dav 301

	header {
		Strict-Transport-Security "max-age=15552000; includeSubDomains"
	}

	reverse_proxy app:80
}
EOF
fi

cat >compose.yaml <<'EOF'
services:
  db:
    image: mariadb:lts
    container_name: nextcloud-db
    restart: unless-stopped
    command: --transaction-isolation=READ-COMMITTED --binlog-format=ROW
    environment:
      MARIADB_ROOT_PASSWORD: ${MYSQL_ROOT_PASSWORD}
      MARIADB_DATABASE: ${MYSQL_DATABASE}
      MARIADB_USER: ${MYSQL_USER}
      MARIADB_PASSWORD: ${MYSQL_PASSWORD}
    volumes:
      - ./db:/var/lib/mysql
    networks:
      - nextcloud

  redis:
    image: redis:alpine
    container_name: nextcloud-redis
    restart: unless-stopped
    command: redis-server --appendonly yes
    volumes:
      - ./redis:/data
    networks:
      - nextcloud

  app:
    image: nextcloud:stable-apache
    container_name: nextcloud-app
    restart: unless-stopped
    depends_on:
      - db
      - redis
    environment:
      MYSQL_HOST: db
      MYSQL_DATABASE: ${MYSQL_DATABASE}
      MYSQL_USER: ${MYSQL_USER}
      MYSQL_PASSWORD: ${MYSQL_PASSWORD}

      NEXTCLOUD_ADMIN_USER: ${NEXTCLOUD_ADMIN_USER}
      NEXTCLOUD_ADMIN_PASSWORD: ${NEXTCLOUD_ADMIN_PASSWORD}
      NEXTCLOUD_TRUSTED_DOMAINS: ${NEXTCLOUD_TRUSTED_DOMAINS}

      REDIS_HOST: redis

      OVERWRITEHOST: ${DOMAIN}
      OVERWRITEPROTOCOL: ${OVERWRITEPROTOCOL}
      OVERWRITECLIURL: ${OVERWRITECLIURL}
      TRUSTED_PROXIES: caddy

      PHP_MEMORY_LIMIT: ${PHP_MEMORY_LIMIT}
      PHP_UPLOAD_LIMIT: ${PHP_UPLOAD_LIMIT}
      APACHE_BODY_LIMIT: ${APACHE_BODY_LIMIT}
    volumes:
      - ./html:/var/www/html
      - ./custom_apps:/var/www/html/custom_apps
      - ./config:/var/www/html/config
      - ./data:/var/www/html/data
      - ./themes:/var/www/html/themes
    networks:
      - nextcloud

  cron:
    image: nextcloud:stable-apache
    container_name: nextcloud-cron
    restart: unless-stopped
    depends_on:
      - db
      - redis
    entrypoint: /cron.sh
    volumes:
      - ./html:/var/www/html
      - ./custom_apps:/var/www/html/custom_apps
      - ./config:/var/www/html/config
      - ./data:/var/www/html/data
      - ./themes:/var/www/html/themes
    networks:
      - nextcloud

  caddy:
    image: caddy:2-alpine
    container_name: nextcloud-caddy
    restart: unless-stopped
    depends_on:
      - app
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile:ro
      - ./caddy/data:/data
      - ./caddy/config:/config
    networks:
      - nextcloud

networks:
  nextcloud:
    name: nextcloud
EOF

cat >occ <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
cd "$(dirname "$0")"
docker compose exec -u www-data app php occ "$@"
EOF
chmod +x occ

cat >update-nextcloud.sh <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
cd "$(dirname "$0")"
docker compose pull
docker compose up -d
docker compose exec -u www-data app php occ upgrade || true
docker compose exec -u www-data app php occ maintenance:repair || true
EOF
chmod +x update-nextcloud.sh

docker compose pull
docker compose up -d

echo "Waiting for Nextcloud initial installation..."
INSTALLED="0"

for i in {1..120}; do
  if docker compose exec -T -u www-data app php occ status 2>/dev/null | grep -q "installed: true"; then
    INSTALLED="1"
    break
  fi
  sleep 5
done

if [[ "$INSTALLED" != "1" ]]; then
  echo "Nextcloud did not report a successful installation in time." >&2
  echo "Recent app logs:" >&2
  docker compose logs --tail=120 app >&2 || true
  exit 1
fi

docker compose exec -T -u www-data app php occ background:cron || true
docker compose exec -T -u www-data app php occ config:system:set default_phone_region --value="$DEFAULT_PHONE_REGION" || true
docker compose exec -T -u www-data app php occ maintenance:update:htaccess || true

cat >/root/nextcloud-credentials.txt <<EOF
Nextcloud URL: ${OVERWRITEPROTOCOL}://${DOMAIN}
Install dir: ${INSTALL_DIR}

Admin user: ${ADMIN_USER}
Admin password: ${ADMIN_PASSWORD}

MariaDB database: ${MYSQL_DATABASE}
MariaDB user: ${MYSQL_USER}
MariaDB password: ${MYSQL_PASSWORD}
MariaDB root password: ${MYSQL_ROOT_PASSWORD}
EOF
chmod 600 /root/nextcloud-credentials.txt

echo
echo "Nextcloud is installed."
echo "URL: ${OVERWRITECLIURL}"
echo "Admin user: ${ADMIN_USER}"
echo "Credentials saved at: /root/nextcloud-credentials.txt"
echo
echo "Useful commands:"
echo "  cd ${INSTALL_DIR}"
echo "  sudo ./occ status"
echo "  sudo docker compose ps"
echo "  sudo docker compose logs -f app"
