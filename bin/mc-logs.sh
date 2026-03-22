#!/usr/bin/env bash
# mc-logs.sh — Follow live Minecraft server logs
# Press Ctrl+C to exit.
set -euo pipefail

MC_DIR="/opt/minecraft"

fail() { printf "  \033[31m✗\033[0m  %s\n" "$*"; }

if [[ ! -f "${MC_DIR}/compose.yml" ]]; then
  fail "Minecraft is not set up (${MC_DIR}/compose.yml not found)."
  exit 1
fi

echo "  Following Minecraft logs (Ctrl+C to exit)..."
echo ""
docker compose -f "${MC_DIR}/compose.yml" logs -f
