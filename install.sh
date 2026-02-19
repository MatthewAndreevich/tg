#!/usr/bin/env bash
set -Eeuo pipefail

IMAGE="telegrammessenger/proxy"
CONTAINER_NAME="mtproxy"
DEFAULT_PORT="8443"
DEFAULT_TLS_DOMAIN="cloudflare.com"
DEFAULT_WORKERS="1"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info() { printf "${BLUE}[INFO]${NC} %s\n" "$*"; }
warn() { printf "${YELLOW}[WARN]${NC} %s\n" "$*"; }
error() { printf "${RED}[ERROR]${NC} %s\n" "$*" >&2; }
success() { printf "${GREEN}[OK]${NC} %s\n" "$*"; }

trap 'error "Installation failed on line $LINENO."; exit 1' ERR

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    error "Please run as root (use: sudo bash install.sh)"
    exit 1
  fi
}

is_tty() {
  [[ -t 0 ]]
}

detect_os() {
  if [[ ! -f /etc/os-release ]]; then
    error "Cannot detect OS. /etc/os-release not found."
    exit 1
  fi

  # shellcheck disable=SC1091
  source /etc/os-release
  case "${ID:-}" in
    ubuntu|debian) success "Detected supported OS: ${PRETTY_NAME:-$ID}" ;;
    *)
      if [[ "${ID_LIKE:-}" == *"debian"* ]]; then
        success "Detected Debian-like OS: ${PRETTY_NAME:-$ID}"
      else
        error "Unsupported OS: ${PRETTY_NAME:-unknown}. Use Ubuntu or Debian."
        exit 1
      fi
      ;;
  esac
}

install_docker() {
  if command -v docker >/dev/null 2>&1; then
    success "Docker already installed."
  else
    info "Installing Docker using official convenience script..."
    apt-get update -y
    apt-get install -y ca-certificates curl gnupg lsb-release
    curl -fsSL https://get.docker.com | sh
    success "Docker installed."
  fi

  info "Enabling and starting Docker service..."
  systemctl enable docker >/dev/null 2>&1 || true
  systemctl restart docker
  systemctl is-active --quiet docker || {
    error "Docker service is not active."
    exit 1
  }
  success "Docker service is running."
}

open_firewall_ports() {
  local proxy_port="$1"
  info "Configuring firewall for ports 22 and ${proxy_port}..."

  if command -v ufw >/dev/null 2>&1; then
    ufw allow 22/tcp >/dev/null 2>&1 || true
    ufw allow "${proxy_port}/tcp" >/dev/null 2>&1 || true
    success "UFW rules ensured."
  elif command -v firewall-cmd >/dev/null 2>&1; then
    firewall-cmd --permanent --add-port=22/tcp >/dev/null 2>&1 || true
    firewall-cmd --permanent --add-port="${proxy_port}/tcp" >/dev/null 2>&1 || true
    firewall-cmd --reload >/dev/null 2>&1 || true
    success "firewalld rules ensured."
  else
    warn "No ufw/firewalld found. Open ports manually if needed."
  fi
}

prompt_secret() {
  local value="${SECRET:-}"
  if [[ -z "${value}" ]]; then
    if is_tty; then
      read -r -p "Enter SECRET (32 hex chars, leave empty to auto-generate): " value
    else
      value=""
    fi
  fi

  value="${value,,}"
  if [[ -z "${value}" ]]; then
    value="$(head -c 16 /dev/urandom | xxd -ps -c 32)"
    success "Generated SECRET: ${value}"
  fi

  if [[ ! "${value}" =~ ^[0-9a-f]{32}$ ]]; then
    error "Invalid SECRET. Expected exactly 32 hex chars."
    exit 1
  fi
  printf "%s" "${value}"
}

prompt_tag() {
  local value="${TAG:-}"
  if [[ -z "${value}" ]] && is_tty; then
    read -r -p "Enter TAG from @MTProxybot (32 hex chars, optional): " value
  fi
  value="${value,,}"
  if [[ -n "${value}" && ! "${value}" =~ ^[0-9a-f]{32}$ ]]; then
    error "Invalid TAG. Expected exactly 32 hex chars or empty value."
    exit 1
  fi
  printf "%s" "${value}"
}

prompt_port() {
  local value="${CLIENT_PORT:-}"
  if [[ -z "${value}" ]]; then
    if is_tty; then
      read -r -p "Enter listening port [${DEFAULT_PORT}]: " value
    else
      value="${DEFAULT_PORT}"
    fi
  fi

  value="${value:-$DEFAULT_PORT}"
  if [[ ! "${value}" =~ ^[0-9]{1,5}$ ]] || (( value < 1 || value > 65535 )); then
    error "Invalid port: ${value}. Expected 1..65535."
    exit 1
  fi
  printf "%s" "${value}"
}

