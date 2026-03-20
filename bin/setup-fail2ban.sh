#!/usr/bin/env bash
# setup-fail2ban.sh — Install and configure fail2ban with systemd backend
# Idempotent: safe to run multiple times.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

info()  { echo "  [INFO]  $*"; }
ok()    { echo "  [ OK ]  $*"; }

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    echo "ERROR: Run this script with sudo or as root." >&2
    exit 1
  fi
}

require_root

echo ""
echo "============================================"
echo "  setup-fail2ban.sh — SSH protection"
echo "============================================"
echo ""

# ── Install fail2ban ──────────────────────────────────────────────────────────
if ! command -v fail2ban-client &>/dev/null; then
  info "Installing fail2ban..."
  apt-get install -y -qq fail2ban
  ok "fail2ban installed."
else
  ok "fail2ban already installed."
fi

# ── Write a local jail configuration ─────────────────────────────────────────
# Use /etc/fail2ban/jail.d/ so we don't overwrite the default jail.conf
JAIL_LOCAL="/etc/fail2ban/jail.d/99-homelab.conf"

if [[ ! -f "${JAIL_LOCAL}" ]]; then
  info "Writing jail configuration to ${JAIL_LOCAL}..."
  cat > "${JAIL_LOCAL}" <<'EOF'
[DEFAULT]
# Use systemd backend (Ubuntu 24.04 uses journald)
backend = systemd

# Ban for 10 minutes after 5 failures within 10 minutes
bantime  = 10m
findtime = 10m
maxretry = 5

# Notify on bans (optional — set destemail/sendername if you want emails)
# destemail = you@example.com
# action = %(action_mwl)s

[sshd]
enabled  = true
port     = ssh
filter   = sshd
backend  = systemd
maxretry = 5
bantime  = 10m
EOF
  ok "Jail configuration written."
else
  ok "Jail configuration already present at ${JAIL_LOCAL}."
fi

# ── Ensure fail2ban service is enabled and running ────────────────────────────
info "Enabling and starting fail2ban..."
systemctl enable fail2ban
systemctl restart fail2ban
ok "fail2ban is running."

# ── Show status ───────────────────────────────────────────────────────────────
sleep 2
fail2ban-client status sshd 2>/dev/null || true

echo ""
echo "✓ fail2ban setup complete."
echo ""
echo "  Useful commands:"
echo "    sudo fail2ban-client status sshd   # show banned IPs"
echo "    sudo fail2ban-client unban <ip>    # manually unban an IP"
echo "    sudo journalctl -u fail2ban -f     # follow logs"
echo ""
echo "  NEXT STEPS:"
echo "    Edit duckdns/.env then:"
echo "    sudo bash ${REPO_ROOT}/bin/setup-duckdns.sh"
echo ""
