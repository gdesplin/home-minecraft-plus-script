#!/usr/bin/env bash
# setup-playit.sh — Install and configure Playit.gg tunnel for CGNAT scenarios
# Idempotent: safe to run multiple times.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

info()  { echo "  [INFO]  $*"; }
ok()    { echo "  [ OK ]  $*"; }
warn()  { echo "  [WARN]  $*"; }

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    echo "ERROR: Run this script with sudo or as root." >&2
    exit 1
  fi
}

require_root

echo ""
echo "============================================"
echo "  setup-playit.sh — Playit.gg Tunnel"
echo "============================================"
echo ""

# ── Install curl / gpg if missing ────────────────────────────────────────────
for pkg in curl gpg; do
  if ! command -v "${pkg}" &>/dev/null; then
    info "Installing ${pkg}..."
    apt-get install -y -qq "${pkg}"
  fi
done

# ── Add Playit.gg APT repository ─────────────────────────────────────────────
KEYRING="/usr/share/keyrings/playit.gpg"
SOURCES_FILE="/etc/apt/sources.list.d/playit-cloud.list"

if [[ ! -f "${KEYRING}" ]]; then
  info "Adding Playit.gg GPG key..."
  curl -SsL https://playit-cloud.github.io/ppa/key.gpg \
    | gpg --dearmor -o "${KEYRING}"
  ok "GPG key installed."
else
  ok "Playit.gg GPG key already present."
fi

if [[ ! -f "${SOURCES_FILE}" ]]; then
  info "Adding Playit.gg APT repository..."
  echo "deb [signed-by=${KEYRING}] https://playit-cloud.github.io/ppa/repo stable main" \
    > "${SOURCES_FILE}"
  ok "APT repository added."
else
  ok "Playit.gg APT repository already present."
fi

# ── Install playit ────────────────────────────────────────────────────────────
info "Updating package lists and installing playit..."
apt-get update -qq
apt-get install -y -qq playit
ok "playit installed: $(playit --version 2>/dev/null || echo '(version unknown)')"

# ── Create dedicated playit system user ──────────────────────────────────────
if ! id -u playit &>/dev/null; then
  info "Creating 'playit' system user..."
  useradd -r -s /bin/false -d /opt/playit playit
  ok "User 'playit' created."
else
  ok "User 'playit' already exists."
fi

# ── Create config / data directory ───────────────────────────────────────────
if [[ ! -d /opt/playit ]]; then
  info "Creating /opt/playit directory..."
  mkdir -p /opt/playit
  ok "Directory created."
else
  ok "/opt/playit already exists."
fi

chown playit:playit /opt/playit
chmod 750 /opt/playit

# ── Install systemd service ───────────────────────────────────────────────────
SERVICE_SRC="${REPO_ROOT}/config/playit.service"
SERVICE_DEST="/etc/systemd/system/playit.service"

if [[ ! -f "${SERVICE_SRC}" ]]; then
  warn "Service file not found at ${SERVICE_SRC}. Skipping systemd setup."
else
  info "Installing systemd service..."
  cp "${SERVICE_SRC}" "${SERVICE_DEST}"
  systemctl daemon-reload
  ok "Systemd service installed."
fi

echo ""
echo "✓ Playit.gg installation complete."
echo ""
echo "  ┌─ NEXT STEPS ──────────────────────────────────────────────────────────┐"
echo "  │                                                                       │"
echo "  │  1. Run the initial claim wizard (one-time setup):                    │"
echo "  │       sudo -u playit playit                                           │"
echo "  │                                                                       │"
echo "  │  2. Open the printed URL in a browser and log in to playit.gg.        │"
echo "  │                                                                       │"
echo "  │  3. Add tunnels on the playit.gg dashboard:                           │"
echo "  │       • TCP  25565  →  Minecraft Java Edition                         │"
echo "  │       • UDP  19132  →  Minecraft Bedrock / Geyser (optional)          │"
echo "  │                                                                       │"
echo "  │  4. Exit the wizard (Ctrl+C), then enable the service:                │"
echo "  │       sudo systemctl enable --now playit                              │"
echo "  │                                                                       │"
echo "  │  5. Share your tunnel address with players:                           │"
echo "  │       yourname.joinplayit.gg                                          │"
echo "  │                                                                       │"
echo "  └───────────────────────────────────────────────────────────────────────┘"
echo ""
echo "  Useful commands:"
echo "    sudo systemctl status playit"
echo "    sudo journalctl -u playit -f"
echo ""
echo "  See the README for full Playit.gg documentation."
echo ""
