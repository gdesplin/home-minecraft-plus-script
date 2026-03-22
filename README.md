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

# 2. Docker CE + Compose plugin
sudo bash bin/setup-docker.sh

# 3. UFW firewall
sudo bash bin/setup-firewall.sh

# 4. fail2ban for SSH
sudo bash bin/setup-fail2ban.sh

# 5. DuckDNS dynamic DNS (configure duckdns/.env first — see below)
#    Skip this step if you are using Playit.gg (see CGNAT section)
sudo bash bin/setup-duckdns.sh

# 6. Minecraft server (configure minecraft/.env first — see below)
sudo bash bin/setup-minecraft.sh

# 7. Restic backups (configure backups/restic.env first — see below)
sudo bash bin/setup-backups.sh

# Optional: Playit.gg tunnel (required when behind CGNAT — see below)
sudo bash bin/setup-playit.sh
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

### Installation

```bash
sudo bash bin/setup-playit.sh
```

This script:
- Adds the official Playit.gg APT repository
- Installs the `playit` agent via APT
- Creates a dedicated `playit` system user for security
- Sets up `/opt/playit/` — the directory where the APT package installs the binary (`/opt/playit/playit`)
- Creates `/etc/playit/` — the canonical secret/config directory used by the vendor systemd unit
- Writes a systemd drop-in override at `/etc/systemd/system/playit.service.d/override.conf`
  to run the service as the `playit` user — **without** overwriting the vendor unit at
  `/usr/lib/systemd/system/playit.service`

> **Note:** The official Playit APT package (v0.17.1) installs the binary at
> **`/opt/playit/playit`** only — it does **not** add `playit` to `$PATH`.
> `which playit` will return nothing even after a successful install; this is expected.
> Always use the full path `/opt/playit/playit` for any manual command.

### First-Time Tunnel Claim (one-time)

> ⚠ **Critical:** always claim the agent as the **`playit` service user**, never as your own login.
> Running `/opt/playit/playit` as your normal user writes a separate secret key to `~/.config/playit_gg/`
> and registers a duplicate agent identity. The service then runs as a different agent than the
> one you claimed, causing tunnels to appear "online" on the dashboard but receive no traffic.

```bash
sudo -u playit /opt/playit/playit
```

