#!/usr/bin/env bash
# setup-playit.sh — Install and configure Playit.gg tunnel for CGNAT scenarios
# Idempotent: safe to run multiple times.
#
# NOTE: The official Playit APT package (tested with v0.17.1) installs the
# binary at /opt/playit/playit — it does NOT place it on $PATH.
# 'which playit' will return nothing even after a successful install.
# All manual commands (claim, debug) must use /opt/playit/playit explicitly.
#
# This script:
#   - Installs playit via the official APT repository
#   - Uses the vendor-provided systemd unit (no overwrite of /usr/lib/systemd/system/playit.service)
#   - Places a drop-in override at /etc/systemd/system/playit.service.d/override.conf
#   - Creates /etc/playit/ as the canonical config/secret directory
set -euo pipefail

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
ok "playit installed: $(/opt/playit/playit --version 2>/dev/null || echo '(version unknown)')"

# ── Create dedicated playit system user ──────────────────────────────────────
if ! id -u playit &>/dev/null; then
  info "Creating 'playit' system user..."
  useradd -r -s /bin/false -d /opt/playit playit
  ok "User 'playit' created."
else
  ok "User 'playit' already exists."
fi

# ── Create config / data directory ───────────────────────────────────────────
# The APT package installs its binary into /opt/playit/ (/opt/playit/playit).
# We set ownership so the service user can write state/secrets there.
if [[ ! -d /opt/playit ]]; then
  info "Creating /opt/playit directory..."
  mkdir -p /opt/playit
  ok "Directory created."
else
  ok "/opt/playit already exists."
fi

chown playit:playit /opt/playit
chmod 750 /opt/playit

# ── Create canonical config directory ────────────────────────────────────────
# The playit vendor systemd unit passes --secret_path /etc/playit/... so the
# agent reads/writes its secret key from /etc/playit/.  The playit user must
# have write access here so that the interactive claim step can persist the key.
if [[ ! -d /etc/playit ]]; then
  info "Creating /etc/playit config directory..."
  mkdir -p /etc/playit
  ok "Directory created."
else
  ok "/etc/playit already exists."
fi

chown root:playit /etc/playit
chmod 750 /etc/playit

# ── Create log directory ──────────────────────────────────────────────────────
# The playit binary (APT package) uses a rolling file appender that writes to
# /var/log/playit/. This directory must exist and be owned by the playit service
# user BEFORE the service starts; otherwise the binary panics with exit-code 101:
#   "initializing rolling file appender failed: InitError { ... }"
# Note: running 'sudo -u playit /opt/playit/playit' interactively works even
# without this directory because the interactive run logs elsewhere by default.
if [[ ! -d /var/log/playit ]]; then
  info "Creating /var/log/playit log directory..."
  mkdir -p /var/log/playit
  ok "Directory created."
else
  ok "/var/log/playit already exists."
fi
chown playit:playit /var/log/playit
chmod 755 /var/log/playit
ok "/var/log/playit ownership set to playit:playit."

# ── Install systemd drop-in override (do NOT overwrite vendor unit) ───────────
# The official playit APT package ships its own unit at:
#   /usr/lib/systemd/system/playit.service
# We use a drop-in override to enforce the correct user/group, working directory,
# and log directory without replacing the vendor unit.
# LogsDirectory=playit tells systemd to create/own /var/log/playit before start,
# providing a belt-and-suspenders guarantee alongside the mkdir above.
DROPIN_DIR="/etc/systemd/system/playit.service.d"
DROPIN_FILE="${DROPIN_DIR}/override.conf"

info "Installing systemd drop-in override..."
mkdir -p "${DROPIN_DIR}"
cat > "${DROPIN_FILE}" << 'EOF'
[Service]
# Run as the dedicated playit system user, not root.
User=playit
Group=playit
WorkingDirectory=/opt/playit
# Ensure /var/log/playit/ exists and is owned by the service user before start.
# This prevents the "rolling file appender failed" panic (exit-code 101) that
# occurs when the directory is absent after a fresh install or reset.
LogsDirectory=playit
EOF
ok "Drop-in override written to ${DROPIN_FILE}."

systemctl daemon-reload
ok "systemd configuration reloaded."

echo ""
echo "✓ Playit.gg installation complete."
echo ""
echo "  ┌─ NEXT STEPS ──────────────────────────────────────────────────────────┐"
echo "  │                                                                       │"
echo "  │  1. Claim the agent ONE TIME as the service user:                     │"
echo "  │       sudo -u playit /opt/playit/playit                              │"
echo "  │                                                                       │"
echo "  │     NOTE: 'which playit' will return nothing — the APT package       │"
echo "  │     (v0.17.1) installs the binary at /opt/playit/playit only.        │"
echo "  │     Always use the full path for manual commands.                     │"
echo "  │                                                                       │"
echo "  │     ⚠  IMPORTANT: do NOT run the agent as your normal login.         │"
echo "  │     Running it as your own user writes a separate secret key to       │"
echo "  │     ~/.config/playit_gg/ and creates a duplicate agent identity,      │"
echo "  │     which causes tunnels to show online but receive no traffic.       │"
echo "  │                                                                       │"
echo "  │  2. Open the printed URL in a browser and log in to playit.gg.        │"
echo "  │                                                                       │"
echo "  │  3. Add tunnels on the playit.gg dashboard:                           │"
echo "  │       • TCP  25565  →  local address: 127.0.0.1:25565                 │"
echo "  │       • UDP  19132  →  local address: 127.0.0.1:19132  (Bedrock)      │"
echo "  │                                                                       │"
echo "  │     ⚠  Use 127.0.0.1 (not the Docker container IP) so the host-side  │"
echo "  │     playit agent can reach Docker's published port.                   │"
echo "  │                                                                       │"
echo "  │  4. Exit the wizard (Ctrl+C), then enable the service:                │"
echo "  │       sudo systemctl enable --now playit                              │"
echo "  │                                                                       │"
echo "  │  5. Verify the agent is running:                                      │"
echo "  │       sudo systemctl status playit                                    │"
echo "  │       sudo journalctl -u playit -n 30                                 │"
echo "  │                                                                       │"
echo "  │  6. Share your tunnel address with players:                           │"
echo "  │       yourname.joinplayit.gg                                          │"
echo "  │                                                                       │"
echo "  └───────────────────────────────────────────────────────────────────────┘"
echo ""
echo "  Useful commands:"
echo "    sudo systemctl status playit"
echo "    sudo tail -f /var/log/playit/playit.log"
echo "    sudo journalctl -u playit -f"
echo ""
echo "  See the README for full Playit.gg documentation, including the"
echo "  'Full reset' procedure if you need to start over."
echo ""
