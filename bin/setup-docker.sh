#!/usr/bin/env bash
# setup-docker.sh — Install Docker CE and the Compose plugin
# Idempotent: safe to run multiple times.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

info()  { echo "  [INFO]  $*"; }
ok()    { echo "  [ OK ]  $*"; }

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    echo "ERROR: Run this script with sudo or as root." >&2
    exit 1
  fi
}

require_root

echo ""
echo "============================================"
echo "  setup-docker.sh — Docker CE + Compose"
echo "============================================"
echo ""

# ── Remove old / conflicting packages ─────────────────────────────────────────
info "Removing any conflicting old Docker packages..."
for pkg in docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc; do
  apt-get remove -y -qq "${pkg}" 2>/dev/null || true
done
ok "Old packages removed."

# ── Install Docker CE via official repo ───────────────────────────────────────
DOCKER_KEYRING="/etc/apt/keyrings/docker.gpg"

if [[ ! -f "${DOCKER_KEYRING}" ]]; then
  info "Adding Docker GPG key..."
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
    | gpg --dearmor -o "${DOCKER_KEYRING}"
  chmod a+r "${DOCKER_KEYRING}"
  ok "Docker GPG key added."
else
  ok "Docker GPG key already present."
fi

DOCKER_REPO_FILE="/etc/apt/sources.list.d/docker.list"
if [[ ! -f "${DOCKER_REPO_FILE}" ]]; then
  info "Adding Docker apt repository..."
  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=${DOCKER_KEYRING}] \
https://download.docker.com/linux/ubuntu \
$(. /etc/os-release && echo "${VERSION_CODENAME}") stable" \
    > "${DOCKER_REPO_FILE}"
  apt-get update -qq
  ok "Docker repository added."
else
  ok "Docker repository already present."
fi

if ! command -v docker &>/dev/null; then
  info "Installing Docker CE packages..."
  DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
    docker-ce \
    docker-ce-cli \
    containerd.io \
    docker-buildx-plugin \
    docker-compose-plugin
  ok "Docker CE installed."
else
  DOCKER_VER=$(docker --version)
  ok "Docker already installed: ${DOCKER_VER}"
fi

# ── Enable and start Docker ───────────────────────────────────────────────────
info "Enabling and starting Docker service..."
systemctl enable --now docker
ok "Docker service is active."

# ── Add the calling user (and optionally a deploy user) to docker group ───────
# The SUDO_USER var is set when the script is run via sudo
DEPLOY_USER="${HOMELAB_DEPLOY_USER:-${SUDO_USER:-}}"
if [[ -n "${DEPLOY_USER}" ]] && id "${DEPLOY_USER}" &>/dev/null; then
  if ! groups "${DEPLOY_USER}" | grep -q docker; then
    info "Adding ${DEPLOY_USER} to the docker group..."
    usermod -aG docker "${DEPLOY_USER}"
    ok "${DEPLOY_USER} added to docker group. (Log out/in for group to take effect.)"
  else
    ok "${DEPLOY_USER} already in docker group."
  fi
else
  warn "Could not determine a non-root user to add to docker group."
  warn "Run: sudo usermod -aG docker <your-username>"
fi

# ── Verify installation ───────────────────────────────────────────────────────
info "Verifying Docker installation..."
docker --version
docker compose version
ok "Docker and Compose plugin verified."

echo ""
echo "✓ Docker setup complete."
echo ""
echo "  NOTE: If you were just added to the docker group, log out and back in"
echo "        (or run 'newgrp docker') for it to take effect."
echo ""
echo "  NEXT STEPS:"
echo "    sudo bash ${REPO_ROOT}/bin/setup-firewall.sh"
echo ""
