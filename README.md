# Home Minecraft Plus Script

Idempotent bootstrap for a headless **Ubuntu 24.04 LTS** mini PC that runs:

- A **Paper Minecraft server** on bare metal under `minecraft.service`
- An **Oracle Cloud VPS + WireGuard relay** for public Minecraft access
- **Restic backups** of `/opt/minecraft/data`
- Security basics: **UFW** and **fail2ban**
- A **Docker/Kamal-ready host** for other apps that share the box

---

## Table of Contents

1. [What This Repo Manages](#what-this-repo-manages)
2. [Prerequisites](#prerequisites)
3. [Clone This Repo](#clone-this-repo)
4. [Run the Host Setup](#run-the-host-setup)
5. [Minecraft Service](#minecraft-service)
6. [Oracle VPS + WireGuard Relay](#oracle-vps--wireguard-relay)
7. [Checking Status](#checking-status)
8. [Backups and Restore](#backups-and-restore)
9. [Bedrock Support (Optional)](#bedrock-support-optional)
10. [Kamal Notes](#kamal-notes)
11. [Security Hardening](#security-hardening)
12. [Directory Layout](#directory-layout)

---

## What This Repo Manages

This repo reflects the **current** Minecraft setup:

- The mini PC runs the actual Paper server and world data.
- Friends connect through an **Oracle Cloud VPS public IP**.
- The Oracle VPS forwards **TCP 25565** over **WireGuard (`wg0`)** to the mini PC.
- Optional DNS can point at the Oracle VPS, but DNS management is **outside this repo**.

This repo no longer manages Playit, DuckDNS, or Cloudflare tunnel workflows.

---

## Prerequisites

### Mini PC

| Requirement | Notes |
|-------------|-------|
| Ubuntu 24.04 LTS Server | Minimal install recommended |
| A non-root user with `sudo` | The repo assumes you use this account for setup |
| SSH key auth configured | Recommended before hardening SSH |
| 8+ GB RAM | 4 GB is reserved for Minecraft by default |
| SSD storage | Strongly recommended |

### Oracle VPS

| Requirement | Notes |
|-------------|-------|
| Ubuntu 24.04 LTS | Any small always-free shape is fine |
| Public IPv4 address | Players connect here |
| WireGuard installed and configured | The VPS is the relay, not the game host |
| OCI ingress rule for TCP 25565 | Required for Java Edition access |

---

## Clone This Repo

```bash
sudo apt install -y git
git clone https://github.com/gdesplin/home-minecraft-plus-script.git ~/homelab
cd ~/homelab
```

---

## Run the Host Setup

Run the mini-PC setup scripts in this order. Each script is intended to be safe to re-run.

```bash
# 1. Base packages, locale, timezone
sudo bash bin/setup-host.sh

# 2. Docker CE + Compose plugin (for Kamal / sidecar apps)
sudo bash bin/setup-docker.sh

# 3. UFW rules for SSH, Minecraft, Bedrock, HTTP, HTTPS
sudo bash bin/setup-firewall.sh

# 4. fail2ban for SSH
sudo bash bin/setup-fail2ban.sh

# 5. Paper Minecraft service
sudo bash bin/setup-minecraft.sh

# 6. Restic backups
cp backups/restic.env.example backups/restic.env
nano backups/restic.env
sudo bash bin/setup-backups.sh
```

Server settings live in `/opt/minecraft/data/server.properties`.

```bash
sudo nano /opt/minecraft/data/server.properties
sudo systemctl restart minecraft.service
```

---

## Minecraft Service

The Paper server is managed by systemd.

```bash
# Status
sudo systemctl status minecraft.service

# Follow logs
journalctl -u minecraft -f

# Restart
sudo systemctl restart minecraft.service
```

The service runs from:

- Binary: `/opt/minecraft/bin/paper.jar`
- Data: `/opt/minecraft/data`
- Unit: `/etc/systemd/system/minecraft.service`

The default Java listener is:

- `TCP 25565` for Java Edition
- `UDP 19132` if you later add Geyser for Bedrock support

---

## Oracle VPS + WireGuard Relay

### Topology

```text
Minecraft client
  -> Oracle VPS public IP:25565
  -> iptables DNAT/FORWARD on Oracle VPS
  -> WireGuard tunnel (wg0)
  -> mini PC 10.200.0.2:25565
  -> Paper server
```

### Mini-PC Expectations

The mini PC should:

- Have `wg0` up
- Reach the Oracle peer over WireGuard
- Listen on `25565`

Useful checks on the mini PC:

```bash
ip -brief addr show wg0
ss -tulpn | grep 25565
systemctl status minecraft.service
```

### Oracle VPS Expectations

The Oracle VPS should:

- Have `wg0` up
- Reach `10.200.0.2:25565`
- Forward inbound `TCP 25565` to `10.200.0.2:25565`
- Allow inbound `TCP 25565` in Oracle Cloud security rules

Useful checks on the Oracle VPS:

```bash
sudo wg show
nc -vz 10.200.0.2 25565
sudo iptables -t nat -S | grep 25565
sudo iptables -S FORWARD | grep 25565
```

### Forwarding Rules on the Oracle VPS

If you need to recreate the relay, run this on the VPS:

```bash
PUB_IF=$(ip route show default | awk '/default/ {print $5; exit}')
WG_IF=wg0
MC_IP=10.200.0.2
MC_PORT=25565

sudo sysctl -w net.ipv4.ip_forward=1
printf 'net.ipv4.ip_forward=1\n' | sudo tee /etc/sysctl.d/99-minecraft-ip-forward.conf >/dev/null

sudo iptables -t nat -C PREROUTING -i "$PUB_IF" -p tcp --dport "$MC_PORT" -j DNAT --to-destination "$MC_IP:$MC_PORT" 2>/dev/null || \
sudo iptables -t nat -A PREROUTING -i "$PUB_IF" -p tcp --dport "$MC_PORT" -j DNAT --to-destination "$MC_IP:$MC_PORT"

sudo iptables -C FORWARD -i "$PUB_IF" -o "$WG_IF" -p tcp -d "$MC_IP" --dport "$MC_PORT" -m conntrack --ctstate NEW,ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || \
sudo iptables -A FORWARD -i "$PUB_IF" -o "$WG_IF" -p tcp -d "$MC_IP" --dport "$MC_PORT" -m conntrack --ctstate NEW,ESTABLISHED,RELATED -j ACCEPT

sudo iptables -C FORWARD -i "$WG_IF" -o "$PUB_IF" -p tcp -s "$MC_IP" --sport "$MC_PORT" -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || \
sudo iptables -A FORWARD -i "$WG_IF" -o "$PUB_IF" -p tcp -s "$MC_IP" --sport "$MC_PORT" -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

sudo iptables -t nat -C POSTROUTING -o "$WG_IF" -p tcp -d "$MC_IP" --dport "$MC_PORT" -j MASQUERADE 2>/dev/null || \
sudo iptables -t nat -A POSTROUTING -o "$WG_IF" -p tcp -d "$MC_IP" --dport "$MC_PORT" -j MASQUERADE
```

### OCI Ingress Rule

In Oracle Cloud, allow:

- Source: `0.0.0.0/0`
- Protocol: `TCP`
- Destination port: `25565`

Players should connect to the **Oracle public IP** or to any DNS name you point at that VPS.

---

## Checking Status

```bash
sudo bash bin/status.sh
```

This shows:

- Docker service status
- Minecraft service status
- WireGuard interface presence and route summary
- Backup timer status
- fail2ban status
- UFW status
- Disk usage

---

## Backups and Restore

See [`backups/README.md`](backups/README.md) for full backup and restore notes.

Quick restore:

```bash
sudo systemctl stop minecraft.service
sudo bash -c 'source /etc/restic/restic.env && restic restore latest --target /'
sudo systemctl start minecraft.service
```

---

## Bedrock Support (Optional)

If you install **Geyser** + **Floodgate**, Bedrock players can join through `UDP 19132`.

That requires:

1. Geyser/Floodgate plugin JARs in `/opt/minecraft/data/plugins/`
2. `19132/udp` allowed on the mini PC firewall
3. Matching UDP forwarding on the **Oracle VPS**
4. Matching UDP ingress in **OCI**

Bedrock clients then connect to the Oracle VPS public IP on port `19132`.

---

## Kamal Notes

This host is still set up to run Docker-based workloads alongside Minecraft.

```bash
sudo bash bin/setup-docker.sh
```

Typical split:

- Minecraft: `25565`
- Bedrock (optional): `19132/udp`
- Web apps / Traefik: `80` and `443`

Minecraft and Kamal do not conflict as long as they stay on separate ports.

---

## Security Hardening

### Restrict SSH to LAN Only

```bash
sudo ufw delete allow 22/tcp
sudo ufw allow from 192.168.1.0/24 to any port 22 proto tcp comment 'SSH LAN only'
sudo ufw reload
```

Adjust the subnet to match your LAN.

### Disable SSH Password Authentication

```bash
sudo sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
sudo systemctl restart sshd
```

### fail2ban

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

```text
.
├── README.md
├── bin/
│   ├── setup-host.sh
│   ├── setup-docker.sh
│   ├── setup-firewall.sh
│   ├── setup-fail2ban.sh
│   ├── setup-minecraft.sh
│   ├── setup-backups.sh
│   └── status.sh
├── minecraft/
│   └── README.md
└── backups/
    ├── restic.env.example
    ├── minecraft-backup.sh
    ├── minecraft-backup.service
    ├── minecraft-backup.timer
    └── README.md
```
