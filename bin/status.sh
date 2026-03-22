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

# ── Minecraft (systemd service) ───────────────────────────────────────────────
hdr "Minecraft Server"
if [[ ! -f "/etc/systemd/system/minecraft.service" ]]; then
  warn "minecraft.service not installed."
  echo "     Run: sudo bash bin/setup-minecraft.sh"
elif systemctl is-active --quiet minecraft.service 2>/dev/null; then
  ok "minecraft.service is running."
  MC_LOG=$(journalctl -u minecraft -n 1 --no-pager --output=cat 2>/dev/null || echo "(no log yet)")
  echo "     Last log : ${MC_LOG}"
else
  fail "minecraft.service is NOT running."
  echo "     Run: sudo systemctl start minecraft.service"
fi

# ── Playit.gg agent ───────────────────────────────────────────────────────────
hdr "Playit.gg Agent"
if [[ ! -f "/etc/systemd/system/playit.service" ]]; then
  warn "playit.service not installed."
  echo "     If you are behind CGNAT, run: sudo bash bin/setup-playit.sh"
elif systemctl is-active --quiet playit.service 2>/dev/null; then
  ok "playit.service is running."
  journalctl -u playit -n 3 --no-pager --output=cat 2>/dev/null \
    | while IFS= read -r line; do echo "     ${line}"; done || true
else
  warn "playit.service is installed but NOT running."
  echo "     Run: sudo systemctl start playit.service"
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
