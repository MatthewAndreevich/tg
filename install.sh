#!/usr/bin/env bash
set -Eeuo pipefail

REPO_URL="https://github.com/TelegramMessenger/MTProxy"
INSTALL_DIR="/opt/MTProxy"
SERVICE_NAME="MTProxy.service"
SERVICE_PATH="/etc/systemd/system/${SERVICE_NAME}"
CONFIG_UPDATE_SERVICE_NAME="MTProxyConfigUpdate.service"
CONFIG_UPDATE_TIMER_NAME="MTProxyConfigUpdate.timer"
CONFIG_UPDATE_SERVICE_PATH="/etc/systemd/system/${CONFIG_UPDATE_SERVICE_NAME}"
CONFIG_UPDATE_TIMER_PATH="/etc/systemd/system/${CONFIG_UPDATE_TIMER_NAME}"
CONFIG_UPDATE_SCRIPT_PATH="/usr/local/bin/mtproxy-refresh-config.sh"
DEFAULT_CLIENT_PORT="443"
DEFAULT_STATS_PORT="8888"
DEFAULT_WORKERS="1"
RUN_USER="nobody"

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

install_dependencies() {
  info "Installing build dependencies from official guide..."
  apt-get update -y
  apt-get install -y git curl build-essential libssl-dev zlib1g-dev ca-certificates xxd
  success "Dependencies installed."
}

clone_or_update_repo() {
  if [[ -d "${INSTALL_DIR}/.git" ]]; then
    info "Updating existing MTProxy source in ${INSTALL_DIR}..."
    git -C "${INSTALL_DIR}" fetch --all --tags --prune
    git -C "${INSTALL_DIR}" checkout master
    git -C "${INSTALL_DIR}" pull --ff-only origin master
  else
    info "Cloning official MTProxy repository into ${INSTALL_DIR}..."
    rm -rf "${INSTALL_DIR}"
    git clone "${REPO_URL}" "${INSTALL_DIR}"
  fi
  success "Source code is ready."
}

build_mtproxy() {
  info "Building MTProxy..."
  make -C "${INSTALL_DIR}"
  if [[ ! -x "${INSTALL_DIR}/objs/bin/mtproto-proxy" ]]; then
    error "Build finished but binary not found: ${INSTALL_DIR}/objs/bin/mtproto-proxy"
    exit 1
  fi
  success "MTProxy compiled successfully."
}

fetch_runtime_files() {
  info "Downloading current proxy-secret and proxy-multi.conf..."
  curl -fsSL "https://core.telegram.org/getProxySecret" -o "${INSTALL_DIR}/objs/bin/proxy-secret"
  curl -fsSL "https://core.telegram.org/getProxyConfig" -o "${INSTALL_DIR}/objs/bin/proxy-multi.conf"
  success "Runtime files updated."
}

write_config_update_script() {
  cat > "${CONFIG_UPDATE_SCRIPT_PATH}" <<SCRIPT
#!/usr/bin/env bash
set -Eeuo pipefail

TARGET_DIR="${INSTALL_DIR}/objs/bin"
TMP_FILE="\$(mktemp)"
trap 'rm -f "\${TMP_FILE}"' EXIT

curl -fsSL "https://core.telegram.org/getProxyConfig" -o "\${TMP_FILE}"
install -m 0644 "\${TMP_FILE}" "\${TARGET_DIR}/proxy-multi.conf"
SCRIPT
  chmod +x "${CONFIG_UPDATE_SCRIPT_PATH}"
  success "Config refresh script installed to ${CONFIG_UPDATE_SCRIPT_PATH}."
}

write_config_update_units() {
  cat > "${CONFIG_UPDATE_SERVICE_PATH}" <<SERVICE
[Unit]
Description=Refresh MTProxy proxy-multi.conf from Telegram
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=${CONFIG_UPDATE_SCRIPT_PATH}
SERVICE

  cat > "${CONFIG_UPDATE_TIMER_PATH}" <<TIMER
[Unit]
Description=Run MTProxy config refresh daily

[Timer]
OnCalendar=daily
Persistent=true
RandomizedDelaySec=15m
Unit=${CONFIG_UPDATE_SERVICE_NAME}

[Install]
WantedBy=timers.target
TIMER

  success "Config update systemd units written."
}

open_firewall_ports() {
  local client_port="$1"
  info "Configuring firewall for ports 22 and ${client_port}..."

  if command -v ufw >/dev/null 2>&1; then
    ufw allow 22/tcp >/dev/null 2>&1 || true
    ufw allow "${client_port}/tcp" >/dev/null 2>&1 || true
    success "UFW rules ensured."
  elif command -v firewall-cmd >/dev/null 2>&1; then
    firewall-cmd --permanent --add-port=22/tcp >/dev/null 2>&1 || true
    firewall-cmd --permanent --add-port="${client_port}/tcp" >/dev/null 2>&1 || true
    firewall-cmd --reload >/dev/null 2>&1 || true
    success "firewalld rules ensured."
  else
    warn "No ufw/firewalld found. Open ports manually if needed."
  fi
}

prompt_secret() {
  local value
  read -r -p "Enter user SECRET (32 hex chars, leave empty to auto-generate): " value
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
  local value
  read -r -p "Enter TAG from @MTProxybot (32 hex chars, optional): " value
  value="${value,,}"
  if [[ -n "${value}" && ! "${value}" =~ ^[0-9a-f]{32}$ ]]; then
    error "Invalid TAG. Expected exactly 32 hex chars or empty value."
    exit 1
  fi
  printf "%s" "${value}"
}

