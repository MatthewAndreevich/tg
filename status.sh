#!/usr/bin/env bash
set -Eeuo pipefail

CONTAINER_NAME="mtproxy"

if ! command -v docker >/dev/null 2>&1; then
  echo "Docker is not installed."
  exit 1
fi

echo "=== Docker service ==="
if command -v systemctl >/dev/null 2>&1; then
  systemctl is-active docker 2>/dev/null || true
else
  echo "systemctl not available"
fi

echo
echo "=== Container state ==="
if docker ps -a --format '{{.Names}}' | grep -Fxq "${CONTAINER_NAME}"; then
  docker ps -a --filter "name=^/${CONTAINER_NAME}$" --format 'Name={{.Names}} Status={{.Status}} Ports={{.Ports}}'
else
  echo "Container ${CONTAINER_NAME} not found"
  exit 0
fi

echo
echo "=== Port mapping ==="
docker port "${CONTAINER_NAME}" || true

echo
echo "=== Recent logs (tail 50) ==="
docker logs --tail 50 "${CONTAINER_NAME}" 2>&1 || true
