#!/usr/bin/env bash
# setup-playit.sh — Enable the Playit.gg Paper plugin for CGNAT scenarios
# Idempotent: safe to run multiple times.
#
# This script enables the Playit.gg Paper/Spigot plugin so the Minecraft
# server can accept player connections even when the host is behind CGNAT
# (no port-forwarding needed).
#
# The plugin runs inside the Paper server itself — no separate system service,
# APT package, or dedicated user is required.
#
# How it works:
#   1. Adds PLUGINS=<url> to /opt/minecraft/.env so the itzg Docker image
#      auto-downloads the plugin JAR from GitHub on each container start.
#   2. Restarts the Minecraft container to pick up the change.
#   3. The plugin prints a claim URL to the server console on first run.
set -euo pipefail

MC_DEST="/opt/minecraft"
ENV_FILE="${MC_DEST}/.env"
PLUGIN_URL="https://github.com/playit-cloud/playit-minecraft-plugin/releases/latest/download/playit-minecraft-plugin.jar"

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

# ── Add PLUGINS URL to .env ───────────────────────────────────────────────────
if grep -q "^PLUGINS=.*playit-minecraft-plugin" "${ENV_FILE}" 2>/dev/null; then
  ok "Playit.gg plugin URL is already in PLUGINS."
elif grep -q "^PLUGINS=" "${ENV_FILE}" 2>/dev/null; then
  # PLUGINS exists but doesn't include the playit plugin — append it
  CURRENT=$(grep "^PLUGINS=" "${ENV_FILE}" | tail -1 | cut -d= -f2-)
  if [[ -z "${CURRENT}" ]]; then
    sed -i "s|^PLUGINS=.*|PLUGINS=${PLUGIN_URL}|" "${ENV_FILE}"
  else
    sed -i "s|^PLUGINS=.*|PLUGINS=${CURRENT},${PLUGIN_URL}|" "${ENV_FILE}"
  fi
  ok "Added Playit.gg plugin URL to existing PLUGINS."
elif grep -q "^# *PLUGINS=" "${ENV_FILE}" 2>/dev/null; then
  # Commented-out PLUGINS line — uncomment and set
  sed -i "s|^# *PLUGINS=.*|PLUGINS=${PLUGIN_URL}|" "${ENV_FILE}"
  ok "Uncommented and set PLUGINS to Playit.gg plugin URL."
else
  # No PLUGINS line at all — add it
  {
    echo ""
    echo "# Playit.gg plugin for CGNAT tunneling"
    echo "PLUGINS=${PLUGIN_URL}"
  } >> "${ENV_FILE}"
  ok "Added PLUGINS=${PLUGIN_URL} to ${ENV_FILE}."
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
