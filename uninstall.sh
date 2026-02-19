#!/usr/bin/env bash
set -Eeuo pipefail

CONTAINER_NAME="mtproxy"
IMAGE="telegrammessenger/proxy"

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

if ! command -v docker >/dev/null 2>&1; then
  error "Docker not found. Nothing to uninstall."
  exit 1
fi

if docker ps -a --format '{{.Names}}' | grep -Fxq "${CONTAINER_NAME}"; then
  info "Stopping and removing container ${CONTAINER_NAME}..."
  docker rm -f "${CONTAINER_NAME}" >/dev/null
  success "Container removed."
else
  info "Container ${CONTAINER_NAME} not found."
fi

read -r -p "Remove Docker image ${IMAGE}? [y/N]: " remove_image
remove_image="${remove_image,,}"
if [[ "${remove_image}" == "y" || "${remove_image}" == "yes" ]]; then
  if docker image inspect "${IMAGE}" >/dev/null 2>&1; then
    info "Removing image ${IMAGE}..."
    docker rmi "${IMAGE}" >/dev/null || true
    success "Image removal requested."
  else
    info "Image ${IMAGE} not present."
  fi
fi

success "Uninstall complete. Docker remains installed."
