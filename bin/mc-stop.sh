#!/usr/bin/env bash
# mc-stop.sh — Gracefully stop the Minecraft server
# Sends save-all then stop via RCON before halting the Docker container so that
# the world data is flushed cleanly and no chunks are lost.
set -euo pipefail

MC_DIR="/opt/minecraft"
RCON_HOST="127.0.0.1"
RCON_PORT="25575"

ok()   { printf "  \033[32m✓\033[0m  %s\n" "$*"; }
warn() { printf "  \033[33m⚠\033[0m  %s\n" "$*"; }
fail() { printf "  \033[31m✗\033[0m  %s\n" "$*"; }
info() { printf "  \033[34m»\033[0m  %s\n" "$*"; }

if [[ ! -f "${MC_DIR}/compose.yml" ]]; then
  fail "Minecraft is not set up (${MC_DIR}/compose.yml not found)."
  exit 1
fi

# Load RCON password from .env (if present)
RCON_PASSWORD=""
if [[ -f "${MC_DIR}/.env" ]]; then
  RCON_PASSWORD=$(grep -E '^RCON_PASSWORD=' "${MC_DIR}/.env" | cut -d= -f2- | tr -d '"' || true)
fi

# ── Graceful RCON shutdown ────────────────────────────────────────────────────
if docker ps --filter "name=^mc$" --filter "status=running" \
     --format "{{.Names}}" 2>/dev/null | grep -q "^mc$"; then
  info "Sending save-all to flush world data..."
  docker exec mc rcon-cli \
    --host "${RCON_HOST}" --port "${RCON_PORT}" \
    --password "${RCON_PASSWORD}" \
    "save-all" 2>/dev/null && ok "save-all sent." || warn "save-all failed (server may still be starting)."
  sleep 2

  info "Sending stop command..."
  docker exec mc rcon-cli \
    --host "${RCON_HOST}" --port "${RCON_PORT}" \
    --password "${RCON_PASSWORD}" \
    "stop" 2>/dev/null && ok "stop command sent." || warn "RCON stop failed — will stop the container directly."
  sleep 3
else
  warn "Minecraft container is not running."
fi

# ── Stop the container ────────────────────────────────────────────────────────
info "Stopping Minecraft container..."
docker compose -f "${MC_DIR}/compose.yml" stop
ok "Minecraft server stopped."
