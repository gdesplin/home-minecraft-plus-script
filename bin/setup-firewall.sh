#!/usr/bin/env bash
# setup-firewall.sh — Configure UFW for Minecraft + Kamal host
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
echo "  setup-firewall.sh — UFW configuration"
echo "============================================"
echo ""

# ── Install UFW if missing ────────────────────────────────────────────────────
if ! command -v ufw &>/dev/null; then
  info "Installing UFW..."
  apt-get install -y -qq ufw
fi

# ── Reset to a known state (keeps existing rules, just re-applies) ────────────
# We use ufw status to check current rules instead of resetting, to stay idempotent.

# ── Set default policies ──────────────────────────────────────────────────────
info "Setting default policies: deny incoming, allow outgoing..."
ufw default deny incoming  --force 2>/dev/null || true
ufw default allow outgoing --force 2>/dev/null || true

# ── Allow SSH (broad — restrict to LAN after testing: see README) ─────────────
info "Allowing SSH (port 22/tcp)..."
ufw allow 22/tcp comment 'SSH'
ok "SSH allowed."

# ── Minecraft Java Edition ────────────────────────────────────────────────────
info "Allowing Minecraft (port 25565/tcp)..."
ufw allow 25565/tcp comment 'Minecraft Java'
ok "Minecraft port allowed."

# ── Minecraft Bedrock Edition (Geyser) ───────────────────────────────────────
info "Allowing Minecraft Bedrock Edition via Geyser (port 19132/udp)..."
ufw allow 19132/udp comment 'Minecraft Bedrock (Geyser)'
ok "Minecraft Bedrock port allowed."

# ── HTTP/HTTPS for Kamal/Traefik ──────────────────────────────────────────────
info "Allowing HTTP (80/tcp) and HTTPS (443/tcp) for Kamal/Traefik..."
ufw allow 80/tcp  comment 'HTTP (Kamal/Traefik)'
ufw allow 443/tcp comment 'HTTPS (Kamal/Traefik)'
ok "HTTP/HTTPS allowed."

# ── Docker daemon socket is local only (no rule needed) ──────────────────────
# RCON (25575) is intentionally NOT opened externally; bind to 127.0.0.1 in compose.

# ── Enable UFW ────────────────────────────────────────────────────────────────
info "Enabling UFW..."
ufw --force enable
ok "UFW enabled."

echo ""
ufw status verbose
echo ""
echo "✓ Firewall setup complete."
echo ""
echo "  IMPORTANT: To restrict SSH to LAN only (recommended), run:"
echo ""
echo "    sudo ufw delete allow 22/tcp"
echo "    sudo ufw allow from 192.168.1.0/24 to any port 22 proto tcp comment 'SSH LAN only'"
echo "    sudo ufw reload"
echo ""
echo "  Adjust the subnet (192.168.1.0/24) to match your network."
echo ""
echo "  NEXT STEPS:"
echo "    sudo bash ${REPO_ROOT}/bin/setup-fail2ban.sh"
echo ""
