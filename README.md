# Home Minecraft Plus Script

Idempotent bootstrap for a headless **Ubuntu 24.04 LTS** mini-PC that runs:

- A **Paper Minecraft server** running bare-metal (no Docker) under a dedicated `minecraft` system user, managed by `minecraft.service` (systemd)
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
5. [Network Setup Decision Tree](#network-setup-decision-tree)
6. [Router Port Forwarding](#router-port-forwarding)
7. [CGNAT / Playit.gg Tunnel](#cgnat--playitgg-tunnel)
8. [DuckDNS Setup](#duckdns-setup)
9. [Starting Minecraft](#starting-minecraft)
10. [Bedrock Edition Support (Optional)](#bedrock-edition-support-optional)
11. [Checking Status](#checking-status)
12. [Backups and Restore](#backups-and-restore)
13. [Kamal Notes](#kamal-notes)
14. [Security Hardening](#security-hardening)

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

# 2. Docker CE + Compose plugin (still needed for Kamal)
sudo bash bin/setup-docker.sh

# 3. UFW firewall
sudo bash bin/setup-firewall.sh

# 4. fail2ban for SSH
sudo bash bin/setup-fail2ban.sh

# 5. DuckDNS dynamic DNS (configure duckdns/.env first — see below)
#    Skip this step if you are using Playit.gg (see CGNAT section)
sudo bash bin/setup-duckdns.sh

# 6. Minecraft server (bare-metal, no Docker required)
sudo bash bin/setup-minecraft.sh

# 7. Restic backups (configure backups/restic.env first — see below)
sudo bash bin/setup-backups.sh

# Optional: Playit.gg agent (required when behind CGNAT — see below)
sudo bash bin/setup-playit.sh
```

### Configure Environment Files

Before running steps 5 and 7, copy and edit the example env files:

```bash
# DuckDNS
cp duckdns/.env.example duckdns/.env
nano duckdns/.env         # fill in DUCKDNS_TOKEN and DUCKDNS_SUBDOMAIN

# Restic backups
cp backups/restic.env.example backups/restic.env
nano backups/restic.env   # fill in RESTIC_REPOSITORY and RESTIC_PASSWORD
```

The Minecraft server no longer uses a `.env` file. All server settings are in
`/opt/minecraft/data/server.properties` (written automatically on first run by
`setup-minecraft.sh`). Edit that file directly and restart the service:

```bash
sudo nano /opt/minecraft/data/server.properties
sudo systemctl restart minecraft.service
```

---

## Router Port Forwarding

Minecraft clients connect directly to your public IP (or DuckDNS hostname). You need to forward **two ports** if you want both Java and Bedrock players to connect:

| Edition | Protocol | Port |
|---------|----------|------|
| Java | TCP | 25565 |
| Bedrock (Geyser) | UDP | 19132 |

### Steps

1. **Give the server a stable LAN IP:**
   - Preferred: Set a **DHCP reservation** in your router using the server's MAC address.
   - Alternative: Configure a static IP in Ubuntu (`/etc/netplan/`).

2. **Log in to your router admin panel** (often `192.168.1.1` or `192.168.0.1`).

3. **Create port-forward rules:**

   **Java Edition (required):**
   - Protocol: **TCP**
   - External port: **25565**
   - Internal IP: your server's LAN IP (e.g. `192.168.1.50`)
   - Internal port: **25565**

   **Bedrock Edition / Geyser (optional — skip if you don't need Bedrock crossplay):**
   - Protocol: **UDP**
   - External port: **19132**
   - Internal IP: your server's LAN IP (e.g. `192.168.1.50`)
   - Internal port: **19132**

4. **Test from outside your LAN:**
   - Use [mcsrvstat.us](https://mcsrvstat.us/) to check if your server is reachable.
   - Or ask a friend to connect to `<your-duckdns-subdomain>.duckdns.org`.

---

## Network Setup Decision Tree

Before diving into port forwarding or tunnels, figure out which approach applies to you:

```
1. Run on your server:
      curl ifconfig.me
   Compare the result to your router's WAN IP (shown in the router admin panel).

   ┌─ Router WAN IP starts with 100.64.x.x (CGNAT range)? ─────► Use Playit.gg
   ├─ Router WAN IP differs from curl ifconfig.me result? ──────► Use Playit.gg
   └─ Router WAN IP matches curl ifconfig.me? ──────────────────► Port forwarding + DuckDNS

2. If using Playit.gg:
   • Skip router port forwarding
   • Skip DuckDNS setup (optional to keep for other services like Rails)
   • Players connect to: yourname.joinplayit.gg

3. If using DuckDNS + port forwarding:
   • Configure router port forwards (see Router Port Forwarding below)
   • Set up DuckDNS (see DuckDNS Setup below)
   • Players connect to: yourname.duckdns.org
```

> **Quick check:** The definitive CGNAT indicator is `100.64.0.0/10` as the router WAN IP,
> or a mismatch between your router's WAN IP and `curl ifconfig.me`. Some ISPs assign
> `10.x.x.x` WAN addresses without CGNAT — compare both values to be sure.

---

## Router Port Forwarding

> **Skip this section if you are behind CGNAT.** See [CGNAT / Playit.gg Tunnel](#cgnat--playitgg-tunnel) instead.

Minecraft clients connect directly to your public IP (or DuckDNS hostname). You need to forward **two ports** if you want both Java and Bedrock players to connect:

| Edition | Protocol | Port |
|---------|----------|------|
| Java | TCP | 25565 |
| Bedrock (Geyser) | UDP | 19132 |

### Steps

1. **Give the server a stable LAN IP:**
   - Preferred: Set a **DHCP reservation** in your router using the server's MAC address.
   - Alternative: Configure a static IP in Ubuntu (`/etc/netplan/`).

2. **Log in to your router admin panel** (often `192.168.1.1` or `192.168.0.1`).

3. **Create port-forward rules:**

   **Java Edition (required):**
   - Protocol: **TCP**
   - External port: **25565**
   - Internal IP: your server's LAN IP (e.g. `192.168.1.50`)
   - Internal port: **25565**

   **Bedrock Edition / Geyser (optional — skip if you don't need Bedrock crossplay):**
   - Protocol: **UDP**
   - External port: **19132**
   - Internal IP: your server's LAN IP (e.g. `192.168.1.50`)
   - Internal port: **19132**

4. **Test from outside your LAN:**
   - Use [mcsrvstat.us](https://mcsrvstat.us/) to check if your server is reachable.
   - Or ask a friend to connect to `<your-duckdns-subdomain>.duckdns.org`.

---

## CGNAT / Playit.gg Tunnel

### What is CGNAT?

**Carrier-Grade NAT (CGNAT)** is a practice where ISPs share a single public IP address among
many customers. This makes it impossible to receive incoming connections (like Minecraft players
connecting to your server) through traditional port forwarding.

**How to detect CGNAT:**

- Log in to your router admin panel and look at the **WAN IP address**.
- Run `curl ifconfig.me` on the server and compare to your router's WAN IP.
- If they **differ**, you are behind CGNAT.
- If the router WAN IP starts with `100.64.x.x` (range `100.64.0.0/10`), you are definitively behind CGNAT.
- If they match but you still can't port-forward, check for firewall rules at the ISP level.

### Playit.gg — Free Tunneling Solution

[Playit.gg](https://playit.gg) is a free tunneling service built specifically for game servers.
It routes traffic through Playit's servers so your players can connect even when port forwarding
is impossible. Latency impact is minimal (typically under 10 ms).

This setup installs the official **standalone `playit` agent binary** directly on the host as its
own systemd service (`playit.service`). The agent tunnels traffic to `localhost:25565`, so no
Docker networking layer is involved — connections are reliable and straightforward.

### Installation

```bash
sudo bash bin/setup-playit.sh
```

This script:
- Downloads the `playit` binary from [GitHub](https://github.com/playit-cloud/playit-agent/releases)
  and installs it at `/usr/local/bin/playit`
- Creates a dedicated `playit` system user
- Creates `/etc/playit/` for the agent's configuration and secret
- Writes and enables `playit.service` (systemd)
- Starts the service and shows the initial log output (including the claim URL)

### First-Time Tunnel Claim (one-time)

After running `setup-playit.sh`, watch the output for the claim URL. You can also follow live logs:

```bash
journalctl -u playit -f
```

Look for a line like:

```
Visit https://playit.gg/claim/xxxxx to claim your agent
```

Open the URL in a browser and log in (or create a free account) at
[playit.gg](https://playit.gg). The agent automatically creates a TCP tunnel for
port 25565 (Java Edition). For Bedrock crossplay (UDP 19132), add a tunnel on the
[Playit.gg dashboard](https://playit.gg).

### Player Connection

Players connect using your **Playit.gg tunnel address** instead of DuckDNS:

```
yourname.joinplayit.gg
```

The exact address is shown on your [playit.gg dashboard](https://playit.gg).

> **Note:** DuckDNS is **not needed** for Minecraft when using Playit.gg. You can keep
> DuckDNS if you use it for other services (e.g. Rails apps via Kamal).

### Managing the Agent

The agent runs as its own systemd service, independent of the Minecraft server.

```bash
# View agent logs (including claim URL on first run)
journalctl -u playit -f

# Restart the agent
sudo systemctl restart playit.service

# Check agent status
sudo systemctl status playit.service
```

Agent configuration is stored in `/etc/playit/`.

### Playit.gg Troubleshooting

| Problem | Solution |
|---------|----------|
| No claim URL in logs | Wait a few seconds; run `journalctl -u playit -n 50 --no-pager` |
| Agent not starting | Check `sudo systemctl status playit.service` and `journalctl -u playit` |
| Connection refused by players | Make sure Minecraft is running: `sudo systemctl status minecraft.service` |
| Tunnel shows offline | Restart the agent: `sudo systemctl restart playit.service` |
| Wrong tunnel address | Check the dashboard at [playit.gg](https://playit.gg) for your current address |

### Full Reset Procedure

Use this to wipe all Playit agent state and start fresh.

**Option A — use the reset script (recommended):**

```bash
sudo bash bin/reset-playit.sh
```

The script prompts for confirmation, stops and removes the service, deletes the agent secret
(`/etc/playit/`), removes the binary, and optionally runs `setup-playit.sh` immediately afterward.

**Option B — manual steps:**

```bash
# 1. Stop and disable the service
sudo systemctl stop playit.service
sudo systemctl disable playit.service

# 2. Remove the unit file and reload systemd
sudo rm /etc/systemd/system/playit.service
sudo systemctl daemon-reload

# 3. Remove the agent secret (forces re-claim on reinstall)
sudo rm -rf /etc/playit/

# 4. Remove the binary
sudo rm -f /usr/local/bin/playit
```

After the reset, go to the [Playit.gg dashboard](https://playit.gg) → **Agents** and remove
any stale agents from previous installs so only the new one remains.

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

The Minecraft server is managed by systemd. After running `setup-minecraft.sh` the service
starts automatically and restarts on failure.

```bash
# Check status
sudo systemctl status minecraft.service

# Follow logs
journalctl -u minecraft -f
```

The first start downloads and initializes the Paper server — this may take a minute or two.

> **EULA:** The setup script automatically writes `eula=true` to
> `/opt/minecraft/data/eula.txt`. By running `setup-minecraft.sh` you agree to the
> [Minecraft EULA](https://aka.ms/MinecraftEULA).

### Manage the Server

```bash
# Start / stop / restart
sudo systemctl start minecraft.service
sudo systemctl stop minecraft.service
sudo systemctl restart minecraft.service

# Send a console command via RCON (requires mcrcon or similar)
# mcrcon -H 127.0.0.1 -P 25575 -p changeme_rcon_secret "list"
```

### Op a Player

Edit `/opt/minecraft/data/ops.json` or connect via RCON and run:

```
op YourUsername
```

---

## Bedrock Edition Support (Optional)

[Geyser](https://geysermc.org/) + [Floodgate](https://wiki.geysermc.org/floodgate/) allow players
on Xbox, Switch, mobile (iOS/Android), and Windows 10/11 Bedrock Edition to join your Java Paper
server. To use them, install the Geyser-Spigot and Floodgate plugin JARs into
`/opt/minecraft/data/plugins/` and restart the server.

### How to Connect (Bedrock Players)

1. Open Minecraft on your Bedrock device (Xbox, Switch, mobile, Windows 10/11).
2. Go to **Play → Servers → Add Server**.
3. Enter:
   - **Server Address:** `yourname.duckdns.org`
   - **Port:** `19132`
4. Connect and join!

> **Note:** You must have UDP port 19132 forwarded on your router (see [Router Port Forwarding](#router-port-forwarding)).

### Whitelisting Bedrock Players

Bedrock players join with a prefix before their username (default prefix: `.`).

For example, a Bedrock player with gamertag `Steve` appears as `.Steve` in-game.

To whitelist a Bedrock player, include the prefixed name in
`/opt/minecraft/data/whitelist.json` or via RCON:

```
whitelist add .BedrockPlayer
whitelist reload
```

### Known Limitations

- Some Java Edition features don't translate perfectly to Bedrock (e.g. certain redstone mechanics, inventory UI differences).
- Bedrock players use a slightly different combat system.
- Performance overhead is minimal — negligible for ~10 players.

---

## Checking Status

```bash
sudo bash bin/status.sh
```

This shows:
- Docker service status (still used for Kamal)
- Minecraft systemd service status and last log line
- Playit.gg agent status and recent log lines
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
sudo systemctl stop minecraft.service
sudo restic -r <RESTIC_REPOSITORY> restore latest --target /
sudo systemctl start minecraft.service
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

## Troubleshooting / FAQ

### Bedrock players can't connect

1. **Check UDP 19132 is forwarded on your router** — TCP forwarding alone is not enough. Bedrock uses UDP.
2. **Verify the UFW rule is active:**
   ```bash
   sudo ufw status | grep 19132
   ```
   You should see `19132/udp  ALLOW  Anywhere`.
3. **Confirm Geyser is installed** in `/opt/minecraft/data/plugins/`.
4. Restart the server after any plugin changes:
   ```bash
   sudo systemctl restart minecraft.service
   ```

### Whitelist not working for Bedrock players

Bedrock players use a prefixed username (default prefix: `.`). Make sure to include the prefix when whitelisting.

---

## Directory Layout

```
.
├── README.md               # This file
├── bin/
│   ├── setup-host.sh       # Base packages, locale, timezone
│   ├── setup-docker.sh     # Docker CE + Compose plugin (for Kamal)
│   ├── setup-firewall.sh   # UFW rules
│   ├── setup-fail2ban.sh   # fail2ban (sshd)
│   ├── setup-duckdns.sh    # DuckDNS systemd service + timer
│   ├── setup-minecraft.sh  # Bare-metal Paper server + minecraft.service
│   ├── setup-backups.sh    # Restic + systemd backup timer
│   ├── setup-playit.sh     # Playit.gg agent (CGNAT support)
│   ├── reset-playit.sh     # Remove Playit.gg agent + data
│   └── status.sh           # Health dashboard
├── minecraft/
│   └── README.md           # Minecraft bare-metal configuration notes
├── duckdns/
│   └── .env.example        # DuckDNS credentials template
└── backups/
    ├── restic.env.example  # Restic credentials template
    ├── minecraft-backup.sh # Backup script (rcon safe-save + restic)
    ├── minecraft-backup.service
    ├── minecraft-backup.timer
    └── README.md           # Backup + restore docs
```
