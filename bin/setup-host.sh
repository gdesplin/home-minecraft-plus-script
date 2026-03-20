#!/usr/bin/env bash
# setup-host.sh — Base system packages, locale, timezone
# Idempotent: safe to run multiple times.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

info()  { echo "  [INFO]  $*"; }
ok()    { echo "  [ OK ]  $*"; }
warn()  { echo "  [WARN]  $*"; }

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    echo "ERROR: Run this script with sudo or as root." >&2
    exit 1
  fi
}

require_root

echo ""
echo "============================================"
echo "  setup-host.sh — Ubuntu 24.04 base setup"
echo "============================================"
echo ""

# ── Update package lists ──────────────────────────────────────────────────────
info "Updating package lists..."
apt-get update -qq

# ── Upgrade installed packages ────────────────────────────────────────────────
info "Upgrading installed packages (non-interactive)..."
DEBIAN_FRONTEND=noninteractive apt-get upgrade -y -qq

# ── Install base packages ─────────────────────────────────────────────────────
BASE_PACKAGES=(
  curl
  wget
  git
  unzip
  htop
  vim
  net-tools
  dnsutils
  ca-certificates
  gnupg
  lsb-release
  software-properties-common
  apt-transport-https
  jq
  rsync
  cron
  ufw
  fail2ban
  ntp
  apparmor
  apparmor-utils
)

info "Installing base packages..."
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "${BASE_PACKAGES[@]}"
ok "Base packages installed."

# ── Set locale ────────────────────────────────────────────────────────────────
LOCALE="en_US.UTF-8"
if ! locale -a 2>/dev/null | grep -q "en_US.utf8"; then
  info "Generating locale ${LOCALE}..."
  locale-gen "${LOCALE}"
fi
update-locale LANG="${LOCALE}" LANGUAGE="${LOCALE}" LC_ALL="${LOCALE}"
ok "Locale set to ${LOCALE}."

# ── Set timezone ──────────────────────────────────────────────────────────────
TIMEZONE="${HOMELAB_TIMEZONE:-America/New_York}"
info "Setting timezone to ${TIMEZONE}..."
timedatectl set-timezone "${TIMEZONE}" || ln -snf "/usr/share/zoneinfo/${TIMEZONE}" /etc/localtime
ok "Timezone set to ${TIMEZONE}."

# ── Enable NTP ────────────────────────────────────────────────────────────────
info "Enabling NTP time sync..."
timedatectl set-ntp true || true
ok "NTP enabled."

# ── Enable unattended upgrades for security patches ───────────────────────────
if ! dpkg -l | grep -q unattended-upgrades; then
  info "Installing unattended-upgrades..."
  DEBIAN_FRONTEND=noninteractive apt-get install -y -qq unattended-upgrades
fi
if [[ ! -f /etc/apt/apt.conf.d/20auto-upgrades ]]; then
  info "Enabling automatic security upgrades..."
  cat > /etc/apt/apt.conf.d/20auto-upgrades <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
EOF
fi
ok "Unattended-upgrades configured."

# ── Kernel parameters for Docker / performance ────────────────────────────────
SYSCTL_CONF="/etc/sysctl.d/99-homelab.conf"
if [[ ! -f "${SYSCTL_CONF}" ]]; then
  info "Applying sysctl tuning for Docker/networking..."
  cat > "${SYSCTL_CONF}" <<'EOF'
# Allow Docker bridge networking
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
# Improve TCP performance
net.core.somaxconn = 4096
net.ipv4.tcp_fastopen = 3
# Disable IPv6 if not needed (comment out if you use IPv6)
# net.ipv6.conf.all.disable_ipv6 = 1
EOF
  sysctl --system -q
  ok "sysctl tuning applied."
else
  ok "sysctl config already present, skipping."
fi

echo ""
echo "✓ Host setup complete."
echo ""
echo "  NEXT STEPS:"
echo "    sudo bash ${REPO_ROOT}/bin/setup-docker.sh"
echo ""
