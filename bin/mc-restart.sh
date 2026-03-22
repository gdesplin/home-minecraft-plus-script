#!/usr/bin/env bash
# mc-restart.sh — Gracefully restart the Minecraft server
# Performs a clean save-all + stop (via mc-stop.sh) then starts fresh.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

ok()   { printf "  \033[32m✓\033[0m  %s\n" "$*"; }
info() { printf "  \033[34m»\033[0m  %s\n" "$*"; }

info "Stopping server..."
bash "${SCRIPT_DIR}/mc-stop.sh"

echo ""
info "Starting server..."
bash "${SCRIPT_DIR}/mc-start.sh"

ok "Restart complete."
