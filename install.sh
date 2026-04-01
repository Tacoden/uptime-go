#!/usr/bin/env bash
set -euo pipefail

APP_NAME="uptime-go"
APP_DIR="/opt/${APP_NAME}"
BIN_PATH="${APP_DIR}/${APP_NAME}"
CONFIG_PATH="${APP_DIR}/config.json"
SERVICE_NAME="${APP_NAME}.service"
SERVICE_PATH="/etc/systemd/system/${SERVICE_NAME}"
REPO="${GITHUB_REPOSITORY:-Tacoden/uptime-go}"
RELEASE_TAG="unknown"
RELEASE_EXTRACT_DIR=""

CAP_ENABLED=false
FALLBACK_ROOT=false

current_user="${SUDO_USER:-${USER:-root}}"

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

detect_repo() {
  if [[ -n "${REPO}" ]]; then
    return 0
  fi

  if command -v git >/dev/null 2>&1; then
    local origin
    origin="$(git config --get remote.origin.url 2>/dev/null || true)"
    if [[ "${origin}" =~ github.com[:/]([^/]+)/([^/.]+)(\.git)?$ ]]; then
      REPO="${BASH_REMATCH[1]}/${BASH_REMATCH[2]}"
      return 0
    fi
  fi

  read -r -p "Enter GitHub repo (owner/repo): " REPO
  if [[ ! "${REPO}" =~ ^[^/]+/[^/]+$ ]]; then
    echo "Invalid repo format. Expected owner/repo."
    exit 1
  fi
}

detect_platform() {
  local os arch
  os="$(uname -s | tr '[:upper:]' '[:lower:]')"
  arch="$(uname -m)"

  case "${os}" in
    linux)
      ;;
    *)
      echo "Unsupported OS: ${os}. This installer currently supports Linux only."
      exit 1
      ;;
  esac

  case "${arch}" in
    x86_64|amd64)
      arch="amd64"
      ;;
    aarch64|arm64)
      arch="arm64"
      ;;
    armv7l)
      arch="armv7"
      ;;
    *)
      echo "Unsupported architecture: ${arch}"
      exit 1
      ;;
  esac

  echo "${os}" "${arch}"
}

find_release_asset_url() {
  local repo="$1"
  local os="$2"
  local arch="$3"
  local api_url json urls

  api_url="https://api.github.com/repos/${repo}/releases/latest"
  json="$(curl -fsSL "${api_url}")"

  RELEASE_TAG="$(printf '%s' "${json}" | tr '\n' ' ' | sed -nE 's/.*"tag_name"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p')"
  if [[ -z "${RELEASE_TAG}" ]]; then
    RELEASE_TAG="unknown"
  fi

  urls="$(printf '%s' "${json}" | tr '\n' ' ' | grep -Eo '"browser_download_url"[[:space:]]*:[[:space:]]*"[^"]+"' | sed -E 's/^"browser_download_url"[[:space:]]*:[[:space:]]*"(.*)"$/\1/')"

  if [[ -z "${urls}" ]]; then
    echo ""
    return 0
  fi

  printf '%s\n' "${urls}" | grep -Ei "${os}.*(${arch}|x86_64|aarch64).*\.(tar\.gz|tgz|zip)$|${APP_NAME}$" | head -n 1
}

install_release_binary() {
  local asset_url="$1"
  local tmp_dir asset_file extract_dir found_bin

  tmp_dir="$(mktemp -d)"
  extract_dir="${tmp_dir}/extract"
  RELEASE_EXTRACT_DIR="${extract_dir}"
  mkdir -p "${extract_dir}"
  trap 'rm -rf "${tmp_dir}"' EXIT

  asset_file="${tmp_dir}/asset"
  echo "Downloading latest release asset: ${asset_url}"
  curl -fL "${asset_url}" -o "${asset_file}"

  if [[ "${asset_url}" == *.tar.gz || "${asset_url}" == *.tgz ]]; then
    tar -xzf "${asset_file}" -C "${extract_dir}"
  elif [[ "${asset_url}" == *.zip ]]; then
    require_cmd unzip
    unzip -q "${asset_file}" -d "${extract_dir}"
  else
    cp "${asset_file}" "${extract_dir}/${APP_NAME}"
  fi

  found_bin="$(find "${extract_dir}" -type f -name "${APP_NAME}" | head -n 1)"
  if [[ -z "${found_bin}" ]]; then
    echo "Downloaded asset did not contain ${APP_NAME}."
    exit 1
  fi

  echo "Installing application files into ${APP_DIR}..."
  sudo mkdir -p "${APP_DIR}"
  sudo install -m 755 "${found_bin}" "${BIN_PATH}"
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

require_cmd curl
require_cmd tar

detect_repo
read -r target_os target_arch < <(detect_platform)

asset_url="$(find_release_asset_url "${REPO}" "${target_os}" "${target_arch}")"
if [[ -z "${asset_url}" ]]; then
  echo "Could not find a matching release asset for ${target_os}/${target_arch} in ${REPO}."
  echo "Set GITHUB_REPOSITORY=owner/repo if auto-detection picked the wrong repo."
  exit 1
fi

print_banner
echo "Version: ${RELEASE_TAG}"
echo

echo "Using GitHub repository: ${REPO}"
install_release_binary "${asset_url}"

if [[ -f "${CONFIG_PATH}" ]]; then
  echo "Config already exists at ${CONFIG_PATH}; keeping existing file."
elif [[ -f "config.json" ]]; then
  sudo install -m 644 "config.json" "${CONFIG_PATH}"
  echo "Created config at ${CONFIG_PATH} from local config.json."
elif [[ -n "${RELEASE_EXTRACT_DIR}" ]]; then
  release_config="$(find "${RELEASE_EXTRACT_DIR}" -type f -name "config.json" | head -n 1 || true)"
  if [[ -n "${release_config}" ]]; then
    sudo install -m 644 "${release_config}" "${CONFIG_PATH}"
    echo "Created config at ${CONFIG_PATH} from release asset."
  else
    echo "No config.json found locally or in release asset."
    echo "Create ${CONFIG_PATH} manually before first run."
  fi
else
  echo "No config.json source found."
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
