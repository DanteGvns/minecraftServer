#Set up commands for the Server

#Install Tailscaile
winget install Tailscale.Tailscale --winget

#Install SSH server
Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
Start-Service sshd
Set-Service -Name sshd -StartupType 'Automatic'
#connect from another machine
#ssh ssh -l "computername\account" tailscale-ip-address

Install RDP stuff
turn on remote desktop windows 11 pro
turn off network level authentication

#connect from another machine 
windows + R  mstsc

#restart tailscale on restart
set tailscale to automatic delayed start
$Action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-File C:\Scripts\fix-tailscale.ps1"
$Trigger = New-ScheduledTaskTrigger -AtStartup
$Principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -RunLevel Highest
Register-ScheduledTask -TaskName "FixTailscaleStartup" -Action $Action -Trigger $Trigger -Principal $Principal


Install WSL
wsl --install ubuntu

#Restart the computer

#Create a shortcut to launch Ubuntu WSL from the desktop
$Desktop = [Environment]::GetFolderPath("Desktop")
$ShortcutPath = Join-Path $Desktop "Ubuntu WSL.lnk"

$WScriptShell = New-Object -ComObject WScript.Shell
$Shortcut = $WScriptShell.CreateShortcut($ShortcutPath)
$Shortcut.TargetPath = "C:\Windows\System32\wsl.exe"
$Shortcut.Arguments = "-d Ubuntu ~"
$Shortcut.IconLocation = "C:\Windows\System32\wsl.exe"
$Shortcut.Save()

#update and upgrade packages in Ubuntu WSL
sudo apt update && sudo apt upgrade -y
sudo apt install git curl wget unzip -y

#Install Git (PowerShell command)
winget install --id Git.Git -e --source winget
#Install GitHub Desktop (PowerShell command)
winget install --id GitHub.GitHubDesktop -e --source winget
#Clone repo onto the server’s Windows filesystem
cd C:\Users\<ServerUser>\Documents\
cd C:\Users\dante\MinecraftServer
git clone https://github.com/<your-username>/<your-repo>.git

#Access the repo from WSL2
cd /mnt/c/Users/<ServerUser>/Documents/<your-repo>
cd /mnt/c/Users/dante/MinecraftServer

#Enable systemd inside WSL2
sudo nano /etc/wsl.conf
    [boot]
    systemd=true
Save → exit.
wsl --shutdown
#Reopen Ubuntu

#Install Docker inside WSL2
sudo apt install docker.io docker-compose -y
sudo systemctl enable docker
sudo systemctl start docker

#include user to the docker group
sudo usermod -aG docker $USER
wsl --shutdown
#Reopen Ubuntu and verify
docker run hello-world