#!/usr/bin/env bash
set -Eeuo pipefail

SERVICE_NAME="MTProxy.service"
CONFIG_UPDATE_SERVICE_NAME="MTProxyConfigUpdate.service"
CONFIG_UPDATE_TIMER_NAME="MTProxyConfigUpdate.timer"

if ! command -v systemctl >/dev/null 2>&1; then
  echo "systemctl is not available on this host."
  exit 1
fi

echo "=== Service status ==="
systemctl status "${SERVICE_NAME}" --no-pager || true

echo
echo "=== Config update timer ==="
systemctl status "${CONFIG_UPDATE_TIMER_NAME}" --no-pager || true

echo
echo "=== Last config refresh run ==="
journalctl -u "${CONFIG_UPDATE_SERVICE_NAME}" -n 20 --no-pager || true

echo
echo "=== Last logs (tail 80) ==="
journalctl -u "${SERVICE_NAME}" -n 80 --no-pager || true

echo
echo "=== Listening sockets (443/8443/8888 typical) ==="
ss -ltnp 2>/dev/null | grep -E ':(443|8443|8888)\b' || true
