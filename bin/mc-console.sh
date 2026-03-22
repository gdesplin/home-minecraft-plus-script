#!/usr/bin/env bash
# mc-console.sh — Open the Minecraft admin console (RCON)
# Type server commands interactively.  Type 'exit' or press Ctrl+C to quit.
#
# Common commands:
#   list                         — show online players
#   say <message>                — broadcast a message
#   op <player>                  — grant operator status
#   whitelist add <player>       — add to whitelist
#   gamemode creative <player>   — change game mode
#   tp <player> <x> <y> <z>     — teleport a player
#   kick <player> [reason]       — kick a player
#   help                         — list all commands
set -euo pipefail

MC_DIR="/opt/minecraft"
RCON_HOST="127.0.0.1"
RCON_PORT="25575"

fail() { printf "  \033[31m✗\033[0m  %s\n" "$*"; }
warn() { printf "  \033[33m⚠\033[0m  %s\n" "$*"; }

if ! docker ps --filter "name=^mc$" --filter "status=running" \
     --format "{{.Names}}" 2>/dev/null | grep -q "^mc$"; then
  fail "Minecraft container is not running."
  echo "     Run: sudo bash bin/mc-start.sh"
  exit 1
fi

# Load RCON password from .env
RCON_PASSWORD=""
if [[ -f "${MC_DIR}/.env" ]]; then
  RCON_PASSWORD=$(grep -E '^RCON_PASSWORD=' "${MC_DIR}/.env" | cut -d= -f2- | tr -d '"' || true)
fi

if [[ -z "${RCON_PASSWORD}" ]]; then
  warn "RCON_PASSWORD not found in ${MC_DIR}/.env — attempting without password."
fi

echo "  Connecting to Minecraft admin console..."
echo "  Type 'exit' or press Ctrl+C to quit."
echo ""
exec docker exec -it mc rcon-cli \
  --host "${RCON_HOST}" \
  --port "${RCON_PORT}" \
  --password "${RCON_PASSWORD}"
