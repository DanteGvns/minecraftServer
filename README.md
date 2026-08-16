# Minecraft Bedrock Server Infrastructure

This repository contains a complete, self‑contained infrastructure setup for running a Minecraft Bedrock server inside WSL2 using Docker. All deployment, backup, automation, logging, health‑checking, and restore logic is included in the `infra/` directory, making the project fully portable and easy to redeploy on any machine.

## Overview

The server runs inside WSL2 using Docker and is managed through a set of scripts and systemd units. The design ensures reliable uptime, automated nightly backups, gamerule enforcement, log viewing, health monitoring, restore capability, and simple redeployment. All infrastructure files live in the repo, while systemd units are installed into the Linux system directory using `install-units.sh`.

## Directory Structure

`infra/docker-compose.yml`  
Defines the Bedrock server container, ports, volume, and restart policy.

`infra/deploy.sh`  
Pulls the latest Bedrock image, restarts the container, and reapplies gamerules.

`infra/gamerules.sh`  
Sends gamerule commands into the running Bedrock container to enforce server rules.

`infra/backup.sh`  
Creates a consistent world backup, pauses saving, copies the world data, resumes saving, and prunes backups to keep the last 3 daily copies plus one weekly copy (max 4 backups total).

`infra/logviewer.sh`  
Interactive log viewer for Bedrock server logs, backup logs, systemd logs, and live docker log tailing.

`infra/healthcheck.sh`  
Runs a full operational health check: Docker status, container status, Bedrock responsiveness, backup count, systemd timer status, systemd service status, and disk usage.

`infra/restore.sh`  
Restores a selected backup by stopping the container, replacing the world data, and restarting the server.

`infra/mc-backup.service`  
Systemd service that runs `backup.sh` as a one‑shot job.

`infra/mc-backup.timer`  
Systemd timer that triggers the backup service every night at 3 AM.

`infra/install-units.sh`  
Installs the systemd service and timer into `/etc/systemd/system/`, reloads systemd, enables the timer, and starts it.

## Setup Instructions

1. Clone this repository onto the server’s Windows filesystem.
2. Open WSL2 and navigate to the repo directory.
3. Ensure Docker is installed and running inside WSL2.

### Install systemd backup automation
`chmod +x infra/install-units.sh`  
`bash infra/install-units.sh`

### Start the Bedrock server
`docker compose -f infra/docker-compose.yml up -d`

Backups will now run automatically every night at 3 AM, with retention limited to the last 3 daily backups plus one weekly backup.

## Backup Retention Policy

The backup system keeps:  
- The newest 3 daily backups  
- One weekly backup older than 7 days  
- A maximum of 4 backups total  

This ensures consistent restore points without consuming excessive storage.

## Redeployment

To redeploy the server after updates:  
`chmod +x infra/deploy.sh`  
`bash infra/deploy.sh`

This pulls the latest Bedrock image, restarts the container, and reapplies gamerules.

## Log Viewing

To view logs interactively:  
`chmod +x infra/logviewer.sh`  
`bash infra/logviewer.sh`

Options include Bedrock logs, backup folder contents, systemd backup logs, and live docker log tailing.

## Health Check

To verify server status, backup automation, and system health:  
`chmod +x infra/healthcheck.sh`  
`bash infra/healthcheck.sh`

This provides a full operational report.

## Restore Instructions

To restore a backup:  
`chmod +x infra/restore.sh`  
`bash infra/restore.sh`

Select a backup folder, and the script will stop the container, replace the world data, and restart the server.

## Notes

All systemd units must be installed using `install-units.sh` because systemd only loads units from `/etc/systemd/system/`. Keeping the unit files in the repo ensures full version control and easy redeployment.


## dos2unix

dos2unix infra/*.sh
dos2unix infra/*.service
dos2unix infra/*.timer


## dashboard
chmod +x infra/dashboard.sh
bash infra/dashboard.sh


Alias
echo "alias mc-dashboard='bash ~/MinecraftServer/minecraftServer/infra/dashboard.sh'" >> ~/.bashrc
source ~/.bashrc

mc-dashboard

launch_dashboard.bat
wsl -d Ubuntu bash -c "cd /mnt/c/Users/dante/MinecraftServer/minecraftServer/infra && bash dashboard.sh"
pause

## Playit.gg
curl -L https://playit-cloud.github.io/cli/playit-linux-amd64 -o playit
chmod +x playit
./playit
