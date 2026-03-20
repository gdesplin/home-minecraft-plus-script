# Home Minecraft Plus Script

Idempotent bootstrap for a headless **Ubuntu 24.04 LTS** mini-PC that runs:

- A **Paper Minecraft server** in Docker (`itzg/minecraft-server`, Java 21, 4 GB RAM, ~10 players)
- A **Kamal-ready Docker host** for Rails apps
- **DuckDNS** dynamic-DNS updater (systemd service + timer)
- **Restic backups** of the Minecraft world (hourly systemd timer, configurable retention)
- Security basics: **UFW** firewall and **fail2ban** for SSH

---

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Initial Server Setup](#initial-server-setup)
3. [Clone This Repo](#clone-this-repo)
4. [Running the Setup Scripts](#running-the-setup-scripts)
5. [Router Port Forwarding](#router-port-forwarding)
6. [DuckDNS Setup](#duckdns-setup)
7. [Starting Minecraft](#starting-minecraft)
8. [Checking Status](#checking-status)
9. [Backups and Restore](#backups-and-restore)
10. [Kamal Notes](#kamal-notes)
11. [Security Hardening](#security-hardening)

---

## Prerequisites

| Requirement | Notes |
|-------------|-------|
| Ubuntu 24.04 LTS Server (headless) | Minimal install recommended |
| A non-root user with `sudo` | Created during install (e.g. `minecraft`) |
| SSH key auth configured | See below |
| 8+ GB RAM | 4 GB reserved for Minecraft |
| SSD storage | Strongly recommended |
| Internet access | For packages, Docker images, DuckDNS |

### Install Ubuntu Server

1. Download the Ubuntu 24.04 LTS Server ISO and flash to USB.
2. Boot the mini-PC from USB; choose **"Ubuntu Server (minimized)"** or the standard server install.
3. During install, create a user (e.g. `minecraft`) and enable OpenSSH.
4. Finish install and reboot.

### Set Up SSH Keys (recommended)

From your laptop:

```bash
# Generate a key if you don't have one
ssh-keygen -t ed25519 -C "your@email.com"

# Copy to the server
ssh-copy-id minecraft@<server-lan-ip>
```

After confirming key login works, you can disable password auth (see [Security Hardening](#security-hardening)).

---

## Initial Server Setup

```bash
# Log in to the server
ssh minecraft@<server-lan-ip>

# Update system
sudo apt update && sudo apt upgrade -y
sudo reboot
```

---

## Clone This Repo

```bash
sudo apt install -y git
git clone https://github.com/gdesplin/home-minecraft-plus-script.git ~/homelab
cd ~/homelab
```

---

## Running the Setup Scripts

Run scripts in order. Each is **idempotent** — safe to re-run if something changes.

```bash
# 1. Host basics (packages, locale, timezone)
sudo bash bin/setup-host.sh

# 2. Docker CE + Compose plugin
sudo bash bin/setup-docker.sh

# 3. UFW firewall
sudo bash bin/setup-firewall.sh

# 4. fail2ban for SSH
sudo bash bin/setup-fail2ban.sh

# 5. DuckDNS dynamic DNS (configure duckdns/.env first — see below)
sudo bash bin/setup-duckdns.sh

# 6. Minecraft server (configure minecraft/.env first — see below)
sudo bash bin/setup-minecraft.sh

# 7. Restic backups (configure backups/restic.env first — see below)
sudo bash bin/setup-backups.sh
```

### Configure Environment Files

Before running steps 5–7, copy and edit the example env files:

```bash
# DuckDNS
cp duckdns/.env.example duckdns/.env
nano duckdns/.env         # fill in DUCKDNS_TOKEN and DUCKDNS_SUBDOMAIN

# Minecraft (optional overrides; defaults are sensible)
cp minecraft/.env.example minecraft/.env
nano minecraft/.env       # set EULA=TRUE (required), optionally MC_VERSION

# Restic backups
cp backups/restic.env.example backups/restic.env
nano backups/restic.env   # fill in RESTIC_REPOSITORY and RESTIC_PASSWORD
```

---

## Router Port Forwarding

Minecraft clients connect directly to your public IP (or DuckDNS hostname) on **TCP port 25565**.

### Steps

1. **Give the server a stable LAN IP:**
   - Preferred: Set a **DHCP reservation** in your router using the server's MAC address.
   - Alternative: Configure a static IP in Ubuntu (`/etc/netplan/`).

2. **Log in to your router admin panel** (often `192.168.1.1` or `192.168.0.1`).

3. **Create a port-forward rule:**
   - Protocol: **TCP**
   - External port: **25565**
   - Internal IP: your server's LAN IP (e.g. `192.168.1.50`)
   - Internal port: **25565**

4. **Test from outside your LAN:**
   - Use [mcsrvstat.us](https://mcsrvstat.us/) to check if your server is reachable.
   - Or ask a friend to connect to `<your-duckdns-subdomain>.duckdns.org`.

### CGNAT / Double-NAT

If port forwarding doesn't work, your ISP may be using **Carrier-Grade NAT (CGNAT)**. Signs:
- Your router's WAN IP is in `100.64.0.0/10` or `10.x.x.x`
- `curl ifconfig.me` on the server differs from your router's WAN IP

In that case, contact your ISP and request a **public IP address**, or consider a Tailscale relay.

---

## DuckDNS Setup

1. Go to [duckdns.org](https://www.duckdns.org/) and sign in.
2. Create a subdomain (e.g. `myhomemc`).
3. Copy your **token** from the dashboard.
4. Fill in `duckdns/.env`:

```env
DUCKDNS_SUBDOMAIN=myhomemc
DUCKDNS_TOKEN=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
```

5. Run `sudo bash bin/setup-duckdns.sh` — this installs a systemd timer that updates DuckDNS every 5 minutes.

Players connect to: `myhomemc.duckdns.org:25565`
(Port 25565 is the Minecraft default, so if you use the default port, players can omit `:25565`.)

---

## Starting Minecraft

```bash
cd /opt/minecraft
sudo docker compose up -d

# Follow logs
sudo docker compose logs -f
```

The first start downloads the Paper server jar — this may take a minute or two.

> **EULA:** You must set `EULA=TRUE` in `minecraft/.env` (or `/opt/minecraft/.env`). By setting
> this you agree to the [Minecraft EULA](https://aka.ms/MinecraftEULA).

### Manage the Server

```bash
# Send a console command via RCON
sudo docker exec mc rcon-cli "list"

# Attach to the console (Ctrl+P, Ctrl+Q to detach)
sudo docker attach mc

# Stop the server cleanly
cd /opt/minecraft && sudo docker compose stop

# Restart
cd /opt/minecraft && sudo docker compose restart
```

### Op a Player

```bash
sudo docker exec mc rcon-cli "op YourUsername"
```

---

## Checking Status

```bash
sudo bash bin/status.sh
```

This shows:
- Docker service status
- Minecraft container status and online players
- DuckDNS timer status
- Backup timer status and last backup time
- UFW status
- Disk usage

---

## Backups and Restore

See [`backups/README.md`](backups/README.md) for full documentation.

**Quick restore:**

```bash
# List snapshots
sudo restic -r <RESTIC_REPOSITORY> snapshots

# Restore latest snapshot
cd /opt/minecraft && sudo docker compose stop
sudo restic -r <RESTIC_REPOSITORY> restore latest --target /
cd /opt/minecraft && sudo docker compose start
```

---

## Kamal Notes

This host is pre-configured to run **Kamal** deployments (Rails apps in Docker containers). Kamal manages rolling deploys via SSH from your dev machine.

### Prerequisites on This Host

- Docker CE installed (`setup-docker.sh` handles this)
- Your deploy user added to the `docker` group (`setup-docker.sh` handles this)
- SSH key from your dev machine authorized on this host

### From Your Dev Machine

```bash
# Install Kamal
gem install kamal

# In your Rails app directory
kamal init
# Edit config/deploy.yml with this server's IP/hostname
kamal setup
kamal deploy
```

### Port Considerations

- Rails apps typically run on ports **80/443** (via a reverse proxy like Traefik, which Kamal includes).
- `setup-firewall.sh` opens ports 80 and 443 by default.
- For internal-only apps, keep those ports closed and use Tailscale or SSH tunneling.

### Coexistence with Minecraft

Kamal's Traefik proxy binds ports 80 and 443. Minecraft uses 25565. They do not conflict.

---

## Security Hardening

### Restrict SSH to LAN Only

Edit `/etc/ufw/applications.d/openssh-server` or simply update the UFW rule:

```bash
# Remove the broad SSH rule
sudo ufw delete allow OpenSSH

# Allow SSH only from your LAN subnet (adjust to match your network)
sudo ufw allow from 192.168.1.0/24 to any port 22 proto tcp comment 'SSH LAN only'
sudo ufw reload
```

### Disable SSH Password Authentication

After confirming key-based login works:

```bash
sudo sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
sudo systemctl restart sshd
```

### fail2ban

`setup-fail2ban.sh` installs fail2ban with the systemd backend to protect SSH. Default: 5 failed attempts → 10 minute ban.

Check bans:

```bash
sudo fail2ban-client status sshd
```

### Unattended Upgrades

```bash
sudo apt install -y unattended-upgrades
sudo dpkg-reconfigure -plow unattended-upgrades
```

---

## Directory Layout

```
.
├── README.md               # This file
├── bin/
│   ├── setup-host.sh       # Base packages, locale, timezone
│   ├── setup-docker.sh     # Docker CE + Compose plugin
│   ├── setup-firewall.sh   # UFW rules
│   ├── setup-fail2ban.sh   # fail2ban (sshd)
│   ├── setup-duckdns.sh    # DuckDNS systemd service + timer
│   ├── setup-minecraft.sh  # Minecraft compose stack
│   ├── setup-backups.sh    # Restic + systemd backup timer
│   └── status.sh           # Health dashboard
├── minecraft/
│   ├── compose.yml         # Docker Compose for Minecraft
│   └── .env.example        # Minecraft environment template
├── duckdns/
│   └── .env.example        # DuckDNS credentials template
└── backups/
    ├── restic.env.example  # Restic credentials template
    ├── minecraft-backup.sh # Backup script (rcon safe-save + restic)
    ├── minecraft-backup.service
    ├── minecraft-backup.timer
    └── README.md           # Backup + restore docs
```