prompt_port() {
  local label="$1"
  local default_value="$2"
  local value
  read -r -p "${label} [${default_value}]: " value
  value="${value:-$default_value}"
  if [[ ! "${value}" =~ ^[0-9]{1,5}$ ]] || (( value < 1 || value > 65535 )); then
    error "Invalid port: ${value}. Expected 1..65535."
    exit 1
  fi
  printf "%s" "${value}"
}

prompt_workers() {
  local value
  read -r -p "Enter workers count [${DEFAULT_WORKERS}]: " value
  value="${value:-$DEFAULT_WORKERS}"
  if [[ ! "${value}" =~ ^[0-9]+$ ]] || (( value < 1 )); then
    error "Invalid workers count. Expected integer >= 1."
    exit 1
  fi
  printf "%s" "${value}"
}

write_service() {
  local secret="$1"
  local tag="$2"
  local client_port="$3"
  local stats_port="$4"
  local workers="$5"

  local tag_arg=""
  if [[ -n "${tag}" ]]; then
    tag_arg="-P ${tag}"
  fi

  cat > "${SERVICE_PATH}" <<SERVICE
[Unit]
Description=MTProxy
After=network.target

[Service]
Type=simple
WorkingDirectory=${INSTALL_DIR}/objs/bin
ExecStart=${INSTALL_DIR}/objs/bin/mtproto-proxy -u ${RUN_USER} -p ${stats_port} -H ${client_port} -S ${secret} ${tag_arg} --aes-pwd ${INSTALL_DIR}/objs/bin/proxy-secret ${INSTALL_DIR}/objs/bin/proxy-multi.conf -M ${workers}
Restart=on-failure
RestartSec=5s
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
SERVICE

  success "Systemd service written to ${SERVICE_PATH}."
}

start_service() {
  info "Reloading systemd and starting ${SERVICE_NAME}..."
  systemctl daemon-reload
  systemctl enable "${SERVICE_NAME}" >/dev/null
  systemctl restart "${SERVICE_NAME}"

  if ! systemctl is-active --quiet "${SERVICE_NAME}"; then
    error "Service is not active. Check: journalctl -u ${SERVICE_NAME} -n 100 --no-pager"
    exit 1
  fi
  success "Service is active and enabled."
}

enable_config_update_timer() {
  info "Enabling daily config refresh timer..."
  systemctl daemon-reload
  systemctl enable "${CONFIG_UPDATE_TIMER_NAME}" >/dev/null
  systemctl restart "${CONFIG_UPDATE_TIMER_NAME}"
  systemctl start "${CONFIG_UPDATE_SERVICE_NAME}" || true
  success "Timer enabled: ${CONFIG_UPDATE_TIMER_NAME}"
}

get_public_ip() {
  local ip
  for endpoint in "https://api.ipify.org" "https://ifconfig.me/ip" "https://ipv4.icanhazip.com"; do
    ip="$(curl -4 -fsSL --max-time 6 "${endpoint}" 2>/dev/null || true)"
    ip="$(printf "%s" "${ip}" | tr -d '[:space:]')"
    if [[ "${ip}" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
      printf "%s" "${ip}"
      return 0
    fi
  done
  error "Could not auto-detect public IPv4."
  exit 1
}

print_result() {
  local ip="$1"
  local client_port="$2"
  local stats_port="$3"
  local secret="$4"

  local plain_link="tg://proxy?server=${ip}&port=${client_port}&secret=${secret}"
  local dd_link="tg://proxy?server=${ip}&port=${client_port}&secret=dd${secret}"

  printf "\n"
  success "MTProxy is ready (official source build)."
  printf "\n"
  printf "Public IP         : %s\n" "${ip}"
  printf "Client port (-H)  : %s\n" "${client_port}"
  printf "Stats port (-p)   : %s (local)\n" "${stats_port}"
  printf "Service           : %s\n" "${SERVICE_NAME}"
  printf "\n"
  printf "Proxy link:\n%s\n\n" "${plain_link}"
  printf "Proxy link (dd padding):\n%s\n\n" "${dd_link}"
  printf "Stats endpoint (local):\n"
  printf "curl -s http://127.0.0.1:%s/stats\n\n" "${stats_port}"

  if command -v qrencode >/dev/null 2>&1; then
    printf "QR code:\n"
    qrencode -t ANSIUTF8 "${plain_link}" || true
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
  install_dependencies
  clone_or_update_repo
  build_mtproxy
  fetch_runtime_files
  write_config_update_script
  write_config_update_units

  local secret tag client_port stats_port workers public_ip
  secret="$(prompt_secret)"
  tag="$(prompt_tag)"
  client_port="$(prompt_port "Enter client listening port (-H)" "${DEFAULT_CLIENT_PORT}")"
  stats_port="$(prompt_port "Enter local stats port (-p)" "${DEFAULT_STATS_PORT}")"
  workers="$(prompt_workers)"

  open_firewall_ports "${client_port}"
  write_service "${secret}" "${tag}" "${client_port}" "${stats_port}" "${workers}"
  start_service
  enable_config_update_timer

  public_ip="$(get_public_ip)"
  print_result "${public_ip}" "${client_port}" "${stats_port}" "${secret}"
}

main "$@"
