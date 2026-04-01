#!/usr/bin/env bash
set -euo pipefail

APP_NAME="uptime-go"
APP_DIR="/opt/${APP_NAME}"
BIN_PATH="${APP_DIR}/${APP_NAME}"
CONFIG_PATH="${APP_DIR}/config.json"
SERVICE_NAME="${APP_NAME}.service"
SERVICE_PATH="/etc/systemd/system/${SERVICE_NAME}"

CAP_ENABLED=false
FALLBACK_ROOT=false

current_user="${SUDO_USER:-${USER:-root}}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOCAL_BIN_PATH=""

print_banner() {
  cat <<'EOF'
 _   _       _   _                     
| | | |_ __ | |_(_)_ __ ___   ___     
| | | | '_ \| __| | '_ ` _ \ / _ \ 
| |_| | |_) | |_| | | | | | |  __/    
 \___/| .__/ \__|_|_| |_| |_|\___| 
      |_|                            
               ____                  
              / ___| ___             
             | |  _ / _ \          
             | |_| | (_) |          
              \____|\___/         
EOF
}

require_cmd() {
  local cmd="$1"
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "Required command not found: ${cmd}"
    exit 1
  fi
}

detect_local_binary() {
  if [[ -x "${SCRIPT_DIR}/${APP_NAME}" ]]; then
    LOCAL_BIN_PATH="${SCRIPT_DIR}/${APP_NAME}"
    return 0
  fi

  if [[ -x "${SCRIPT_DIR}/main" ]]; then
    LOCAL_BIN_PATH="${SCRIPT_DIR}/main"
    return 0
  fi

  echo "Could not find a local executable binary in ${SCRIPT_DIR}."
  echo "Expected one of: ${APP_NAME} or main"
  echo "Extract the release archive first, then run install.sh from that folder."
  exit 1
}

ask_yes_no() {
  local prompt="$1"
  local answer
  read -r -p "${prompt} [y/N]: " answer
  case "${answer}" in
    [yY]|[yY][eE][sS])
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

write_service_file() {
  local run_user="$1"

  sudo tee "${SERVICE_PATH}" >/dev/null <<EOF
[Unit]
Description=uptime-go monitoring service
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=${APP_DIR}
ExecStart=${BIN_PATH}
Restart=always
RestartSec=5
User=${run_user}

[Install]
WantedBy=multi-user.target
EOF
}

print_banner
echo

detect_local_binary
echo "Using local binary: ${LOCAL_BIN_PATH}"

echo "Installing application files into ${APP_DIR}..."
sudo mkdir -p "${APP_DIR}"
sudo install -m 755 "${LOCAL_BIN_PATH}" "${BIN_PATH}"

if [[ -f "${CONFIG_PATH}" ]]; then
  echo "Config already exists at ${CONFIG_PATH}; keeping existing file."
elif [[ -f "config.json" ]]; then
  sudo install -m 644 "config.json" "${CONFIG_PATH}"
  echo "Created config at ${CONFIG_PATH} from local config.json."
else
  echo "No local config.json found in ${SCRIPT_DIR}."
  echo "Create ${CONFIG_PATH} manually before first run."
fi

echo "Attempting to enable raw socket capability with setcap..."
if command -v setcap >/dev/null 2>&1 && command -v getcap >/dev/null 2>&1; then
  if sudo setcap cap_net_raw+ep "${BIN_PATH}"; then
    CAP_ENABLED=true
    echo "setcap successful:"
    getcap "${BIN_PATH}" || true
  else
    echo "setcap failed."
  fi
else
  echo "setcap/getcap tools are not installed (libcap utilities missing)."
fi

if [[ "${CAP_ENABLED}" != "true" ]]; then
  echo
  echo "Without CAP_NET_RAW, ping may fail for non-root runtime."
  echo "Fallback is running as root (for service or manual runs)."
  if ask_yes_no "Continue with root fallback"; then
    FALLBACK_ROOT=true
  else
    echo "Installation stopped. Install libcap tools and re-run this script."
    exit 1
  fi
fi

echo
if ask_yes_no "Set up ${SERVICE_NAME} to auto-start and run 24/7"; then
  run_user="${current_user}"
  if [[ "${FALLBACK_ROOT}" == "true" ]]; then
    run_user="root"
  fi

  echo "Creating systemd service at ${SERVICE_PATH} (User=${run_user})..."
  write_service_file "${run_user}"

  echo "Enabling and starting ${SERVICE_NAME}..."
  sudo systemctl daemon-reload
  sudo systemctl enable --now "${SERVICE_NAME}"
  sudo systemctl --no-pager --full status "${SERVICE_NAME}" | head -n 20 || true
else
  echo "Skipped service setup."
fi

echo
if [[ "${FALLBACK_ROOT}" == "true" ]]; then
  echo "Manual run (root fallback):"
  echo "  cd ${APP_DIR} && sudo ${BIN_PATH}"
else
  echo "Manual run:"
  echo "  cd ${APP_DIR} && ${BIN_PATH}"
fi

echo
echo "Next step: edit your config file and add your details:"
echo "  ${CONFIG_PATH}"
echo "Example: sudo nano ${CONFIG_PATH}"
