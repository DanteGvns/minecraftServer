# Minecraft Bedrock Server Infrastructure

This repository runs a Minecraft Bedrock server in Docker inside WSL2 on Windows 11 Pro. The Playit agent and systemd automation also run inside WSL2.

The server checkout currently lives at:

```text
/mnt/c/Users/dante/MinecraftServer/minecraftServer
```

The scripts derive their paths from the checkout, so the same repository can be installed under a different Windows user or directory.

## Architecture

- Windows 11 Pro hosts WSL2 and provides the Windows filesystem.
- Ubuntu WSL2 runs Docker, systemd, the Bedrock container, and the Playit agent.
- Docker Compose publishes Bedrock UDP port `19132`.
- `mc-backup.timer` runs the backup service daily.
- `playit-health.timer` checks the tunnel every minute and uses failure thresholds and restart cooldowns.
- World backups and pre-restore snapshots are stored below `infra/backups` by default.

World backups are runtime data and must not be committed to Git. The directory is ignored, but Git does not provide off-machine disaster recovery; copy backups to another disk or remote target separately.

Do not start the server from PowerShell in the repository. Enter WSL first, then run scripts with `bash`.

## First-Time Setup

From PowerShell:

```powershell
wsl.exe
```

From WSL:

```bash
cd /mnt/c/Users/dante/MinecraftServer/minecraftServer
cp .env.example infra/.env
nano infra/.env
```

Set `BEDROCK_VERSION` to the exact version currently deployed on the server. Read the current value from the running server before changing Compose. Do not use `LATEST` for a production world.

Install or verify Docker, Docker Compose, and systemd in WSL. The repository assumes `docker compose` (Compose v2), not only the legacy `docker-compose` command.

## Line Endings and Script Execution

`.gitattributes` forces shell scripts, systemd units, timers, Compose files, and documentation to use LF line endings. On the server, set Git not to rewrite these files after the first pull:

```bash
git config core.autocrlf false
git config core.eol lf
git pull --ff-only origin main
```

Scripts are intentionally run through Bash. You should no longer need to run `chmod +x` or `dos2unix` after every pull:

```bash
bash infra/healthcheck.sh
bash infra/dashboard.sh
bash infra/logviewer.sh
```

## Existing Server Migration

The server already has systemd units installed. Update them in place:

```bash
cd /mnt/c/Users/dante/MinecraftServer/minecraftServer
git pull --ff-only origin main
bash infra/install-units.sh
bash infra/install-playit-health.sh
```

The installers:

1. Detect the current repository directory.
2. Generate systemd service files with that directory embedded.
3. Use `ExecStart=/bin/bash`, so executable permissions on `/mnt/c` are not required.
4. Run `systemctl daemon-reload`.
5. Keep the existing unit names.
6. Enable and restart the timers without starting a backup immediately.

Verify the migration:

```bash
systemctl cat mc-backup.service
systemctl cat playit-health.service
systemctl list-timers --all | grep -E 'mc-backup|playit-health'
systemctl status mc-backup.timer playit-health.timer --no-pager
```

A running backup does not need to be deleted and recreated. If systemd reports a backup currently in progress, wait for it to finish before reinstalling the unit.

## Start and Update

After `infra/.env` contains the current pinned version:

```bash
bash infra/deploy.sh
```

Deployment creates a backup first, pulls the pinned image, starts the container, and waits for the image's built-in `mc-monitor` to receive a Bedrock UDP status response. It records the result in `infra/update-history.log` by default and does not apply gamerules automatically.

On a true first deployment, where no valid world exists yet, deployment skips the pre-update backup. If the container was removed but its Compose volume remains, deployment discovers that volume and creates an offline backup before continuing. A shared advisory lock prevents backup, restore, and deployment from modifying the world concurrently.

If readiness times out, deployment recreates the container with the previous image and Bedrock version and verifies that rollback with the same UDP probe. The command still exits nonzero after a successful rollback so the failed update cannot be mistaken for success. The pre-update backup remains available if automated rollback also fails.

## Backups

Run a manual backup with:

```bash
bash infra/backup.sh
```

The backup process:

- Holds Bedrock saving.
- Records a log timestamp, issues `save hold`, and polls with `save query`.
- Copies only after a new container-log response says the data is ready to be copied. The accepted response can be overridden with `MC_SAVE_QUERY_PATTERN` if Bedrock changes its wording.
- Resolves the active Docker volume from the container's `/data` mount.
- Copies into an in-progress directory.
- Publishes the timestamped backup only after the copy succeeds.
- Always attempts `save resume`, including when the copy fails.
- Removes incomplete temporary backups.
- Validates that `level.dat` and a nonempty world database exist before publishing the backup or applying retention.