prompt_domain() {
  local value="${TLS_DOMAIN:-}"
  if [[ -z "${value}" ]]; then
    if is_tty; then
      read -r -p "Enter FakeTLS domain [${DEFAULT_TLS_DOMAIN}]: " value
    else
      value="${DEFAULT_TLS_DOMAIN}"
    fi
  fi

  value="${value:-$DEFAULT_TLS_DOMAIN}"
  value="${value,,}"
  if [[ ! "${value}" =~ ^[a-z0-9.-]+$ ]] || [[ "${value}" == .* ]] || [[ "${value}" == *..* ]]; then
    error "Invalid domain format."
    exit 1
  fi
  printf "%s" "${value}"
}

prompt_workers() {
  local value="${WORKERS:-}"
  if [[ -z "${value}" ]]; then
    if is_tty; then
      read -r -p "Enter workers count [${DEFAULT_WORKERS}]: " value
    else
      value="${DEFAULT_WORKERS}"
    fi
  fi

  value="${value:-$DEFAULT_WORKERS}"
  if [[ ! "${value}" =~ ^[0-9]+$ ]] || (( value < 1 )); then
    error "Invalid workers count. Expected integer >= 1."
    exit 1
  fi
  printf "%s" "${value}"
}

domain_to_hex() {
  local domain="$1"
  printf "%s" "${domain}" | xxd -p -c 256 | tr -d '\n'
}

get_public_ip() {
  local ip
  for endpoint in \
    "https://api.ipify.org" \
    "https://ifconfig.me/ip" \
    "https://ipv4.icanhazip.com"; do
    ip="$(curl -4 -fsSL --max-time 6 "${endpoint}" 2>/dev/null || true)"
    ip="$(printf "%s" "${ip}" | tr -d '[:space:]')"
    if [[ "${ip}" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
      printf "%s" "${ip}"
      return 0
    fi
  done
  error "Could not detect public IPv4 automatically."
  exit 1
}

remove_old_container() {
  if docker ps -a --format '{{.Names}}' | grep -Fxq "${CONTAINER_NAME}"; then
    info "Removing existing container '${CONTAINER_NAME}' to keep setup idempotent..."
    docker rm -f "${CONTAINER_NAME}" >/dev/null
    success "Old container removed."
  fi
}

run_container() {
  local secret="$1"
  local tag="$2"
  local port="$3"
  local workers="$4"

  info "Pulling official MTProxy image (${IMAGE})..."
  docker pull "${IMAGE}" >/dev/null

  local tag_env=()
  if [[ -n "${tag}" ]]; then
    tag_env=(-e "TAG=${tag}")
  fi

  info "Starting MTProxy container..."
  docker run -d \
    --name "${CONTAINER_NAME}" \
    --restart always \
    -p "${port}:443" \
    -e "SECRET=${secret}" \
    -e "WORKERS=${workers}" \
    "${tag_env[@]}" \
    "${IMAGE}" >/dev/null

  success "Container started."
}

print_result() {
  local ip="$1"
  local port="$2"
  local ee_secret="$3"

  local tg_link="tg://proxy?server=${ip}&port=${port}&secret=${ee_secret}"

  printf "\n"
  success "MTProxy is ready (Docker + FakeTLS)."
  printf "\n"
  printf "Server IP     : %s\n" "${ip}"
  printf "Port          : %s\n" "${port}"
  printf "Container     : %s\n" "${CONTAINER_NAME}"
  printf "Docker Status : %s\n" "$(systemctl is-active docker 2>/dev/null || echo unknown)"
  printf "\n"
  printf "Connection link:\n%s\n\n" "${tg_link}"

  if command -v qrencode >/dev/null 2>&1; then
    printf "QR code:\n"
    qrencode -t ANSIUTF8 "${tg_link}" || true
    printf "\n"
  else
    warn "Install qrencode to print QR: apt-get install -y qrencode"
  fi

  printf "Useful commands:\n"
  printf "  bash status.sh\n"
  printf "  sudo bash uninstall.sh\n\n"
}

main() {
  require_root
  detect_os
  install_docker

  local secret tag port tls_domain domain_hex ee_secret public_ip workers

  secret="$(prompt_secret)"
  tag="$(prompt_tag)"
  port="$(prompt_port)"
  tls_domain="$(prompt_domain)"
  workers="$(prompt_workers)"

  open_firewall_ports "${port}"
  remove_old_container
  run_container "${secret}" "${tag}" "${port}" "${workers}"

  domain_hex="$(domain_to_hex "${tls_domain}")"
  ee_secret="ee${secret}${domain_hex}"
  public_ip="$(get_public_ip)"

  print_result "${public_ip}" "${port}" "${ee_secret}"
}

main "$@"
