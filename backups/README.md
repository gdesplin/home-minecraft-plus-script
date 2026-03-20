# Backups — Minecraft World Restic Backup

Hourly restic snapshots of `/opt/minecraft/data` with safe in-game flush via RCON.

---

## Retention Policy

| Policy         | Value |
|----------------|-------|
| keep-hourly    | 24    |
| keep-daily     | 7     |
| keep-weekly    | 12    |
| keep-monthly   | 6     |
| keep-yearly    | 5     |

To adjust retention, edit `/etc/restic/restic.env` and change `KEEP_*` values. The next backup run will apply the new policy.

---

## Setup

```bash
# 1. Copy and edit the env template
cp backups/restic.env.example backups/restic.env
nano backups/restic.env   # fill in RESTIC_REPOSITORY and RESTIC_PASSWORD

# 2. Run the setup script (installs restic, systemd timer, initialises repo)
sudo bash bin/setup-backups.sh
```

---

## Running a Manual Backup

```bash
sudo systemctl start minecraft-backup.service

# Follow the logs
sudo journalctl -u minecraft-backup.service -f
```

---

## Listing Snapshots

```bash
# Load env and list snapshots
sudo bash -c 'source /etc/restic/restic.env && restic snapshots'
```

Or, if you have the env values handy:

```bash
sudo RESTIC_REPOSITORY=<your-repo> RESTIC_PASSWORD=<your-password> restic snapshots
```

---

## Restoring

> ⚠️ Always stop the Minecraft server before restoring to avoid data conflicts.

### Restore Latest Snapshot

```bash
# Stop the server
cd /opt/minecraft
sudo docker compose stop

# Load restic env
source /etc/restic/restic.env   # or export RESTIC_REPOSITORY / RESTIC_PASSWORD manually

# List snapshots to find the one you want
sudo restic snapshots

# Restore latest snapshot into the data directory
# The --target flag is the ROOT — restic restores the full path under it,
# so this restores to /opt/minecraft/data (matching the original backup path).
sudo restic restore latest --target /

# Verify the restore looks correct
ls -la /opt/minecraft/data/

# Start the server
sudo docker compose start
```

### Restore a Specific Snapshot

```bash
# Find the snapshot ID from: sudo restic snapshots
SNAPSHOT_ID=abc12345

sudo restic restore "${SNAPSHOT_ID}" --target /
```

### Restore to a Different Location (inspect first)

```bash
# Restore to /tmp/mc-restore to inspect before overwriting
sudo restic restore latest --target /tmp/mc-restore

ls /tmp/mc-restore/opt/minecraft/data/
```

### Restore a Single World Directory

```bash
# Restore only the 'world' directory from the latest snapshot
sudo restic restore latest \
  --target / \
  --include /opt/minecraft/data/world
```

---

## Checking Repository Integrity

```bash
sudo bash -c 'source /etc/restic/restic.env && restic check'

# Read-verify a sample of data blocks
sudo bash -c 'source /etc/restic/restic.env && restic check --read-data-subset=10%'
```

---

## Timer Status

```bash
# Show backup timer status and next run time
sudo systemctl status minecraft-backup.timer

# Show last backup run result
sudo systemctl status minecraft-backup.service

# View backup logs
sudo journalctl -u minecraft-backup.service --since today
```

---

## Backup Destinations

The `RESTIC_REPOSITORY` in `restic.env` supports many backends:

| Backend | Example |
|---------|---------|
| Local path | `/mnt/backup-disk/minecraft` |
| SFTP | `sftp:user@nas.local:/backups/minecraft` |
| Backblaze B2 | `b2:my-bucket:/minecraft` |
| AWS S3 | `s3:s3.amazonaws.com/my-bucket` |
| S3-compatible (Wasabi, Cloudflare R2, etc.) | `s3:https://s3.wasabisys.com/my-bucket` |

For cloud backends, also set the provider credentials in `restic.env` (see `restic.env.example`).

> **Recommendation:** Use a remote or off-site backend. A backup on the same disk as the data
> doesn't protect against disk failure.

---

## Files

| File | Description |
|------|-------------|
| `restic.env.example` | Template for credentials and retention settings |
| `minecraft-backup.sh` | Backup script: RCON flush → restic snapshot → prune |
| `minecraft-backup.service` | Systemd one-shot service that runs the backup script |
| `minecraft-backup.timer` | Systemd timer — triggers the service every hour |
