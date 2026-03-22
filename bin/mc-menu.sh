#!/usr/bin/env bash
# mc-menu.sh — Interactive management menu for the Minecraft homelab
# Inspired by yash1648/mc-server — adapted for the full homelab stack.
#
# Usage: bash bin/mc-menu.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MC_DIR="/opt/minecraft"

# ── Colours ───────────────────────────────────────────────────────────────────
RESET='\033[0m'
BOLD='\033[1m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
RED='\033[0;31m'
DIM='\033[2m'

# ── Helpers ───────────────────────────────────────────────────────────────────
mc_running() {
  docker ps --filter "name=^mc$" --filter "status=running" \
    --format "{{.Names}}" 2>/dev/null | grep -q "^mc$"
}

playit_running() {
  systemctl is-active --quiet playit 2>/dev/null
}

status_badge() {
  if mc_running; then
    printf "${GREEN}${BOLD}● RUNNING${RESET}"
  else
    printf "${RED}${BOLD}○ STOPPED${RESET}"
  fi
}

playit_badge() {
  if playit_running; then
    printf "${GREEN}${BOLD}● RUNNING${RESET}"
  else
    printf "${YELLOW}${BOLD}○ OFFLINE${RESET}"
  fi
}

# ── Menu display ──────────────────────────────────────────────────────────────
show_menu() {
  clear
  printf "${PURPLE}${BOLD}"
  echo "╔══════════════════════════════════════════════════════════╗"
  echo "║        🎮  Minecraft Homelab Management Menu             ║"
  echo "╚══════════════════════════════════════════════════════════╝"
  printf "${RESET}\n"

  printf "  Minecraft : $(status_badge)   Playit : $(playit_badge)\n"
  echo ""

  printf "${CYAN}${BOLD}  SERVER CONTROL${RESET}\n"
  echo "  ──────────────────────────────────────────────────────────"
  printf "  ${BOLD}1${RESET})  Start server\n"
  printf "  ${BOLD}2${RESET})  Stop server  ${DIM}(graceful save-all + stop)${RESET}\n"
  printf "  ${BOLD}3${RESET})  Restart server\n"
  echo ""

  printf "${CYAN}${BOLD}  MONITORING${RESET}\n"
  echo "  ──────────────────────────────────────────────────────────"
  printf "  ${BOLD}4${RESET})  Follow live logs  ${DIM}(Ctrl+C to exit)${RESET}\n"
  printf "  ${BOLD}5${RESET})  Full status dashboard\n"
  echo ""

  printf "${CYAN}${BOLD}  ADMINISTRATION${RESET}\n"
  echo "  ──────────────────────────────────────────────────────────"
  printf "  ${BOLD}6${RESET})  Open admin console  ${DIM}(rcon-cli)${RESET}\n"
  printf "  ${BOLD}7${RESET})  Add / install a plugin\n"
  echo ""

  printf "${CYAN}${BOLD}  TUNNEL (Playit.gg)${RESET}\n"
  echo "  ──────────────────────────────────────────────────────────"
  printf "  ${BOLD}8${RESET})  Start Playit tunnel\n"
  printf "  ${BOLD}9${RESET})  Stop Playit tunnel\n"
  printf "  ${BOLD}10${RESET}) Restart Playit tunnel\n"
  printf "  ${BOLD}11${RESET}) View Playit logs  ${DIM}(last 30 lines)${RESET}\n"
  printf "  ${BOLD}12${RESET}) Reset Playit  ${DIM}(full wipe + reinstall)${RESET}\n"
  echo ""

  printf "${CYAN}${BOLD}  MAINTENANCE${RESET}\n"
  echo "  ──────────────────────────────────────────────────────────"
  printf "  ${BOLD}13${RESET}) Run manual backup  ${DIM}(restic snapshot)${RESET}\n"
  echo ""

  printf "${CYAN}${BOLD}  SYSTEM${RESET}\n"
  echo "  ──────────────────────────────────────────────────────────"
  printf "   ${BOLD}0${RESET}) Exit menu\n"
  echo ""
}

