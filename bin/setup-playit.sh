#!/usr/bin/env bash
# setup-playit.sh — Enable the Playit.gg Paper plugin for CGNAT scenarios
# Idempotent: safe to run multiple times.
#
# This script enables the Playit.gg Paper/Spigot plugin (SpigotMC resource
# 105566) so the Minecraft server can accept player connections even when the
# host is behind CGNAT (no port-forwarding needed).
#
# The plugin runs inside the Paper server itself — no separate system service,
# APT package, or dedicated user is required.
#
# How it works:
#   1. Adds SPIGET_RESOURCES=105566 to /opt/minecraft/.env so the itzg Docker
#      image auto-downloads the plugin on next container start.
#   2. Restarts the Minecraft container to pick up the change.
#   3. The plugin prints a claim URL to the server console on first run.
set -euo pipefail

MC_DEST="/opt/minecraft"
ENV_FILE="${MC_DEST}/.env"
PLUGIN_ID="105566"

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
echo "  setup-playit.sh — Playit.gg Plugin"
echo "============================================"
echo ""

# ── Verify Minecraft is deployed ──────────────────────────────────────────────
if [[ ! -f "${ENV_FILE}" ]]; then
  err "Minecraft .env not found at ${ENV_FILE}."
  err "Run setup-minecraft.sh first."
  exit 1
fi

if [[ ! -f "${MC_DEST}/compose.yml" ]]; then
  err "compose.yml not found at ${MC_DEST}/compose.yml."
  err "Run setup-minecraft.sh first."
  exit 1
fi

# ── Verify server type supports plugins ───────────────────────────────────────
SERVER_TYPE=$(grep -i "^TYPE=" "${ENV_FILE}" | tail -1 | cut -d= -f2 || echo "")
SERVER_TYPE="${SERVER_TYPE:-PAPER}"
case "${SERVER_TYPE^^}" in
  PAPER|SPIGOT|BUKKIT)
    ok "Server type '${SERVER_TYPE}' supports plugins."
    ;;
  *)
    err "Server type '${SERVER_TYPE}' does not support Spigot/Paper plugins."
    err "The Playit.gg plugin requires TYPE=PAPER (recommended) or TYPE=SPIGOT."
    exit 1
    ;;
esac

# ── Add SPIGET_RESOURCES to .env ──────────────────────────────────────────────
if grep -q "^SPIGET_RESOURCES=.*${PLUGIN_ID}" "${ENV_FILE}" 2>/dev/null; then
  ok "Playit.gg plugin (${PLUGIN_ID}) is already in SPIGET_RESOURCES."
elif grep -q "^SPIGET_RESOURCES=" "${ENV_FILE}" 2>/dev/null; then
  # SPIGET_RESOURCES exists but doesn't include the playit plugin — append it
  CURRENT=$(grep "^SPIGET_RESOURCES=" "${ENV_FILE}" | tail -1 | cut -d= -f2)
  if [[ -z "${CURRENT}" ]]; then
    sed -i "s|^SPIGET_RESOURCES=.*|SPIGET_RESOURCES=${PLUGIN_ID}|" "${ENV_FILE}"
  else
    sed -i "s|^SPIGET_RESOURCES=.*|SPIGET_RESOURCES=${CURRENT},${PLUGIN_ID}|" "${ENV_FILE}"
  fi
  ok "Added Playit.gg plugin to existing SPIGET_RESOURCES."
elif grep -q "^# *SPIGET_RESOURCES=" "${ENV_FILE}" 2>/dev/null; then
  # Commented-out SPIGET_RESOURCES line — uncomment and set
  sed -i "s|^# *SPIGET_RESOURCES=.*|SPIGET_RESOURCES=${PLUGIN_ID}|" "${ENV_FILE}"
  ok "Uncommented and set SPIGET_RESOURCES=${PLUGIN_ID}."
else
  # No SPIGET_RESOURCES line at all — add it
  {
    echo ""
    echo "# Playit.gg plugin for CGNAT tunneling"
    echo "SPIGET_RESOURCES=${PLUGIN_ID}"
  } >> "${ENV_FILE}"
  ok "Added SPIGET_RESOURCES=${PLUGIN_ID} to ${ENV_FILE}."
fi

# ── Restart the Minecraft container ───────────────────────────────────────────
info "Restarting Minecraft container to download the plugin..."
cd "${MC_DEST}"
if docker compose ps 2>/dev/null | grep -q "running\|Up"; then
  docker compose up -d --force-recreate
  ok "Minecraft container restarted."
else
  warn "Minecraft container is not running. Starting it..."
  docker compose up -d
  ok "Minecraft container started."
fi

echo ""
echo "✓ Playit.gg plugin enabled."
echo ""
echo "  ┌─ NEXT STEPS ──────────────────────────────────────────────────────────┐"
echo "  │                                                                       │"
echo "  │  1. Wait for the server to finish starting (~60–90 s), then check     │"
echo "  │     the server console for a Playit.gg claim URL:                     │"
echo "  │       sudo docker compose -f ${MC_DEST}/compose.yml logs -f           │"
echo "  │                                                                       │"
echo "  │     Look for a line like:                                             │"
echo "  │       [playit-gg] Visit https://playit.gg/claim/xxxxx to claim ...    │"
echo "  │                                                                       │"
echo "  │  2. Open the URL in a browser and log in to playit.gg.                │"
echo "  │                                                                       │"
echo "  │  3. The plugin automatically creates a TCP tunnel for port 25565.     │"
echo "  │     For Bedrock (UDP 19132), add a tunnel on the playit.gg dashboard. │"
echo "  │                                                                       │"
echo "  │  4. Share your tunnel address with players:                           │"
echo "  │       yourname.joinplayit.gg                                          │"
echo "  │                                                                       │"
echo "  └───────────────────────────────────────────────────────────────────────┘"
echo ""
echo "  Useful commands:"
echo "    sudo docker compose -f ${MC_DEST}/compose.yml logs -f"
echo "    sudo docker exec mc rcon-cli"
echo ""
echo "  Plugin data is stored in: ${MC_DEST}/data/plugins/PlayitGg/"
echo ""
