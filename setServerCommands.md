# Windows and WSL Server Setup Notes

This is a setup runbook, not an executable script. Run each command in the shell named by its section and replace placeholder paths before use.

## Windows PowerShell as Administrator

Install Tailscale, Git, GitHub Desktop, WSL, and the Windows OpenSSH server:

```powershell
winget install --id Tailscale.Tailscale -e --source winget
winget install --id Git.Git -e --source winget
winget install --id GitHub.GitHubDesktop -e --source winget

Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
Start-Service sshd
Set-Service -Name sshd -StartupType Automatic

wsl.exe --install -d Ubuntu
```

Restart Windows after WSL installation. Keep Remote Desktop Network Level Authentication enabled and restrict RDP and SSH to Tailscale or another trusted network.

## Enable systemd in Ubuntu

Open Ubuntu with `wsl.exe -d Ubuntu`, then create `/etc/wsl.conf`:

```ini
[boot]
systemd=true
```

Back in PowerShell, restart WSL:

```powershell
wsl.exe --shutdown
```

## Ubuntu WSL

Clone the repository onto the Windows filesystem, then run its bootstrap script from Ubuntu:

```bash
cd /mnt/c/Users/<ServerUser>/Documents/GitHub
git clone https://github.com/<your-username>/minecraftServer.git
cd minecraftServer
bash infra/bootstrap.sh
```

Close and reopen WSL after bootstrap so Docker group membership takes effect. Continue with the first-time setup in `README.md`.

## Remote access

From another trusted machine, use the server's Tailscale address:

```text
ssh "computername\account"@tailscale-ip-address
```

For Remote Desktop, open `mstsc.exe` and connect to the same trusted address.