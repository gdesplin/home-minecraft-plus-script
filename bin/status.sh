#!/usr/bin/env bash
# status.sh — Health-check dashboard for the homelab
# Shows: Docker, Minecraft, DuckDNS, backups, UFW, disk usage
set -euo pipefail

SEP="──────────────────────────────────────────────"
MC_DIR="/opt/minecraft"
RESTIC_ENV="/etc/restic/restic.env"
DUCKDNS_LOG="/var/log/duckdns.log"

ok()   { printf "  \033[32m✓\033[0m  %s\n" "$*"; }
warn() { printf "  \033[33m⚠\033[0m  %s\n" "$*"; }
fail() { printf "  \033[31m✗\033[0m  %s\n" "$*"; }
hdr()  { echo ""; echo "${SEP}"; echo "  $*"; echo "${SEP}"; }

# ── Docker ────────────────────────────────────────────────────────────────────
hdr "Docker"
if systemctl is-active --quiet docker 2>/dev/null; then
  ok "Docker service is running."
  DOCKER_VER=$(docker --version 2>/dev/null || echo "unknown")
  echo "     Version : ${DOCKER_VER}"
else
  fail "Docker service is NOT running."
  echo "     Run: sudo systemctl start docker"
fi

# ── Minecraft container ───────────────────────────────────────────────────────
hdr "Minecraft Server"
if [[ -f "${MC_DIR}/compose.yml" ]]; then
  MC_STATUS=$(docker compose -f "${MC_DIR}/compose.yml" ps --format json 2>/dev/null || echo "")
  if docker compose -f "${MC_DIR}/compose.yml" ps 2>/dev/null | grep -q "running\|Up"; then
    ok "Minecraft container is running."
    # Try RCON to get player count
    if docker exec mc rcon-cli "list" &>/dev/null 2>&1; then
      PLAYER_LIST=$(docker exec mc rcon-cli "list" 2>/dev/null || echo "RCON unavailable")
      echo "     ${PLAYER_LIST}"
    else
      echo "     RCON: not available (container may still be starting)"
    fi
  else
    fail "Minecraft container is NOT running."
    echo "     Run: cd ${MC_DIR} && sudo docker compose up -d"
  fi
else
  warn "Minecraft not set up yet (${MC_DIR}/compose.yml not found)."
  echo "     Run: sudo bash bin/setup-minecraft.sh"
fi

# ── Playit.gg tunnel ─────────────────────────────────────────────────────────
hdr "Playit.gg Tunnel"
if systemctl is-active --quiet playit 2>/dev/null; then
  ok "Playit service is running."
  PLAYIT_BIN="/opt/playit/playit"
  if [[ -x "${PLAYIT_BIN}" ]]; then
    PLAYIT_VER=$("${PLAYIT_BIN}" --version 2>/dev/null || echo "unknown")
    echo "     Version  : ${PLAYIT_VER}"
  fi
  # Show the active ExecStart so the user can verify binary path and flags
  EXEC_START=$(systemctl show playit -p ExecStart --value 2>/dev/null \
    | sed 's/^.*path=//;s/ ;.*$//' || echo "unknown")
  echo "     ExecStart: ${EXEC_START}"
  # Quick loopback reachability check for the Minecraft port
  if command -v nc &>/dev/null; then
    if nc -z -w2 127.0.0.1 25565 2>/dev/null; then
      ok "127.0.0.1:25565 is reachable from the host (Docker port is published)."
    else
      warn "127.0.0.1:25565 is NOT reachable — Minecraft may not be running or the port is not published."
      echo "     Check: sudo docker compose -f /opt/minecraft/compose.yml ps"
      echo "     Check: sudo docker ps --format 'table {{.Names}}\\t{{.Ports}}'"
    fi
  fi
elif systemctl list-unit-files playit.service &>/dev/null 2>&1 \
    && systemctl list-unit-files playit.service | grep -q playit; then
  warn "Playit service is installed but NOT running."
  echo "     Run: sudo systemctl start playit"
  echo "     Check: sudo systemctl status playit"
  echo "     Logs: sudo journalctl -u playit -n 30"
