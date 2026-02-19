#!/usr/bin/env bash
set -Eeuo pipefail

SERVICE_NAME="MTProxy.service"
SERVICE_PATH="/etc/systemd/system/${SERVICE_NAME}"
CONFIG_UPDATE_SERVICE_NAME="MTProxyConfigUpdate.service"
CONFIG_UPDATE_TIMER_NAME="MTProxyConfigUpdate.timer"
CONFIG_UPDATE_SERVICE_PATH="/etc/systemd/system/${CONFIG_UPDATE_SERVICE_NAME}"
CONFIG_UPDATE_TIMER_PATH="/etc/systemd/system/${CONFIG_UPDATE_TIMER_NAME}"
CONFIG_UPDATE_SCRIPT_PATH="/usr/local/bin/mtproxy-refresh-config.sh"
INSTALL_DIR="/opt/MTProxy"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info() { printf "${YELLOW}[INFO]${NC} %s\n" "$*"; }
success() { printf "${GREEN}[OK]${NC} %s\n" "$*"; }
error() { printf "${RED}[ERROR]${NC} %s\n" "$*" >&2; }

if [[ "${EUID}" -ne 0 ]]; then
  error "Please run as root (use: sudo bash uninstall.sh)"
  exit 1
fi

if command -v systemctl >/dev/null 2>&1; then
  if systemctl list-unit-files | grep -Fq "${CONFIG_UPDATE_TIMER_NAME}"; then
    info "Stopping and disabling ${CONFIG_UPDATE_TIMER_NAME}..."
    systemctl stop "${CONFIG_UPDATE_TIMER_NAME}" || true
    systemctl disable "${CONFIG_UPDATE_TIMER_NAME}" || true
  fi

  if systemctl list-unit-files | grep -Fq "${CONFIG_UPDATE_SERVICE_NAME}"; then
    systemctl stop "${CONFIG_UPDATE_SERVICE_NAME}" || true
  fi

  if systemctl list-unit-files | grep -Fq "${SERVICE_NAME}"; then
    info "Stopping and disabling ${SERVICE_NAME}..."
    systemctl stop "${SERVICE_NAME}" || true
    systemctl disable "${SERVICE_NAME}" || true
  fi
fi

if [[ -f "${CONFIG_UPDATE_TIMER_PATH}" ]]; then
  info "Removing timer file ${CONFIG_UPDATE_TIMER_PATH}..."
  rm -f "${CONFIG_UPDATE_TIMER_PATH}"
fi

if [[ -f "${CONFIG_UPDATE_SERVICE_PATH}" ]]; then
  info "Removing service file ${CONFIG_UPDATE_SERVICE_PATH}..."
  rm -f "${CONFIG_UPDATE_SERVICE_PATH}"
fi

if [[ -f "${SERVICE_PATH}" ]]; then
  info "Removing service file ${SERVICE_PATH}..."
  rm -f "${SERVICE_PATH}"
fi

if [[ -f "${CONFIG_UPDATE_SCRIPT_PATH}" ]]; then
  info "Removing helper script ${CONFIG_UPDATE_SCRIPT_PATH}..."
  rm -f "${CONFIG_UPDATE_SCRIPT_PATH}"
fi

if command -v systemctl >/dev/null 2>&1; then
  systemctl daemon-reload || true
fi

read -r -p "Remove source directory ${INSTALL_DIR}? [y/N]: " remove_src
remove_src="${remove_src,,}"
if [[ "${remove_src}" == "y" || "${remove_src}" == "yes" ]]; then
  rm -rf "${INSTALL_DIR}"
  success "Removed ${INSTALL_DIR}."
else
  info "Kept ${INSTALL_DIR}."
fi

success "Uninstall complete."
