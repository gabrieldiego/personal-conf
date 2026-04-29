#!/usr/bin/env bash
set -Eeuo pipefail

# Usage:
#   sudo YES=1 ./uninstall-nextcloud.sh
#
# Optional:
#   INSTALL_DIR=/opt/nextcloud
#   YES=1
#   REMOVE_IMAGES=1
#   CLOSE_FIREWALL=1
#   PURGE_DOCKER=1
#
# Notes:
#   - This is destructive.
#   - It deletes Nextcloud data, database, config, Redis data, and Caddy data.
#   - PURGE_DOCKER=1 removes Docker packages and /var/lib/docker, which can destroy
#     other Docker projects on this machine.

INSTALL_DIR="${INSTALL_DIR:-/opt/nextcloud}"
YES="${YES:-0}"
REMOVE_IMAGES="${REMOVE_IMAGES:-0}"
CLOSE_FIREWALL="${CLOSE_FIREWALL:-0}"
PURGE_DOCKER="${PURGE_DOCKER:-0}"

CONTAINERS=(
  nextcloud-app
  nextcloud-cron
  nextcloud-db
  nextcloud-redis
  nextcloud-caddy
)

IMAGES=(
  nextcloud:stable-apache
  mariadb:lts
  redis:alpine
  caddy:2-alpine
)

if [[ $EUID -ne 0 ]]; then
  echo "Run as root: sudo YES=1 REMOVE_IMAGES=1 PURGE_DOCKER=1 $0" >&2
  exit 1
fi

echo "This will remove the local Nextcloud installation."
echo
echo "Install dir:       $INSTALL_DIR"
echo "Remove images:     $REMOVE_IMAGES"
echo "Close firewall:    $CLOSE_FIREWALL"
echo "Purge Docker:      $PURGE_DOCKER"
echo

if [[ "$PURGE_DOCKER" == "1" ]]; then
  echo "WARNING: PURGE_DOCKER=1 will remove Docker and /var/lib/docker."
  echo "That may destroy unrelated Docker containers, images, networks, and volumes."
  echo
fi

if [[ "$YES" != "1" ]]; then
  read -r -p "Type DELETE-NEXTCLOUD to continue: " CONFIRM
  if [[ "$CONFIRM" != "DELETE-NEXTCLOUD" ]]; then
    echo "Aborted."
    exit 1
  fi
fi

echo "Stopping compose stack if present..."

if [[ -f "$INSTALL_DIR/compose.yaml" ]]; then
  cd "$INSTALL_DIR"
  docker compose down --remove-orphans -v || true
elif [[ -f "$INSTALL_DIR/docker-compose.yml" ]]; then
  cd "$INSTALL_DIR"
  docker compose down --remove-orphans -v || true
else
  echo "No compose file found at $INSTALL_DIR; removing known containers directly."
fi

echo "Removing known Nextcloud containers..."

for c in "${CONTAINERS[@]}"; do
  if docker ps -a --format '{{.Names}}' | grep -qx "$c"; then
    docker rm -f "$c" || true
  fi
done

echo "Removing Nextcloud Docker network..."

docker network rm nextcloud >/dev/null 2>&1 || true

if [[ "$REMOVE_IMAGES" == "1" ]]; then
  echo "Removing Nextcloud-related images..."
  for img in "${IMAGES[@]}"; do
    docker image rm "$img" >/dev/null 2>&1 || true
  done
fi

echo "Removing install directory..."

if [[ -d "$INSTALL_DIR" ]]; then
  case "$INSTALL_DIR" in
    /opt/nextcloud|/srv/nextcloud|/home/*/nextcloud)
      rm -rf "$INSTALL_DIR"
      ;;
    *)
      echo "Refusing to remove unusual INSTALL_DIR automatically: $INSTALL_DIR" >&2
      echo "Remove it manually if this is intentional." >&2
      exit 1
      ;;
  esac
fi

echo "Removing credentials file if it appears to be for this install..."

if [[ -f /root/nextcloud-credentials.txt ]]; then
  if grep -q "Install dir: ${INSTALL_DIR}" /root/nextcloud-credentials.txt 2>/dev/null; then
    rm -f /root/nextcloud-credentials.txt
  else
    echo "Keeping /root/nextcloud-credentials.txt because it does not match this INSTALL_DIR."
  fi
fi

if [[ "$CLOSE_FIREWALL" == "1" ]] && command -v ufw >/dev/null 2>&1; then
  echo "Removing UFW allow rules for 80/tcp and 443/tcp if present..."
  ufw delete allow 80/tcp >/dev/null 2>&1 || true
  ufw delete allow 443/tcp >/dev/null 2>&1 || true
  ufw reload >/dev/null 2>&1 || true
fi

if [[ "$PURGE_DOCKER" == "1" ]]; then
  echo "Purging Docker packages and Docker data..."

  systemctl stop docker containerd >/dev/null 2>&1 || true

  apt-get purge -y \
    docker-ce \
    docker-ce-cli \
    containerd.io \
    docker-buildx-plugin \
    docker-compose-plugin \
    docker-ce-rootless-extras \
    docker.io \
    docker-compose \
    docker-compose-v2 \
    podman-docker \
    containerd \
    runc || true

  apt-get autoremove -y || true

  rm -rf /var/lib/docker
  rm -rf /var/lib/containerd
  rm -f /etc/apt/sources.list.d/docker.sources
  rm -f /etc/apt/keyrings/docker.asc
fi

echo
echo "Nextcloud uninstall completed."
echo
echo "For a fresh install, run something like:"
echo "  sudo DOMAIN=192.168.50.113 LOCAL_HTTP=1 ./install-nextcloud.sh"