The agent will print a URL. Open it in a browser and log in (or create a free account) at
[playit.gg](https://playit.gg). Once claimed, configure your tunnels on the dashboard:

| Tunnel type | Port | Local address | Purpose |
|-------------|------|---------------|---------|
| TCP | 25565 | `127.0.0.1:25565` | Minecraft Java Edition |
| UDP | 19132 | `127.0.0.1:19132` | Minecraft Bedrock / Geyser (optional) |

> **Use `127.0.0.1` as the local address** (not the Docker container's internal IP like
> `172.18.0.2`). The Playit agent runs on the host and reaches Minecraft through Docker's
> published port on `127.0.0.1`.

After claiming, press **Ctrl+C** to exit.

### Enable the Service

```bash
sudo systemctl enable --now playit
```

The agent will now start automatically on every boot. Verify it is running:

```bash
sudo systemctl status playit
sudo journalctl -u playit -n 30
```

### Player Connection

Players connect using your **Playit.gg tunnel address** instead of DuckDNS:

```
yourname.joinplayit.gg
```

The exact address is shown on your [playit.gg dashboard](https://playit.gg).

> **Note:** DuckDNS is **not needed** for Minecraft when using Playit.gg. You can keep
> DuckDNS if you use it for other services (e.g. Rails apps via Kamal).

### Managing the Playit.gg Service

```bash
# Check tunnel status
sudo systemctl status playit

# View live logs
sudo tail -f /var/log/playit/playit.log

# Follow systemd journal
sudo journalctl -u playit -f

# Restart the tunnel
sudo systemctl restart playit

# Stop the tunnel
sudo systemctl stop playit
```

### Playit.gg Troubleshooting

| Problem | Solution |
|---------|----------|
| Agent not starting | `sudo systemctl status playit` — check for errors |
| Can't claim tunnel | Re-run `sudo -u playit /opt/playit/playit` — do **not** run as your normal user |
| Connection refused by players | Make sure Minecraft is running: `sudo docker compose -f /opt/minecraft/compose.yml ps` |
| Tunnel shows offline | Restart the service: `sudo systemctl restart playit` |
| Wrong tunnel address | Check the dashboard at [playit.gg](https://playit.gg) for your current address |
| **`which playit` returns nothing** | Expected — the APT package installs to `/opt/playit/playit` only (not on `$PATH`). Use the full path for all manual commands. See [below](#which-playit-returns-nothing). |
| **Tunnel online, but no traffic / connection attempts** | You have duplicate agent identities — see [below](#duplicate-agent-identity-tunnel-online-no-traffic) |
| **Agent AND tunnel both online, Minecraft works on LAN, but tunnel connections fail** | Docker port publishing or wrong tunnel local address — see [below](#agent-and-tunnel-online-minecraft-works-on-lan-external-connections-still-fail) |

#### `which playit` Returns Nothing

**Symptom:** `which playit` prints nothing even though `apt-cache policy playit` shows the
package is installed (e.g. `Installed: 0.17.1`).

**Cause:** The official Playit APT package (v0.17.1) installs the binary at
`/opt/playit/playit` — it does **not** create a symlink in `/usr/bin/` or anywhere else on
`$PATH`. This is the expected layout for this package version.

**Verify the binary is present:**

```bash
ls -l /opt/playit/playit
/opt/playit/playit --version
```

**Fix:** use the full path for all manual Playit commands:

```bash
# Claim / interactive run
sudo -u playit /opt/playit/playit

# Check version
/opt/playit/playit --version

# The systemd service uses the full path automatically — no action needed there.
sudo systemctl cat playit   # ExecStart should reference /opt/playit/playit
```

If `/opt/playit/playit` does not exist, reinstall:

```bash
sudo apt-get install --reinstall playit
ls -l /opt/playit/playit
```

#### Agent and Tunnel Online, Minecraft Works on LAN, External Connections Still Fail

**Symptom:** The Playit dashboard shows both the agent and tunnel as "online". LAN clients
can connect to the Minecraft server using the server's local IP. But players connecting
through the Playit tunnel time out, and nothing appears in the Playit agent logs — no
incoming connection attempts are logged at all.

This scenario (nothing in logs, zero traffic through the tunnel) is different from the
[Duplicate Agent Identity](#duplicate-agent-identity-tunnel-online-no-traffic) case.
Work through the checks below in order:

---

**Step 1 — Verify the Docker container is publishing port 25565 on the host**

```bash
sudo docker ps --format "table {{.Names}}\t{{.Ports}}"
```

The `mc` container must show a port mapping that includes `0.0.0.0:25565->25565/tcp`.
If the `Ports` column is empty or only shows the container-internal port without a host
binding, the port is **not** published to the host and the Playit agent cannot reach it.

**Fix:** make sure `compose.yml` (in `/opt/minecraft/`) contains the correct `ports` stanza:

```yaml
ports:
  - "25565:25565"
  - "19132:19132/udp"
  - "127.0.0.1:25575:25575"   # RCON — localhost only
```

Then restart the stack:

```bash
cd /opt/minecraft && sudo docker compose down && sudo docker compose up -d
```

---

**Step 2 — Confirm the host can reach `127.0.0.1:25565`**

The Playit agent runs on the host and connects to `127.0.0.1:25565`. Test this directly:

```bash
# Requires the netcat-openbsd package (usually already present)
nc -zv 127.0.0.1 25565
```

Expected output: `Connection to 127.0.0.1 25565 port [tcp/*] succeeded!`

If the connection is **refused or times out**, Docker is not publishing the port correctly
(go back to Step 1) or the Minecraft container is still starting up (wait 90 s and retry).

You can also confirm the host is actually listening:

```bash
sudo ss -tlnp | grep 25565
```

This should show a line like `LISTEN ... 0.0.0.0:25565`.

---

**Step 3 — Verify the Playit tunnel local address on the dashboard**

Log in to [playit.gg](https://playit.gg) → **Tunnels** → edit your Minecraft tunnel.

| Field | Required value |
|-------|---------------|
| Protocol | TCP |
| Local Address | `127.0.0.1` |
| Local Port | `25565` |

> **Do not use the Docker container's internal bridge IP** (e.g. `172.17.0.2` or `172.18.0.2`).
> The Playit agent runs on the host and reaches Minecraft through Docker's published port on
> `127.0.0.1`, not through the Docker bridge network directly.

After saving any changes on the dashboard, wait ~30 s and retry the connection.

---

**Step 4 — Check for a stale systemd drop-in override**

A leftover override that references the wrong secret path causes the agent to silently
fail (exit-code 101) or run with the wrong config:

```bash
sudo systemctl cat playit
```

Look at the `ExecStart` line:
- **Correct (vendor unit, no override):** `/opt/playit/playit` with no `--secret_path` flag,
  or pointing to a path that actually exists.
- **Problem:** `--secret_path /etc/playit/playit.toml` and that file does not exist.

Check for a drop-in:

```bash
ls /etc/systemd/system/playit.service.d/ 2>/dev/null && \
  cat /etc/systemd/system/playit.service.d/override.conf
```

If an `override.conf` is present and references a missing secret path, remove it:

```bash
sudo rm -rf /etc/systemd/system/playit.service.d/
sudo systemctl daemon-reload
sudo systemctl restart playit
```

> **Note:** `setup-playit.sh` creates a minimal override (`User=playit`, `Group=playit`,
> `WorkingDirectory=/opt/playit`) that is safe and intentional. Only remove the override if
> it contains an `--secret_path` pointing to a file that does not exist, or other stale flags.

---

**Step 5 — Confirm the Playit service user and secret location match**

The agent stores its secret key in the service user's config directory. If the service
runs as a different user than the one that ran the interactive claim step, it will start
with a fresh (unclaimed) identity and the tunnel will receive no traffic.

Check which user the service runs as:

```bash
systemctl show playit -p User --value
```

Then confirm that user's config exists and contains a `secret_key`:

```bash
# If the service runs as 'playit':
sudo cat /opt/playit/.config/playit_gg/playit.toml 2>/dev/null \
  || sudo ls /etc/playit/ 2>/dev/null \
  || echo "No config found for 'playit' user"

# Also check the path the vendor unit explicitly passes (if any):
sudo systemctl cat playit | grep secret
```

If no config exists for the service user, re-run the claim as the **same user** the service
runs as:

```bash
# e.g. if the service runs as 'playit':
sudo -u playit /opt/playit/playit
# open the URL, claim, set tunnel local address to 127.0.0.1:25565, Ctrl+C
sudo systemctl restart playit
```

---

**Step 6 — Inspect the live agent logs**

```bash
sudo journalctl -u playit -n 50 --no-pager
```

Look for lines indicating:
- `tunnel running` — good; the agent is registered and should be forwarding.
- `reconnecting` or `error` — the agent is having trouble reaching Playit's servers.
- Silence after restart — the agent may have exited immediately (check exit code with
  `sudo systemctl status playit`).

If the agent logs `tunnel running` but still no connection attempts appear when a client
tries to connect, the issue is almost always either Step 3 (wrong local address in the
dashboard) or a duplicate agent identity (see below).

---

**Step 7 — Still stuck? Do a full reset**

If none of the above resolves it, do a complete wipe with the reset script:

```bash
sudo bash bin/reset-playit.sh
```

After the reset, re-claim as the `playit` user, ensure the dashboard shows only **one**
agent, and set the tunnel local address to `127.0.0.1:25565`.

---

#### Duplicate Agent Identity (tunnel online, no traffic)

**Symptom:** the Playit dashboard shows the tunnel as "online" and `playit.log` says
`tunnel running, 1 tunnels registered`, but external connection attempts produce no log
lines and players cannot connect.

**Cause:** the tunnel on the dashboard is bound to a different secret key than the one
the running service is using. This happens when `/opt/playit/playit` was run as your normal
user at some point, creating `~/.config/playit_gg/playit.toml` with a separate identity.

**Diagnosis:**

```bash
# Which key is the running service using?
# (sudo needed: /etc/playit/ is owned root:playit with 750 permissions)
sudo cat /etc/playit/playit.toml

# Is there a second identity from a previous interactive run?
cat ~/.config/playit_gg/playit.toml 2>/dev/null || echo "(no user-level config)"
```

If the `secret_key` values differ, the service is running with the wrong identity.

**Fix:** do a [Full Reset](#full-reset-procedure) below to start clean.

Also check your [Playit.gg dashboard → Agents](https://playit.gg): you should see only
**one** agent listed. Delete any stale/duplicate agents.

#### Full Reset Procedure

Use this to wipe all Playit state and start fresh with a single clean identity.

**Option A — use the reset script (recommended):**

```bash
sudo bash bin/reset-playit.sh
```

The script prompts for confirmation, removes all state, and optionally runs
`setup-playit.sh` immediately afterward.

**Option B — manual steps:**

```bash
# 1. Stop and disable the service
sudo systemctl stop playit || true
sudo systemctl disable playit || true

# 2. Purge the APT package (removes vendor unit and binary)
sudo apt-get remove --purge -y playit || true
sudo apt-get autoremove -y

# 3. Delete ALL Playit state (config, logs, drop-in, user-level identity)
sudo rm -rf /etc/playit
sudo rm -rf /var/log/playit
sudo rm -rf /opt/playit
sudo rm -rf /etc/systemd/system/playit.service.d
rm -rf ~/.config/playit_gg

# 4. Reload systemd
sudo systemctl daemon-reload

# 5. Re-install
sudo bash bin/setup-playit.sh

# 6. Claim as the service user (one identity only)
# NOTE: 'which playit' returns nothing — always use the full path
sudo -u playit /opt/playit/playit
# → open the URL, claim, set tunnel local address to 127.0.0.1:25565, Ctrl+C

# 7. Enable and start
sudo systemctl enable --now playit
sudo journalctl -u playit -n 30 --no-pager
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

## Bedrock Edition Support (Optional)

[Geyser](https://geysermc.org/) + [Floodgate](https://wiki.geysermc.org/floodgate/) are supported by the `itzg/minecraft-server` image and are **enabled by default in this setup** (via `GEYSER_ENABLED=true` and `FLOODGATE_ENABLED=true` in `.env.example`). They allow players on Xbox, Switch, mobile (iOS/Android), and Windows 10/11 Bedrock Edition to join your Java Paper server.

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

To whitelist a Bedrock player, include the prefixed name:

```env
# In minecraft/.env
WHITELIST=JavaPlayer,.BedrockPlayer
ENFORCE_WHITELIST=true
```

Or via RCON at runtime (no restart needed):

```bash
sudo docker exec mc rcon-cli "whitelist add .BedrockPlayer"
sudo docker exec mc rcon-cli "whitelist reload"
```

### Disabling Bedrock Support

If you don't need Bedrock crossplay, set these in `minecraft/.env`:

```env
GEYSER_ENABLED=false
FLOODGATE_ENABLED=false
```

Then restart the container:

```bash
cd /opt/minecraft && sudo docker compose restart
```

You can also skip forwarding UDP 19132 on your router in this case.

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

## Troubleshooting / FAQ

### Bedrock players can't connect

1. **Check UDP 19132 is forwarded on your router** — TCP forwarding alone is not enough. Bedrock uses UDP.
2. **Verify the UFW rule is active:**
   ```bash
   sudo ufw status | grep 19132
   ```
   You should see `19132/udp  ALLOW  Anywhere`.
3. **Confirm Geyser is enabled** in `minecraft/.env`:
   ```env
   GEYSER_ENABLED=true
   FLOODGATE_ENABLED=true
   ```
4. Restart the container after any `.env` change:
   ```bash
   cd /opt/minecraft && sudo docker compose restart
   ```

### Whitelist not working for Bedrock players

Bedrock players use a prefixed username (default prefix: `.`). Make sure to include the prefix when whitelisting:

```bash
# Wrong (Java format)
sudo docker exec mc rcon-cli "whitelist add Steve"

# Correct (Bedrock format with Floodgate prefix)
sudo docker exec mc rcon-cli "whitelist add .Steve"
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
│   ├── setup-playit.sh     # Playit.gg tunnel (CGNAT support)
│   ├── reset-playit.sh     # Full Playit.gg wipe + reinstall helper
│   └── status.sh           # Health dashboard
├── config/
│   └── playit.service      # LEGACY — historical reference only (not installed by setup-playit.sh)
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
