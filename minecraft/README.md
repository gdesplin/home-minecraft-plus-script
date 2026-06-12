# Minecraft (Bare-Metal)

The Minecraft server runs directly on the host under `minecraft.service` (no Docker).

Configuration is in `/opt/minecraft/data/server.properties`.
Edit that file directly to change server settings, then restart:

    sudo systemctl restart minecraft.service

To install/reinstall:

    sudo bash bin/setup-minecraft.sh

Players connect through the Oracle VPS relay. The VPS forwards public `TCP 25565`
over WireGuard to this host.

Useful checks:

    ip -brief addr show wg0
    ss -tulpn | grep 25565
    journalctl -u minecraft -f