# ── Pause helper ──────────────────────────────────────────────────────────────
pause() {
  echo ""
  read -r -p "  Press Enter to return to the menu..."
}

# ── Option dispatcher ─────────────────────────────────────────────────────────
handle_choice() {
  local choice="$1"
  case "${choice}" in

    # ── Server control ────────────────────────────────────────────────────────
    1)
      echo ""
      bash "${SCRIPT_DIR}/mc-start.sh"
      pause
      ;;
    2)
      echo ""
      bash "${SCRIPT_DIR}/mc-stop.sh"
      pause
      ;;
    3)
      echo ""
      bash "${SCRIPT_DIR}/mc-restart.sh"
      pause
      ;;

    # ── Monitoring ────────────────────────────────────────────────────────────
    4)
      echo ""
      bash "${SCRIPT_DIR}/mc-logs.sh" || true
      ;;
    5)
      echo ""
      bash "${SCRIPT_DIR}/status.sh" || true
      pause
      ;;

    # ── Administration ────────────────────────────────────────────────────────
    6)
      echo ""
      bash "${SCRIPT_DIR}/mc-console.sh" || true
      ;;
    7)
      echo ""
      read -r -p "  Plugin file path or download URL: " PLUGIN_INPUT
      if [[ -n "${PLUGIN_INPUT}" ]]; then
        bash "${SCRIPT_DIR}/mc-add-plugin.sh" "${PLUGIN_INPUT}" || true
      else
        echo "  Cancelled."
      fi
      pause
      ;;

    # ── Playit.gg tunnel ──────────────────────────────────────────────────────
    8)
      echo ""
      sudo systemctl start playit && \
        printf "  \033[32m✓\033[0m  Playit tunnel started.\n" || \
        printf "  \033[31m✗\033[0m  Failed to start Playit.\n"
      pause
      ;;
    9)
      echo ""
      sudo systemctl stop playit && \
        printf "  \033[32m✓\033[0m  Playit tunnel stopped.\n" || \
        printf "  \033[31m✗\033[0m  Failed to stop Playit.\n"
      pause
      ;;
    10)
      echo ""
      sudo systemctl restart playit && \
        printf "  \033[32m✓\033[0m  Playit tunnel restarted.\n" || \
        printf "  \033[31m✗\033[0m  Failed to restart Playit.\n"
      pause
      ;;
    11)
      echo ""
      sudo journalctl -u playit -n 30 --no-pager || true
      pause
      ;;
    12)
      echo ""
      printf "  \033[33m⚠\033[0m  This will wipe ALL Playit state and reinstall.\n"
      read -r -p "  Continue? [y/N] " CONFIRM
      if [[ "${CONFIRM,,}" == "y" ]]; then
        sudo bash "${SCRIPT_DIR}/reset-playit.sh" || true
      else
        echo "  Cancelled."
      fi
      pause
      ;;

    # ── Maintenance ───────────────────────────────────────────────────────────
    13)
      echo ""
      sudo systemctl start minecraft-backup.service && \
        printf "  \033[32m✓\033[0m  Backup started. Follow: sudo journalctl -u minecraft-backup.service -f\n" || \
        printf "  \033[31m✗\033[0m  Backup service failed to start.\n"
      pause
      ;;

    # ── Exit ──────────────────────────────────────────────────────────────────
    0)
      echo ""
      echo "  Goodbye!"
      echo ""
      exit 0
      ;;

    *)
      echo ""
      printf "  \033[33m⚠\033[0m  Unknown option: ${choice}\n"
      pause
      ;;
  esac
}

# ── Main loop ─────────────────────────────────────────────────────────────────
while true; do
  show_menu
  printf "${GREEN}  Select option (0–13): ${RESET}"
  read -r CHOICE
  handle_choice "${CHOICE}"
done