Older installations may have the previous `MC_SAVE_QUERY_PATTERN` value in `infra/.env`. The backup script ignores that unsafe legacy value, but update the file to match `.env.example` so the runtime configuration is unambiguous.

The nightly service is installed by `bash infra/install-units.sh` and runs at 3 AM according to `mc-backup.timer`. The timer is persistent, so a run missed while WSL was stopped is replayed after WSL starts. The installer records the migration time before enabling the timer, so reinstalling the units does not itself trigger a catch-up backup.

## Restore and Undo

Run the interactive restore utility during a maintenance window:

```bash
bash infra/restore.sh
```

Before replacing the live world, it validates the backup and creates a copy under:

```text
infra/backups/prerestored/world_<timestamp>
```

The latest five pre-restore snapshots are retained. The selected backup and pre-restore snapshot must both contain `level.dat` and a nonempty database. If the container was running, restore waits for a Bedrock UDP response and automatically puts the original world back if the restored world does not become ready. Interruptions during the directory swap also put the original world back. Pre-restore snapshots appear in the restore menu under `prerestored/`, so undoing a restore uses the same command.

Always verify the selected backup and have a current backup before restoring.

## Health Check and Dashboard

```bash
bash infra/healthcheck.sh
echo $?
bash infra/dashboard.sh
```

The health check returns zero only when required checks pass. It checks Docker, the container, a real Bedrock UDP status response, UDP port publication, backup timer state, the last one-shot backup result, backup age, and disk usage.

The dashboard obtains current and maximum player counts from the same Bedrock UDP status response. It reports `unknown` when the server cannot be queried. A successful one-shot backup service is reported by its last result even though the service is normally inactive between runs.

## Playit Health

The Playit health timer is installed with:

```bash
bash infra/install-playit-health.sh
```

A connected tunnel with zero traffic is healthy. The health check accepts common connected and forwarding states, requires repeated unhealthy results before restarting Playit, and applies a restart cooldown to prevent loops.

Useful commands:

```bash
systemctl status playit playit-health.timer --no-pager
journalctl -u playit-health.service --no-pager
```

## Gamerules

Gamerule policy is intentionally not enforced during deployment yet. Edit and run `infra/gamerules.sh` only after deciding the desired settings with the server players. Keep the desired values in that one script so they are easy to change.

## Logs

```bash
bash infra/logviewer.sh
journalctl -u mc-backup.service --no-pager
journalctl -u playit-health.service --no-pager
docker logs "${MC_CONTAINER_NAME:-bedrock}"
```

## Windows Remote Access

Keep Remote Desktop Network Level Authentication enabled. Restrict RDP through Windows Firewall and the trusted Tailscale interface or subnet. Do not expose RDP broadly to the public network.

## Configuration

Runtime values are loaded from `infra/.env`; explicitly exported environment variables take precedence. Important values include:

- `BEDROCK_VERSION`: required exact Bedrock version.
- `COMPOSE_PROJECT_NAME`: defaults to `infra`.
- `MC_BACKUP_DIR`: backup location.
- `MC_PRERESTORE_DIR`: pre-restore snapshot location.
- `MC_BACKUP_MAX_AGE_HOURS`: health-check backup age limit.
- `MC_BACKUP_RETENTION`: number of completed normal backups to retain; defaults to four.
- `MC_SAVE_QUERY_PATTERN`: case-insensitive pattern for a successful, new `save query` response in container logs.
- `MC_DISK_MAX_USED_PERCENT`: health-check disk threshold.
- `MC_SERVER_PORT`: Bedrock container and published UDP port checked by `mc-monitor`; defaults to `19132`.
- `MC_STATUS_TIMEOUT_SECONDS`: maximum duration of one Bedrock UDP status attempt; defaults to 5 seconds.
- `MC_READY_TIMEOUT_SECONDS`: deployment and rollback readiness timeout; defaults to 120 seconds.
- `MC_RESTORE_READY_TIMEOUT_SECONDS`: restored-world and rollback readiness timeout; defaults to 120 seconds.
- `MC_OPERATION_LOCK_FILE`: advisory lock shared by backup, restore, and deploy; defaults below `infra/backups`.
- `PLAYIT_FAILURE_THRESHOLD`: unhealthy checks before restart.
- `PLAYIT_RESTART_COOLDOWN_SECONDS`: minimum interval between Playit restarts.

The Playit health service loads the same `infra/.env` file as the Minecraft utilities. Numeric configuration is validated before an operation begins.

The world backups removed from the current Git tree remain in earlier commits. If the repository has been shared or could become public, rewrite its history with `git filter-repo` and coordinate the resulting force-push with every clone; deleting current files alone does not erase historical world data.

The root `minecraftBedrockSeverPlan.md` is retained as historical planning material. `setServerCommands.md` is a first-time Windows/WSL setup runbook. This README is the operational reference.
