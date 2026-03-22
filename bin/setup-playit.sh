#!/usr/bin/env bash
# setup-playit.sh — Install the playit.gg standalone agent for CGNAT scenarios
# Idempotent: safe to run multiple times.
#
# This script installs the official playit binary from GitHub, creates a
# dedicated system user, and manages it as a systemd service (playit.service).
# The agent tunnels traffic to localhost:25565 so players can connect even
# when the host is behind CGNAT (no port-forwarding needed).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
PLAYIT_BIN="/usr/local/bin/playit"
PLAYIT_DIR="/etc/playit"
PLAYIT_SERVICE="/etc/systemd/system/playit.service"

info()  { echo "  [INFO]  $*"; }
ok()    { echo "  [ OK ]  $*"; }
warn()  { echo "  [WARN]  $*"; }
err()   { echo "  [ERR]   $*" >&2; }

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    echo "ERROR: Run this script with sudo or as root." >&2
    exit 1
  fi
}

require_root

echo ""
echo "============================================"
echo "  setup-playit.sh — Playit.gg Agent"
echo "  (standalone binary, systemd managed)"
echo "============================================"
echo ""

# ── 1. Detect architecture ────────────────────────────────────────────────────
ARCH=$(uname -m)
case "${ARCH}" in
  x86_64)  PLAYIT_ARCH="amd64" ;;
  aarch64) PLAYIT_ARCH="arm64" ;;
  *)
    err "Unsupported architecture: ${ARCH}. Only x86_64 and aarch64 are supported."
    exit 1
    ;;
esac
info "Detected architecture: ${ARCH} → playit-linux-${PLAYIT_ARCH}"

# ── 2. Download playit binary ─────────────────────────────────────────────────
PLAYIT_URL="https://github.com/playit-cloud/playit-agent/releases/latest/download/playit-linux-${PLAYIT_ARCH}"
info "Downloading playit binary from GitHub..."
curl -fsSL -o "${PLAYIT_BIN}" "${PLAYIT_URL}"
chmod +x "${PLAYIT_BIN}"
ok "playit binary installed at ${PLAYIT_BIN}."

# ── 3. Create playit system user ──────────────────────────────────────────────
if ! id playit &>/dev/null; then
  info "Creating 'playit' system user..."
  useradd -r -s /usr/sbin/nologin playit
  ok "User 'playit' created."
else
  ok "User 'playit' already exists."
fi

# ── 4. Create /etc/playit directory ──────────────────────────────────────────
info "Creating ${PLAYIT_DIR}..."
mkdir -p "${PLAYIT_DIR}"
chown playit:playit "${PLAYIT_DIR}"
ok "${PLAYIT_DIR} ready."

# ── 5. Write systemd unit ─────────────────────────────────────────────────────
info "Writing ${PLAYIT_SERVICE}..."
cat > "${PLAYIT_SERVICE}" <<'EOF'
[Unit]
Description=Playit.gg Tunnel Agent
After=network-online.target minecraft.service
Wants=network-online.target

[Service]
User=playit
Group=playit
WorkingDirectory=/etc/playit
ExecStart=/usr/local/bin/playit
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal
SyslogIdentifier=playit

[Install]
WantedBy=multi-user.target
EOF
ok "playit.service written."

# ── 6. Enable and start the service ──────────────────────────────────────────
info "Reloading systemd and enabling playit.service..."
systemctl daemon-reload
systemctl enable playit.service
info "Starting playit.service..."
systemctl start playit.service
ok "playit.service enabled and started."

# ── 7. Show initial logs (claim URL) ─────────────────────────────────────────
echo ""
info "Waiting 3 seconds for the agent to start..."
sleep 3
echo ""
echo "  ── Recent playit logs ──────────────────────────────────────────────────"
journalctl -u playit -n 30 --no-pager || true
echo "  ────────────────────────────────────────────────────────────────────────"
echo ""

echo "✓ Playit.gg agent installed."
echo ""
echo "  ┌─ NEXT STEPS ──────────────────────────────────────────────────────────┐"
echo "  │                                                                       │"
echo "  │  1. Look for a claim URL in the log output above:                    │"
echo "  │       https://playit.gg/claim/xxxxx                                  │"
echo "  │     Or follow live logs:                                              │"
echo "  │       journalctl -u playit -f                                         │"
echo "  │                                                                       │"
echo "  │  2. Open the URL in a browser and log in to playit.gg.               │"
echo "  │     Claim the agent — this links it to your account.                 │"
echo "  │                                                                       │"
echo "  │  3. On the playit.gg dashboard the agent auto-creates a TCP tunnel   │"
echo "  │     for port 25565 (localhost:25565 → internet).                     │"
echo "  │                                                                       │"
echo "  │  4. Share your tunnel address with players:                          │"
echo "  │       yourname.joinplayit.gg                                         │"
echo "  │     (The exact address is shown on the playit.gg dashboard.)         │"
echo "  │                                                                       │"
echo "  └───────────────────────────────────────────────────────────────────────┘"
echo ""
