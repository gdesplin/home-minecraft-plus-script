#!/usr/bin/env bash
# minecraft-backup.sh — Safe restic backup of the Minecraft world
#
# Strategy:
#   1. Signal the Minecraft server to flush world data (via RCON if available)
#   2. Take a restic snapshot of /opt/minecraft/data
#   3. Re-enable auto-save
#   4. Prune old snapshots using the configured retention policy
#
# Installed to /usr/local/bin/minecraft-backup.sh by setup-backups.sh.
# Run by: minecraft-backup.service (triggered by minecraft-backup.timer)
set -euo pipefail

ENV_FILE="/etc/restic/restic.env"
MC_DATA_DIR="/opt/minecraft/data"
RCON_HOST="127.0.0.1"
RCON_PORT="25575"
RCON_PASS_FILE=""       # populated below from env

log()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')]  $*"; }
warn() { echo "[$(date '+%Y-%m-%d %H:%M:%S')]  WARN: $*" >&2; }
err()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')]  ERROR: $*" >&2; }

# ── Load restic env ───────────────────────────────────────────────────────────
if [[ ! -f "${ENV_FILE}" ]]; then
  err "Env file not found: ${ENV_FILE}. Run setup-backups.sh first."
  exit 1
fi

# shellcheck source=/dev/null
source "${ENV_FILE}"

: "${RESTIC_REPOSITORY:?RESTIC_REPOSITORY must be set in ${ENV_FILE}}"
: "${RESTIC_PASSWORD:?RESTIC_PASSWORD must be set in ${ENV_FILE}}"
export RESTIC_REPOSITORY RESTIC_PASSWORD

# Honour optional cloud provider credentials if set
[[ -n "${B2_ACCOUNT_ID:-}"        ]] && export B2_ACCOUNT_ID
[[ -n "${B2_ACCOUNT_KEY:-}"       ]] && export B2_ACCOUNT_KEY
[[ -n "${AWS_ACCESS_KEY_ID:-}"    ]] && export AWS_ACCESS_KEY_ID
[[ -n "${AWS_SECRET_ACCESS_KEY:-}" ]] && export AWS_SECRET_ACCESS_KEY

KEEP_HOURLY="${KEEP_HOURLY:-24}"
KEEP_DAILY="${KEEP_DAILY:-7}"
KEEP_WEEKLY="${KEEP_WEEKLY:-12}"
KEEP_MONTHLY="${KEEP_MONTHLY:-6}"
KEEP_YEARLY="${KEEP_YEARLY:-5}"

# ── Verify world data directory exists ───────────────────────────────────────
if [[ ! -d "${MC_DATA_DIR}" ]]; then
  err "Minecraft data directory not found: ${MC_DATA_DIR}"
  err "Is the server set up? Check /opt/minecraft."
  exit 1
fi

# ── RCON helper ───────────────────────────────────────────────────────────────
RCON_AVAILABLE=false

rcon_cmd() {
  # Use docker exec + rcon-cli if the container is running
  if docker exec mc rcon-cli --host "${RCON_HOST}" \
       --port "${RCON_PORT}" \
       --password "${RCON_PASSWORD:-}" \
       "$@" &>/dev/null 2>&1; then
    return 0
  fi
  return 1
}

if docker ps --filter "name=^mc$" --filter "status=running" \
     --format "{{.Names}}" 2>/dev/null | grep -q "^mc$"; then
  if docker exec mc rcon-cli \
       --host "${RCON_HOST}" \
       --port "${RCON_PORT}" \
       --password "${RCON_PASSWORD:-}" \
       "list" &>/dev/null 2>&1; then
    RCON_AVAILABLE=true
    log "RCON connection established."
  else
    warn "Minecraft container is running but RCON is not available."
    warn "Backup will proceed without save-off (data may be mid-write)."
  fi
else
  warn "Minecraft container is not running. Backing up static data."
fi

# ── Pause world saves ─────────────────────────────────────────────────────────
if [[ "${RCON_AVAILABLE}" == "true" ]]; then
  log "Disabling auto-save (save-off)..."
  docker exec mc rcon-cli \
    --host "${RCON_HOST}" \
    --port "${RCON_PORT}" \
    --password "${RCON_PASSWORD:-}" \
    "save-off" || warn "save-off failed — continuing anyway."

  log "Flushing world to disk (save-all flush)..."
  docker exec mc rcon-cli \
    --host "${RCON_HOST}" \
    --port "${RCON_PORT}" \
    --password "${RCON_PASSWORD:-}" \
    "save-all flush" || warn "save-all flush failed — continuing anyway."

  # Brief pause to let the flush complete
  sleep 3
fi

# ── Take restic snapshot ──────────────────────────────────────────────────────
log "Starting restic backup of ${MC_DATA_DIR}..."
restic backup \
  --tag minecraft \
  --tag "$(hostname)" \
  --exclude "${MC_DATA_DIR}/logs" \
  --exclude "${MC_DATA_DIR}/crash-reports" \
  "${MC_DATA_DIR}"

log "Restic backup completed."

# ── Re-enable world saves ─────────────────────────────────────────────────────
if [[ "${RCON_AVAILABLE}" == "true" ]]; then
  log "Re-enabling auto-save (save-on)..."
  docker exec mc rcon-cli \
    --host "${RCON_HOST}" \
    --port "${RCON_PORT}" \
    --password "${RCON_PASSWORD:-}" \
    "save-on" || warn "save-on failed — you may need to run it manually."
fi

# ── Prune old snapshots ───────────────────────────────────────────────────────
log "Pruning old snapshots with retention policy..."
restic forget \
  --tag minecraft \
  --keep-hourly  "${KEEP_HOURLY}" \
  --keep-daily   "${KEEP_DAILY}" \
  --keep-weekly  "${KEEP_WEEKLY}" \
  --keep-monthly "${KEEP_MONTHLY}" \
  --keep-yearly  "${KEEP_YEARLY}" \
  --prune

log "Pruning complete."

# ── Verify repository integrity (every 10 runs via mod on minute) ─────────────
MINUTE=$(date '+%M')
if (( 10#${MINUTE} % 10 == 0 )); then
  log "Running restic check (--read-data-subset=1%)..."
  restic check --read-data-subset=1% || warn "restic check reported issues — investigate!"
fi

log "Backup job finished successfully."
