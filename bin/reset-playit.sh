#!/usr/bin/env bash
# reset-playit.sh — Remove the playit.gg agent, its service, and its data
#
# USE THIS WHEN:
#   • You want to stop using Playit.gg tunneling.
#   • You need a fresh Playit.gg claim (new identity).
#   • You are switching from Playit.gg to direct port-forwarding.
#
# WHAT THIS SCRIPT DOES:
#   1. Stops and disables playit.service
#   2. Removes the systemd unit file and reloads systemd
#   3. Removes /etc/playit/ (agent secret — forces re-claim on reinstall)
#   4. Removes /usr/local/bin/playit
#
# AFTER RUNNING THIS SCRIPT:
#   • To re-enable: sudo bash bin/setup-playit.sh
#
# NOTE: Go to https://playit.gg → Agents and DELETE any stale agents from
# previous installs so only the current agent remains.
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
echo "  reset-playit.sh — Remove Playit.gg Agent"
echo "============================================"
echo ""
warn "This will stop and remove the playit.gg agent service, its binary,"
warn "and its configuration directory (including the agent secret)."
echo ""
echo "  Affected paths:"
echo "    ${PLAYIT_SERVICE}   (systemd unit)"
echo "    ${PLAYIT_DIR}/                  (agent secret + config)"
echo "    ${PLAYIT_BIN}       (agent binary)"
echo ""
read -r -p "  Type YES to confirm and proceed: " CONFIRM
echo ""
if [[ "${CONFIRM}" != "YES" ]]; then
  echo "  Aborted — nothing changed."
  exit 0
fi

# ── 1. Stop and disable the service ──────────────────────────────────────────
info "Stopping playit.service..."
systemctl stop playit.service 2>/dev/null || true
ok "playit.service stopped (or was not running)."

info "Disabling playit.service..."
systemctl disable playit.service 2>/dev/null || true
ok "playit.service disabled (or was not enabled)."

# ── 2. Remove the systemd unit file ──────────────────────────────────────────
if [[ -f "${PLAYIT_SERVICE}" ]]; then
  rm -f "${PLAYIT_SERVICE}"
  ok "Removed ${PLAYIT_SERVICE}."
else
  ok "${PLAYIT_SERVICE} not found — skipping."
fi

info "Reloading systemd..."
systemctl daemon-reload
ok "systemd reloaded."

# ── 3. Remove agent data directory (secret) ───────────────────────────────────
if [[ -d "${PLAYIT_DIR}" ]]; then
  rm -rf "${PLAYIT_DIR}"
  ok "Removed ${PLAYIT_DIR}/ (agent secret deleted)."
else
  ok "${PLAYIT_DIR}/ not found — skipping."
fi

# ── 4. Remove agent binary ────────────────────────────────────────────────────
if [[ -f "${PLAYIT_BIN}" ]]; then
  rm -f "${PLAYIT_BIN}"
  ok "Removed ${PLAYIT_BIN}."
else
  ok "${PLAYIT_BIN} not found — skipping."
fi

echo ""
echo "✓ Playit.gg agent removed."
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
  echo "  ⚠  Also go to https://playit.gg → Agents and DELETE any stale agents"
  echo "     from previous installs so only the current agent remains."
fi
