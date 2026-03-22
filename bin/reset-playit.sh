#!/usr/bin/env bash
# reset-playit.sh — Hard-reset all Playit.gg state for a clean reinstall
#
# USE THIS WHEN:
#   • The tunnel shows online on the dashboard but external connections never
#     arrive at the Minecraft server (no log lines in the playit agent).
#   • status=101 on 'systemctl status playit' after changing configs.
#   • You accidentally ran /opt/playit/playit as your normal login instead of
#     the 'playit' service user, creating a duplicate agent identity.
#   • Any other situation where you need a single, definitive clean slate.
#
# WHAT THIS SCRIPT DOES:
#   1. Stops and disables the playit systemd service.
#   2. Purges the playit APT package (removes the vendor binary and unit).
#   3. Deletes ALL Playit state: /etc/playit, /opt/playit, /var/log/playit,
#      the systemd drop-in override, and any user-level config in ~/.config.
#   4. Reloads systemd.
#   5. Optionally re-runs setup-playit.sh for a fresh install.
#
# AFTER RUNNING THIS SCRIPT:
#   • Re-run:  sudo bash bin/setup-playit.sh
#   • Claim:   sudo -u playit /opt/playit/playit --secret_path /etc/playit/playit.toml
#   • Enable:  sudo systemctl enable --now playit
#
# NOTE: Go to https://playit.gg → Agents and DELETE any stale agents from
# previous installs so only the newly claimed agent remains.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

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
echo "  reset-playit.sh — Full Playit.gg Reset"
echo "============================================"
echo ""
warn "This will PERMANENTLY delete all Playit.gg configuration,"
warn "secrets, logs, and binaries from this machine."
echo ""
echo "  Affected paths:"
echo "    /opt/playit/               (binary + runtime data)"
echo "    /etc/playit/               (secret key + config)"
echo "    /var/log/playit/           (logs)"
echo "    /etc/systemd/system/playit.service.d/  (drop-in override)"
echo "    ~/.config/playit_gg/       (user-level identity, current user)"
echo "    /home/playit/.config/      (playit user home config)"
echo ""
read -r -p "  Type YES to confirm and proceed: " CONFIRM
echo ""
if [[ "${CONFIRM}" != "YES" ]]; then
  echo "  Aborted — nothing changed."
  exit 0
fi

# ── 1. Stop and disable the service ──────────────────────────────────────────
info "Stopping and disabling playit service..."
systemctl stop playit 2>/dev/null && ok "Service stopped." || info "Service was not running."
systemctl disable playit 2>/dev/null && ok "Service disabled." || info "Service was not enabled."

# ── 2. Purge the APT package ──────────────────────────────────────────────────
info "Purging playit APT package..."
apt-get remove --purge -y playit 2>/dev/null && ok "Package purged." || info "Package was not installed via APT."
apt-get autoremove -y -qq

# ── 3. Delete all Playit state ────────────────────────────────────────────────
info "Removing /opt/playit (binary + runtime data)..."
rm -rf /opt/playit
ok "Removed /opt/playit."

info "Removing /etc/playit (secret key + config)..."
rm -rf /etc/playit
ok "Removed /etc/playit."

info "Removing /var/log/playit (logs)..."
rm -rf /var/log/playit
ok "Removed /var/log/playit."

info "Removing systemd drop-in override..."
rm -rf /etc/systemd/system/playit.service.d
rm -f /etc/systemd/system/playit.service   # remove any manually placed unit, if present
ok "Drop-in removed."

info "Removing user-level Playit config (current user: ${SUDO_USER:-root})..."
if [[ -n "${SUDO_USER:-}" ]]; then
  USER_HOME=$(eval echo "~${SUDO_USER}")
  rm -rf "${USER_HOME}/.config/playit_gg"
  ok "Removed ${USER_HOME}/.config/playit_gg"
fi

info "Removing playit user home config (/opt/playit/.config)..."
rm -rf /opt/playit/.config/playit_gg
ok "Removed /opt/playit/.config/playit_gg (if it existed)."

# ── 4. Reload systemd ─────────────────────────────────────────────────────────
info "Reloading systemd..."
systemctl daemon-reload
ok "systemd reloaded."

echo ""
echo "✓ Playit.gg state fully removed."
echo ""

# ── 5. Offer to reinstall ─────────────────────────────────────────────────────
read -r -p "  Run setup-playit.sh now to reinstall? [y/N] " DO_SETUP
echo ""
if [[ "${DO_SETUP,,}" == "y" ]]; then
  echo "  Running setup-playit.sh..."
  echo ""
  bash "${REPO_ROOT}/bin/setup-playit.sh"
else
  echo "  Skipped reinstall."
  echo ""
  echo "  When you are ready, run:"
  echo "    sudo bash ${REPO_ROOT}/bin/setup-playit.sh"
  echo ""
  echo "  Then claim the agent as the service user:"
  echo "    sudo -u playit /opt/playit/playit \\"
  echo "      --secret_path /etc/playit/playit.toml"
  echo ""
  echo "  Finally, enable the service:"
  echo "    sudo systemctl enable --now playit"
  echo ""
  echo "  ⚠  Also go to https://playit.gg → Agents and DELETE any stale agents"
  echo "     from previous installs so only the new agent remains."
fi
