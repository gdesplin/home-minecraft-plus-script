# Minecraft (Bare-Metal)

The Minecraft server is now run directly on the host (no Docker).

Configuration is in `/opt/minecraft/data/server.properties`.
Edit that file directly to change server settings, then restart:

    sudo systemctl restart minecraft.service

To install/reinstall:

    sudo bash bin/setup-minecraft.sh

To set up playit.gg tunneling:

    sudo bash bin/setup-playit.sh