else
  warn "Playit service not found (not installed or not in use)."
  echo "     If you are behind CGNAT, run: sudo bash bin/setup-playit.sh"
fi

# ── DuckDNS ───────────────────────────────────────────────────────────────────
hdr "DuckDNS"
if systemctl is-active --quiet duckdns.timer 2>/dev/null; then
  ok "DuckDNS timer is active."
  NEXT=$(systemctl show duckdns.timer -p NextElapseUSecRealtime --value 2>/dev/null || echo "unknown")
  LAST=$(systemctl show duckdns.timer -p LastTriggerUSec --value 2>/dev/null || echo "unknown")
  echo "     Last trigger : ${LAST}"
  echo "     Next trigger : ${NEXT}"
  if [[ -f "${DUCKDNS_LOG}" ]]; then
    LAST_LOG=$(tail -1 "${DUCKDNS_LOG}" 2>/dev/null || echo "(empty)")
    echo "     Last update  : ${LAST_LOG}"
  fi
else
  warn "DuckDNS timer is NOT active."
  echo "     Run: sudo bash bin/setup-duckdns.sh"
fi

# ── Backups ───────────────────────────────────────────────────────────────────
hdr "Backups (Restic)"
if systemctl is-active --quiet minecraft-backup.timer 2>/dev/null; then
  ok "Backup timer is active."
  LAST_BACKUP=$(systemctl show minecraft-backup.service -p ExecMainExitTimestamp --value 2>/dev/null || echo "unknown")
  echo "     Last run : ${LAST_BACKUP}"
  if [[ -f "${RESTIC_ENV}" ]]; then
    # shellcheck source=/dev/null
    source "${RESTIC_ENV}" 2>/dev/null || true
    if [[ -n "${RESTIC_REPOSITORY:-}" ]]; then
      SNAPSHOT_COUNT=$(restic -r "${RESTIC_REPOSITORY}" snapshots --no-lock \
        2>/dev/null | grep -c "^[0-9a-f]" || echo "?")
      echo "     Snapshots: ${SNAPSHOT_COUNT}"
    fi
  fi
else
  warn "Backup timer is NOT active."
  echo "     Run: sudo bash bin/setup-backups.sh"
fi

# ── fail2ban ──────────────────────────────────────────────────────────────────
hdr "fail2ban"
if systemctl is-active --quiet fail2ban 2>/dev/null; then
  ok "fail2ban is running."
  BAN_COUNT=$(fail2ban-client status sshd 2>/dev/null \
    | grep "Currently banned" | awk '{print $NF}' || echo "?")
  echo "     SSH currently banned IPs: ${BAN_COUNT}"
else
  warn "fail2ban is NOT running."
  echo "     Run: sudo bash bin/setup-fail2ban.sh"
fi

# ── UFW ───────────────────────────────────────────────────────────────────────
hdr "Firewall (UFW)"
UFW_STATUS=$(ufw status 2>/dev/null | head -1 || echo "UFW not available")
if echo "${UFW_STATUS}" | grep -qi "active"; then
  ok "UFW is active."
  ufw status 2>/dev/null | tail -n +3 | grep -v "^$" | while IFS= read -r line; do
    echo "     ${line}"
  done
else
  warn "UFW is NOT active."
  echo "     Run: sudo bash bin/setup-firewall.sh"
fi

# ── Disk usage ────────────────────────────────────────────────────────────────
hdr "Disk Usage"
df -h --output=source,size,used,avail,pcent,target 2>/dev/null \
  | grep -v "^tmpfs\|^udev\|^/dev/loop" \
  | while IFS= read -r line; do echo "  ${line}"; done

echo ""
echo "${SEP}"
echo "  Status check complete — $(date '+%Y-%m-%d %H:%M:%S')"
echo "${SEP}"
echo ""
