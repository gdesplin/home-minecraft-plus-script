#!/usr/bin/env bash
# mc-start.sh — Start (or restart) the Minecraft Docker container
# Safe to run when the container is already running (it will be a no-op).
set -euo pipefail

MC_DIR="/opt/minecraft"

ok()   { printf "  \033[32m✓\033[0m  %s\n" "$*"; }
fail() { printf "  \033[31m✗\033[0m  %s\n" "$*"; }
info() { printf "  \033[34m»\033[0m  %s\n" "$*"; }

if [[ ! -f "${MC_DIR}/compose.yml" ]]; then
  fail "Minecraft is not set up (${MC_DIR}/compose.yml not found)."
  echo "     Run: sudo bash bin/setup-minecraft.sh"
  exit 1
fi

info "Starting Minecraft server..."
docker compose -f "${MC_DIR}/compose.yml" up -d
ok "Minecraft container started."
echo ""
docker compose -f "${MC_DIR}/compose.yml" ps
echo ""
echo "  Follow logs  : sudo bash bin/mc-logs.sh"
echo "  Admin console: sudo bash bin/mc-console.sh"
