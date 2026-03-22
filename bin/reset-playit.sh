#!/usr/bin/env bash
# reset-playit.sh — Remove the Playit.gg plugin and its data
#
# USE THIS WHEN:
#   • You want to stop using Playit.gg tunneling.
#   • You need a fresh Playit.gg claim (new identity).
#   • You are switching from the plugin to direct port-forwarding.
#
# WHAT THIS SCRIPT DOES:
#   1. Removes PLUGINS / SPIGET_RESOURCES entries for the Playit.gg plugin from .env
#   2. Deletes the plugin JAR and data directory from the server
#   3. Restarts the Minecraft container
#
# AFTER RUNNING THIS SCRIPT:
#   • To re-enable: sudo bash bin/setup-playit.sh
#
# NOTE: Go to https://playit.gg → Agents and DELETE any stale agents from
# previous installs so only the current agent remains.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
MC_DEST="/opt/minecraft"
ENV_FILE="${MC_DEST}/.env"
PLUGIN_ID="105566"
PLUGIN_DIR="${MC_DEST}/data/plugins"
PLUGIN_URL_PATTERN="playit-minecraft-plugin"

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
echo "  reset-playit.sh — Remove Playit.gg Plugin"
echo "============================================"
echo ""
warn "This will remove the Playit.gg plugin and its configuration"
warn "from the Minecraft server."
echo ""
echo "  Affected paths:"
echo "    ${PLUGIN_DIR}/PlayitGg/             (plugin data + config)"
echo "    ${PLUGIN_DIR}/PlayitGg*.jar         (plugin JAR)"
echo "    ${ENV_FILE}                         (PLUGINS / SPIGET_RESOURCES entry)"
echo ""
read -r -p "  Type YES to confirm and proceed: " CONFIRM
echo ""
if [[ "${CONFIRM}" != "YES" ]]; then
  echo "  Aborted — nothing changed."
  exit 0
fi

# ── 1. Remove plugin entries from .env ────────────────────────────────────────
if [[ -f "${ENV_FILE}" ]]; then
  info "Updating ${ENV_FILE}..."

  # ── Remove Playit.gg URL from PLUGINS ──────────────────────────────────────
  if grep -q "^PLUGINS=" "${ENV_FILE}" 2>/dev/null; then
    CURRENT=$(grep "^PLUGINS=" "${ENV_FILE}" | tail -1 | cut -d= -f2-)
    # Remove any URL containing the playit plugin pattern
    NEW_VALUE=$(echo "${CURRENT}" | tr ',' '\n' | { grep -v "${PLUGIN_URL_PATTERN}" || true; } | paste -sd ',' - )
    if [[ -z "${NEW_VALUE}" ]]; then
      sed -i "s|^PLUGINS=.*|# PLUGINS=|" "${ENV_FILE}"
      ok "Removed PLUGINS (no other plugins)."
    else
      sed -i "s|^PLUGINS=.*|PLUGINS=${NEW_VALUE}|" "${ENV_FILE}"
      ok "Removed Playit.gg from PLUGINS (kept other entries)."
    fi
  else
    ok "PLUGINS not found in .env — nothing to remove."
  fi

  # ── Remove Playit.gg ID from SPIGET_RESOURCES (legacy) ────────────────────
  if grep -q "^SPIGET_RESOURCES=" "${ENV_FILE}" 2>/dev/null; then
    CURRENT=$(grep "^SPIGET_RESOURCES=" "${ENV_FILE}" | tail -1 | cut -d= -f2)
    NEW_VALUE=$(echo "${CURRENT}" | sed "s/${PLUGIN_ID}//g" | sed 's/,,/,/g' | sed 's/^,//;s/,$//')
    if [[ -z "${NEW_VALUE}" ]]; then
      sed -i "s|^SPIGET_RESOURCES=.*|# SPIGET_RESOURCES=|" "${ENV_FILE}"
      ok "Removed SPIGET_RESOURCES (no other plugins)."
    else
      sed -i "s|^SPIGET_RESOURCES=.*|SPIGET_RESOURCES=${NEW_VALUE}|" "${ENV_FILE}"
      ok "Removed Playit.gg from SPIGET_RESOURCES (kept: ${NEW_VALUE})."
    fi
  fi
else
  warn "${ENV_FILE} not found."
fi

# ── 2. Delete plugin files ────────────────────────────────────────────────────
info "Removing plugin files..."
rm -rf "${PLUGIN_DIR:?}/PlayitGg" 2>/dev/null && ok "Removed ${PLUGIN_DIR}/PlayitGg/" || true
# Plugin JAR name may vary (e.g. PlayitGg-0.1.2.jar)
find "${PLUGIN_DIR}" -maxdepth 1 -name 'PlayitGg*.jar' -delete 2>/dev/null \
  && ok "Removed PlayitGg*.jar" || true
# Also check for lowercase variants
find "${PLUGIN_DIR}" -maxdepth 1 -iname 'playit*.jar' -delete 2>/dev/null || true

# ── 3. Restart Minecraft container ───────────────────────────────────────────
if [[ -f "${MC_DEST}/compose.yml" ]]; then
  info "Restarting Minecraft container..."
  cd "${MC_DEST}"
  if docker compose ps 2>/dev/null | grep -q "running\|Up"; then
    docker compose up -d --force-recreate
    ok "Minecraft container restarted."
  else
    warn "Minecraft container is not running — skipping restart."
  fi
else
  warn "compose.yml not found — skipping restart."
fi

echo ""
echo "✓ Playit.gg plugin removed."
echo ""

# ── 4. Offer to reinstall ─────────────────────────────────────────────────────
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
