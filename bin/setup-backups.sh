#!/usr/bin/env bash
# setup-backups.sh — Install restic + systemd service/timer for Minecraft backups
# Idempotent: safe to run multiple times.
# Requires: backups/restic.env with RESTIC_REPOSITORY and RESTIC_PASSWORD set.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
BACKUPS_SRC="${REPO_ROOT}/backups"
ENV_FILE="${BACKUPS_SRC}/restic.env"
BACKUP_SCRIPT_DEST="/usr/local/bin/minecraft-backup.sh"
SERVICE_DEST="/etc/systemd/system/minecraft-backup.service"
TIMER_DEST="/etc/systemd/system/minecraft-backup.timer"

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
echo "  setup-backups.sh — Restic + systemd timer"
echo "============================================"
echo ""

# ── Load env file ─────────────────────────────────────────────────────────────
if [[ ! -f "${ENV_FILE}" ]]; then
  err "Missing env file: ${ENV_FILE}"
  err "Copy backups/restic.env.example to backups/restic.env and fill in your credentials."
  exit 1
fi

# shellcheck source=/dev/null
source "${ENV_FILE}"

if [[ -z "${RESTIC_REPOSITORY:-}" || "${RESTIC_REPOSITORY}" == "CHANGE_ME"* ]]; then
  err "RESTIC_REPOSITORY is not set or still has the placeholder value."
  err "Edit ${ENV_FILE}."
  exit 1
fi

if [[ -z "${RESTIC_PASSWORD:-}" || "${RESTIC_PASSWORD}" == "CHANGE_ME"* ]]; then
  err "RESTIC_PASSWORD is not set or still has the placeholder value."
  err "Edit ${ENV_FILE}."
  exit 1
fi

# ── Install restic ────────────────────────────────────────────────────────────
if ! command -v restic &>/dev/null; then
  info "Installing restic..."
  apt-get install -y -qq restic
  ok "restic installed."
else
  RESTIC_VER=$(restic version | head -1)
  ok "restic already installed: ${RESTIC_VER}"
fi

# ── Self-update restic (apt version may be older) ─────────────────────────────
info "Updating restic binary to latest..."
restic self-update 2>/dev/null || true

# ── Install the env file to a system location (readable only by root) ─────────
SYSTEM_ENV="/etc/restic/restic.env"
mkdir -p /etc/restic
if [[ ! -f "${SYSTEM_ENV}" ]]; then
  info "Installing restic env to ${SYSTEM_ENV}..."
  cp "${ENV_FILE}" "${SYSTEM_ENV}"
  chmod 600 "${SYSTEM_ENV}"
  ok "Env file installed."
else
  warn "Env file already exists at ${SYSTEM_ENV}. Not overwriting."
  warn "To update credentials, edit ${SYSTEM_ENV} directly."
fi

# ── Initialize the restic repository (idempotent) ─────────────────────────────
info "Initializing restic repository (safe to run on existing repo)..."
restic --password-file <(grep '^RESTIC_PASSWORD=' "${SYSTEM_ENV}" | cut -d= -f2-) \
       -r "${RESTIC_REPOSITORY}" init 2>&1 \
  | grep -v "already initialized" || true
ok "Restic repository ready."

# ── Install backup script ──────────────────────────────────────────────────────
info "Installing backup script to ${BACKUP_SCRIPT_DEST}..."
cp -f "${BACKUPS_SRC}/minecraft-backup.sh" "${BACKUP_SCRIPT_DEST}"
chmod 755 "${BACKUP_SCRIPT_DEST}"
ok "Backup script installed."

# ── Install systemd service and timer ────────────────────────────────────────
info "Installing systemd units..."
cp -f "${BACKUPS_SRC}/minecraft-backup.service" "${SERVICE_DEST}"
cp -f "${BACKUPS_SRC}/minecraft-backup.timer"   "${TIMER_DEST}"
ok "Systemd units installed."

# ── Reload systemd and enable timer ──────────────────────────────────────────
info "Enabling minecraft-backup.timer..."
systemctl daemon-reload
systemctl enable --now minecraft-backup.timer
ok "Backup timer enabled."

# ── Show timer status ─────────────────────────────────────────────────────────
echo ""
systemctl status minecraft-backup.timer --no-pager || true
echo ""
echo "✓ Backup setup complete."
echo ""
echo "  Repository  : ${RESTIC_REPOSITORY}"
echo "  Schedule    : hourly (minecraft-backup.timer)"
echo "  Retention   :"
echo "    --keep-hourly 24  --keep-daily 7  --keep-weekly 12"
echo "    --keep-monthly 6  --keep-yearly 5"
echo ""
echo "  Useful commands:"
echo "    sudo systemctl status minecraft-backup.timer"
echo "    sudo systemctl start  minecraft-backup.service   # run now"
echo "    sudo restic -r \${RESTIC_REPOSITORY} snapshots"
echo ""
echo "  See backups/README.md for restore instructions."
echo ""
