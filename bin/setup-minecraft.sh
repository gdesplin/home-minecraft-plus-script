#!/usr/bin/env bash
# setup-minecraft.sh — Deploy the Minecraft Paper server via Docker Compose
# Idempotent: safe to run multiple times.
# Requires: docker (setup-docker.sh), compose plugin, and minecraft/.env
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
MC_SRC="${REPO_ROOT}/minecraft"
MC_DEST="/opt/minecraft"
ENV_EXAMPLE="${MC_SRC}/.env.example"
ENV_SRC="${MC_SRC}/.env"
ENV_DEST="${MC_DEST}/.env"

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
echo "  setup-minecraft.sh — Minecraft server"
echo "============================================"
echo ""

# ── Verify Docker is available ────────────────────────────────────────────────
if ! command -v docker &>/dev/null; then
  err "Docker is not installed. Run setup-docker.sh first."
  exit 1
fi
if ! docker compose version &>/dev/null; then
  err "Docker Compose plugin not found. Run setup-docker.sh first."
  exit 1
fi

# ── Create deployment directory ───────────────────────────────────────────────
info "Creating deployment directory ${MC_DEST}..."
mkdir -p "${MC_DEST}/data"
ok "Directories ready."

# ── Copy compose.yml ──────────────────────────────────────────────────────────
info "Copying compose.yml to ${MC_DEST}..."
cp -f "${MC_SRC}/compose.yml" "${MC_DEST}/compose.yml"
ok "compose.yml copied."

# ── Handle .env ───────────────────────────────────────────────────────────────
if [[ ! -f "${ENV_DEST}" ]]; then
  if [[ -f "${ENV_SRC}" ]]; then
    info "Copying minecraft/.env to ${ENV_DEST}..."
    cp "${ENV_SRC}" "${ENV_DEST}"
    ok ".env copied."
  else
    info "No minecraft/.env found; copying .env.example as starting point..."
    cp "${ENV_EXAMPLE}" "${ENV_DEST}"
    warn "A placeholder .env was created at ${ENV_DEST}."
    warn "You MUST set EULA=TRUE before the server will start."
    warn "Edit ${ENV_DEST} now, then re-run this script."
    echo ""
    echo "  nano ${ENV_DEST}"
    echo ""
    exit 0
  fi
else
  ok ".env already exists at ${ENV_DEST}. Skipping (will not overwrite secrets)."
fi

# ── Confirm EULA is accepted ──────────────────────────────────────────────────
if ! grep -qi "^EULA=TRUE" "${ENV_DEST}"; then
  err "EULA=TRUE is not set in ${ENV_DEST}."
  err "You must accept the Minecraft EULA: https://aka.ms/MinecraftEULA"
  err "Add 'EULA=TRUE' to ${ENV_DEST} and re-run this script."
  exit 1
fi
ok "EULA accepted."

# ── Ensure correct ownership ──────────────────────────────────────────────────
DEPLOY_USER="${HOMELAB_DEPLOY_USER:-${SUDO_USER:-root}}"
chown -R "${DEPLOY_USER}:${DEPLOY_USER}" "${MC_DEST}" 2>/dev/null || true

# ── Pull latest image ─────────────────────────────────────────────────────────
info "Pulling latest Minecraft Docker image..."
cd "${MC_DEST}"
docker compose pull
ok "Image pulled."

# ── Start (or restart) the server ─────────────────────────────────────────────
info "Starting Minecraft server..."
docker compose up -d
ok "Minecraft container started."

# ── Wait a moment and check status ───────────────────────────────────────────
sleep 5
echo ""
docker compose ps
echo ""
echo "✓ Minecraft setup complete."
echo ""
echo "  Server directory : ${MC_DEST}"
echo "  World data       : ${MC_DEST}/data"
echo "  Logs             : sudo docker compose -f ${MC_DEST}/compose.yml logs -f"
echo "  Console          : sudo docker exec -it mc rcon-cli"
echo ""
echo "  Players connect to: <your-ip-or-duckdns-hostname>:25565"
echo ""
echo "  NEXT STEPS:"
echo "    Edit backups/restic.env then:"
echo "    sudo bash ${REPO_ROOT}/bin/setup-backups.sh"
echo ""
