# Windows + WSL2 Home Lab + Minecraft Bedrock DevOps Setup Plan

Install Windows updates and install Windows Terminal from the Microsoft Store.

Install WSL2 using the modern unified installer:
wsl --install

Create a desktop shortcut to open wsl
# Get the default WSL distro name
$distro = (wsl -l -v | Select-String "\*" | ForEach-Object {
    ($_ -split "\s+")[1]
})

# Build the shortcut path using the distro name
$ShortcutPath = "$env:USERPROFILE\Desktop\$distro WSL.lnk"

# Create the shortcut
$WScriptShell = New-Object -ComObject WScript.Shell
$Shortcut = $WScriptShell.CreateShortcut($ShortcutPath)
$Shortcut.TargetPath = "C:\Windows\System32\wsl.exe"
$Shortcut.Arguments = "-d $distro ~"
$Shortcut.IconLocation = "C:\Windows\System32\wsl.exe"
$Shortcut.Save()

Reboot if prompted.

Launch Ubuntu from the Start Menu and create your Linux user.

Update the Linux system:
sudo apt update && sudo apt upgrade -y

Install essential packages:
sudo apt install git curl wget unzip -y

Enable systemd inside WSL2 by editing /etc/wsl.conf:
[boot]
systemd=true

Shutdown WSL:
wsl --shutdown

Restart Ubuntu.

Install Docker inside WSL2:
sudo apt install docker.io docker-compose -y
sudo systemctl enable docker
sudo systemctl start docker

Add your user to the docker group:
sudo usermod -aG docker $USER

Shutdown WSL again:
wsl --shutdown

Verify Docker:
docker run hello-world

Optional home lab tools:
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up
sudo apt install rclone -y

Create your infrastructure repository structure:
/infra
  bootstrap.sh
  deploy.sh
  docker-compose.yml
  backup.sh
  gamerules.sh
  logs/
  README.md

bootstrap.sh:
#!/bin/bash
sudo apt update && sudo apt upgrade -y
sudo apt install docker.io docker-compose git rclone -y
sudo systemctl enable docker
sudo systemctl start docker
mkdir -p ~/mc/logs

docker-compose.yml:
version: "3.8"
services:
  bedrock:
    image: itzg/minecraft-bedrock-server
    container_name: bedrock
    ports:
      - "19132:19132/udp"
    environment:
      EULA: "TRUE"
      VERSION: "LATEST"
    volumes:
      - bedrock_data:/data
    restart: unless-stopped
volumes:
  bedrock_data:

deploy.sh:
#!/bin/bash
docker compose pull
docker compose up -d
sleep 10
./gamerules.sh

gamerules.sh:
#!/bin/bash
docker exec bedrock send-command "gamerule showcoordinates true"
docker exec bedrock send-command "gamerule keepinventory true"
docker exec bedrock send-command "gamerule dofiretick false"

backup.sh:
#!/bin/bash
timestamp=$(date +"%Y-%m-%d_%H-%M-%S")
docker exec bedrock send-command "save hold"
sleep 5
docker exec bedrock send-command "save query"
sleep 5
cp -r /var/lib/docker/volumes/bedrock_data/_data ~/mc/backups/world_$timestamp
docker exec bedrock send-command "save resume"

Optional cloud upload:
rclone copy ~/mc/backups remote:mc-backups

systemd backup timer (/etc/systemd/system/mc-backup.timer):
[Unit]
Description=Minecraft Backup Timer
[Timer]
OnCalendar=*-*-* 03:00:00
[Install]
WantedBy=timers.target

systemd backup service (/etc/systemd/system/mc-backup.service):
[Unit]
Description=Minecraft Backup Service
[Service]
Type=oneshot
ExecStart=/home/<user>/infra/backup.sh

Enable timers:
sudo systemctl enable mc-backup.timer
sudo systemctl start mc-backup.timer

CI/CD deploy command for GitHub Actions:
docker compose pull && docker compose up -d

Logs:
docker logs -f bedrock

Monitoring:
docker exec bedrock mc-monitor status

Final architecture:
Windows host, WSL2 Ubuntu runtime, Docker inside WSL2, Bedrock server container, systemd automation, GitHub Actions CI/CD, rclone backups, Tailscale remote access, Docker logs, mc-monitor health checks.