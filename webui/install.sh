#!/bin/bash
# SolStream — one-command bootstrap installer.
#
# Usage (as root, on a fresh Ubuntu 24.04 host):
#   curl -fsSL https://raw.githubusercontent.com/mxmjxn/SolStream/main/webui/install.sh | sudo bash
#
# What this does:
#   1. Installs python3-venv + ansible-core via apt
#   2. Clones / updates the SolStream repo to /opt/solstream
#   3. Creates a Python venv at /opt/solstream/.venv
#   4. Installs the webui package into the venv
#   5. Launches `solstream-webui` on port 8080
#
# After that, you open http://<this-host-ip>:8080 from any device on your
# LAN and walk through the wizard.

set -euo pipefail

REPO_URL="${SOLSTREAM_REPO_URL:-https://github.com/mxmjxn/SolStream.git}"
INSTALL_DIR="${SOLSTREAM_INSTALL_DIR:-/opt/solstream}"
PORT="${SOLSTREAM_PORT:-8080}"

log() { echo -e "\033[1;33m[solstream]\033[0m $*"; }
die() { echo -e "\033[1;31m[solstream] ERROR:\033[0m $*" >&2; exit 1; }

if [[ "${EUID}" -ne 0 ]]; then
  die "Must be run as root. Try: curl -fsSL <url> | sudo bash"
fi

. /etc/os-release
case "${ID:-}" in
  ubuntu) [[ "${VERSION_ID:-}" == "24.04" ]] || die "Need Ubuntu 24.04 (got ${VERSION_ID})." ;;
  *) die "Need Ubuntu 24.04 (got ${ID:-unknown})." ;;
esac

log "Installing base dependencies (apt)…"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq python3-venv git ansible-core mokutil >/dev/null

log "Cloning SolStream to ${INSTALL_DIR}…"
if [[ -d "${INSTALL_DIR}/.git" ]]; then
  git -C "${INSTALL_DIR}" fetch --quiet --depth 1 origin main
  git -C "${INSTALL_DIR}" reset --quiet --hard origin/main
else
  git clone --quiet --depth 1 "${REPO_URL}" "${INSTALL_DIR}"
fi

log "Setting up Python virtualenv…"
python3 -m venv "${INSTALL_DIR}/.venv"
"${INSTALL_DIR}/.venv/bin/pip" install --quiet --upgrade pip wheel
"${INSTALL_DIR}/.venv/bin/pip" install --quiet "${INSTALL_DIR}/cli"
"${INSTALL_DIR}/.venv/bin/pip" install --quiet "${INSTALL_DIR}/webui"

# Make the CLI globally available
ln -sf "${INSTALL_DIR}/.venv/bin/solstream" /usr/local/bin/solstream
ln -sf "${INSTALL_DIR}/.venv/bin/solstream-webui" /usr/local/bin/solstream-webui

LAN_IP="$(ip -4 -o addr show scope global | head -1 | awk '{print $4}' | cut -d/ -f1)"

cat <<EOF

  ╔══════════════════════════════════════════════════════════╗
  ║                                                          ║
  ║   SolStream web installer is ready to launch.           ║
  ║                                                          ║
  ║   It will listen on:                                     ║
  ║                                                          ║
  ║     http://${LAN_IP}:${PORT}
  ║                                                          ║
  ║   Open that URL from any browser on your LAN to start.  ║
  ║                                                          ║
  ╚══════════════════════════════════════════════════════════╝

EOF

log "Launching solstream-webui (Ctrl+C to abort)…"
exec /usr/local/bin/solstream-webui --port "${PORT}"
