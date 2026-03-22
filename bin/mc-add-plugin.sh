#!/usr/bin/env bash
# mc-add-plugin.sh — Install a Minecraft plugin into the Paper server
# Accepts a local .jar file path or a direct-download URL.
#
# Usage:
#   bash bin/mc-add-plugin.sh /path/to/PluginName.jar
#   bash bin/mc-add-plugin.sh https://example.com/PluginName.jar
#
# The server is restarted automatically after installation so the plugin loads.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MC_DIR="/opt/minecraft"
PLUGINS_DIR="${MC_DIR}/data/plugins"

ok()   { printf "  \033[32m✓\033[0m  %s\n" "$*"; }
fail() { printf "  \033[31m✗\033[0m  %s\n" "$*"; }
info() { printf "  \033[34m»\033[0m  %s\n" "$*"; }
warn() { printf "  \033[33m⚠\033[0m  %s\n" "$*"; }

# ── Validate input ────────────────────────────────────────────────────────────
if [[ $# -lt 1 ]]; then
  fail "Usage: bash bin/mc-add-plugin.sh <file.jar | https://...>"
  exit 1
fi

INPUT="$1"

# ── Ensure plugins directory exists ──────────────────────────────────────────
if [[ ! -d "${PLUGINS_DIR}" ]]; then
  info "Creating plugins directory: ${PLUGINS_DIR}"
  mkdir -p "${PLUGINS_DIR}"
fi

# ── Download or copy the plugin ───────────────────────────────────────────────
if [[ "${INPUT}" == http* ]]; then
  FILENAME=$(basename "${INPUT%%\?*}")   # strip query string from URL
  [[ "${FILENAME}" != *.jar ]] && FILENAME="${FILENAME}.jar"
  DEST="${PLUGINS_DIR}/${FILENAME}"

  if ! command -v curl &>/dev/null; then
    fail "curl is required for URL downloads. Run: sudo apt-get install -y curl"
    exit 1
  fi

  info "Downloading ${FILENAME}..."
  curl -fL --progress-bar "${INPUT}" -o "${DEST}"
  ok "Downloaded to ${DEST}"
else
  if [[ ! -f "${INPUT}" ]]; then
    fail "File not found: ${INPUT}"
    exit 1
  fi
  FILENAME=$(basename "${INPUT}")
  DEST="${PLUGINS_DIR}/${FILENAME}"
  info "Copying ${FILENAME}..."
  cp "${INPUT}" "${DEST}"
  ok "Copied to ${DEST}"
fi

# ── Restart the server to load the plugin ────────────────────────────────────
echo ""
info "Restarting Minecraft server to load the plugin..."
bash "${SCRIPT_DIR}/mc-restart.sh"
ok "Plugin '${FILENAME}' installed and server restarted."
