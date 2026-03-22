#!/usr/bin/env bash
# setup-minecraft.sh — Deploy the Paper Minecraft server bare-metal (no Docker)
# Idempotent: safe to run multiple times.
# Manages the server via a systemd unit (minecraft.service).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
MC_HOME="/opt/minecraft"
MC_DATA="${MC_HOME}/data"
MC_BIN="${MC_HOME}/bin"
MC_JAR="${MC_BIN}/paper.jar"
MC_SERVICE="/etc/systemd/system/minecraft.service"

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
echo "  setup-minecraft.sh — Paper Minecraft"
echo "  (bare-metal, systemd managed)"
echo "============================================"
echo ""

# ── 1. Install Java 21 ────────────────────────────────────────────────────────
if ! java -version 2>&1 | grep -q "21\."; then
  info "Installing OpenJDK 21..."
  apt-get install -y -qq openjdk-21-jre-headless
  ok "Java 21 installed."
else
  ok "Java 21 already installed."
fi

# ── 2. Create minecraft system user ──────────────────────────────────────────
if ! id minecraft &>/dev/null; then
  info "Creating 'minecraft' system user..."
  useradd -r -m -d "${MC_HOME}" minecraft
  ok "User 'minecraft' created."
else
  ok "User 'minecraft' already exists."
fi

# ── 3. Create directories ─────────────────────────────────────────────────────
info "Creating directories..."
mkdir -p "${MC_DATA}" "${MC_BIN}"
ok "Directories ready: ${MC_DATA}, ${MC_BIN}"

# ── 4. Download latest Paper JAR ──────────────────────────────────────────────
info "Fetching latest Paper version from PaperMC API..."
PAPER_VERSION=$(curl -fsSL "https://api.papermc.io/v2/projects/paper" \
  | grep -oP '"versions":\[.*?\]' | grep -oP '"[0-9]+\.[0-9]+(?:\.[0-9]+)?"' \
  | tail -1 | tr -d '"')
if [[ -z "${PAPER_VERSION}" ]]; then
  err "Failed to determine latest Paper version from the PaperMC API."
  exit 1
fi
info "Latest Paper version: ${PAPER_VERSION}"

PAPER_BUILD=$(curl -fsSL \
  "https://api.papermc.io/v2/projects/paper/versions/${PAPER_VERSION}/builds" \
  | grep -oP '"build":\s*\K[0-9]+' | tail -1)
if [[ -z "${PAPER_BUILD}" ]]; then
  err "Failed to determine latest Paper build for version ${PAPER_VERSION}."
  exit 1
fi
info "Latest Paper build: ${PAPER_BUILD}"

PAPER_JAR_NAME="paper-${PAPER_VERSION}-${PAPER_BUILD}.jar"
PAPER_URL="https://api.papermc.io/v2/projects/paper/versions/${PAPER_VERSION}/builds/${PAPER_BUILD}/downloads/${PAPER_JAR_NAME}"
info "Downloading ${PAPER_JAR_NAME}..."
curl -fsSL -o "${MC_JAR}" "${PAPER_URL}"
ok "Paper JAR saved to ${MC_JAR}."

# ── 5. Write eula.txt ─────────────────────────────────────────────────────────
if ! grep -q "^eula=true" "${MC_DATA}/eula.txt" 2>/dev/null; then
  info "Writing eula.txt (accepting Minecraft EULA: https://aka.ms/MinecraftEULA)..."
  echo "eula=true" > "${MC_DATA}/eula.txt"
  ok "eula.txt written."
else
  ok "eula.txt already contains eula=true."
fi

# ── 6. Write server.properties (only if missing — never overwrite) ────────────
if [[ ! -f "${MC_DATA}/server.properties" ]]; then
  info "Writing default server.properties..."
  cat > "${MC_DATA}/server.properties" <<'EOF'
server-ip=0.0.0.0
server-port=25565
online-mode=true
max-players=20
difficulty=normal
motd=A Minecraft Server
enable-rcon=true
rcon.port=25575
rcon.password=changeme_rcon_secret
view-distance=8
simulation-distance=6
EOF
  ok "server.properties written."
else
  ok "server.properties already exists — not overwriting."
fi

# ── 7. Fix ownership ──────────────────────────────────────────────────────────
info "Setting ownership of ${MC_HOME} to minecraft:minecraft..."
chown -R minecraft:minecraft "${MC_HOME}"
ok "Ownership set."

# ── 8. Write systemd unit ─────────────────────────────────────────────────────
info "Writing ${MC_SERVICE}..."
cat > "${MC_SERVICE}" <<'EOF'
[Unit]
Description=Paper Minecraft Server
After=network.target

[Service]
User=minecraft
Group=minecraft
WorkingDirectory=/opt/minecraft/data
ExecStart=/usr/bin/java -Xms1G -Xmx4G \
  -XX:+UseG1GC \
  -XX:+ParallelRefProcEnabled \
  -XX:MaxGCPauseMillis=200 \
  -XX:+UnlockExperimentalVMOptions \
  -XX:+DisableExplicitGC \
  -XX:+AlwaysPreTouch \
  -XX:G1NewSizePercent=30 \
  -XX:G1MaxNewSizePercent=40 \
  -XX:G1HeapRegionSize=8M \
  -XX:G1ReservePercent=20 \
  -XX:G1HeapWastePercent=5 \
  -XX:G1MixedGCCountTarget=4 \
  -XX:InitiatingHeapOccupancyPercent=15 \
  -XX:G1MixedGCLiveThresholdPercent=90 \
  -XX:G1RSetUpdatingPauseTimePercent=5 \
  -XX:SurvivorRatio=32 \
  -XX:+PerfDisableSharedMem \
  -XX:MaxTenuringThreshold=1 \
  -Dusing.aikars.flags=https://mcflags.emc.gs \
  -Daikars.new.flags=true \
  -jar /opt/minecraft/bin/paper.jar --nogui
Restart=on-failure
RestartSec=10
StandardInput=null
StandardOutput=journal
StandardError=journal
SyslogIdentifier=minecraft
# Allow up to 120 seconds for graceful shutdown (save-all + stop)
TimeoutStopSec=120
ExecStop=/usr/bin/kill -s SIGTERM $MAINPID

[Install]
WantedBy=multi-user.target
EOF
ok "minecraft.service written."

# ── 9. Enable and start the service ──────────────────────────────────────────
info "Reloading systemd and enabling minecraft.service..."
systemctl daemon-reload
systemctl enable --now minecraft.service
ok "minecraft.service enabled and started."

echo ""
echo "✓ Minecraft setup complete."
echo ""
echo "  Server directory : ${MC_HOME}"
echo "  World data       : ${MC_DATA}"
echo "  Paper JAR        : ${MC_JAR}"
echo ""
echo "  NEXT STEPS:"
echo "    Follow server logs:"
echo "      journalctl -u minecraft -f"
echo ""
echo "    Once the server has started, set up playit.gg tunneling (if needed):"
echo "      sudo bash ${REPO_ROOT}/bin/setup-playit.sh"
echo ""
echo "    Edit backups/restic.env then:"
echo "      sudo bash ${REPO_ROOT}/bin/setup-backups.sh"
echo ""
