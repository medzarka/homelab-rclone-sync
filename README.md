# Homelab Rclone Sync

A fully automated, Dockerized backup solution using Rclone to back up a homelab directory to a cloud provider. It includes bandwidth-saving server-side copies, email alerting, advanced error handling, and the ability to pause specific Docker containers during the backup to ensure application consistency.

## Prerequisites

- **Docker** and **Docker Compose** installed on your host system.
- An **SMTP account** if you want email alerts (e.g., a Gmail App Password, SendGrid, etc.).
- A cloud storage remote configured in `rclone`.

## 1. Initial Setup

1. Copy `.env.example` to `.env`:
   ```bash
   cp .env.example .env
   ```
2. Open `.env` and fill in all the variables.
3. **Rclone Configuration:** Dockhand has trouble parsing multi-line text variables. Convert your `rclone.conf` file to a single-line Base64 string locally (`cat rclone.conf | base64 -w 0`) and paste it into the `RCLONE_CONF_BASE64` variable in the `.env` file.
4. **Exclude Rules:** Copy `exclude.txt.sample` to `exclude.txt`:
   ```bash
   cp exclude.txt.sample exclude.txt
   ```
   Add or modify any patterns you wish to exclude (e.g. `node_modules`, `venv`, logs, cache). `exclude.txt` is mounted directly into the container and ignored by Git.
5. Review the backup logic in `scripts/backup.sh`.

## 2. Important Configuration Options

### Application Consistency (Container Pausing)
If you are backing up databases (like PostgreSQL, MySQL) or apps that constantly write to disk, you risk getting a corrupted backup if they write a file while rclone is syncing it.

> [!TIP]
> You can pause containers during the backup by listing their names in the `.env` file under `CONTAINERS_TO_PAUSE`.
> Example: `CONTAINERS_TO_PAUSE="nextcloud-db plex"`

The script will automatically run `docker pause <name>` before the sync, and `docker unpause <name>` right after. If the backup crashes for any reason, the script's `trap` mechanism guarantees the containers will be unpaused before the script exits.

### Email Alerts & Notification Policies
Control when emails are sent via `EMAIL_NOTIFY_MODE` in `.env`:

| Policy | Behavior | Best Used For |
| :--- | :--- | :--- |
| **`on_failure`** *(Default)* | Sends email **only** when a backup fails or encounters errors. | **Recommended**: Eliminates daily inbox clutter while keeping you alerted to issues. |
| **`weekly`** | Sends on errors + one full summary report every Sunday. | Weekly digest overview of backup health. |
| **`always`** | Sends an email report after every single backup run. | Strict auditing / initial setup verification. |
| **`never`** | Completely disables email alerts. | Relying exclusively on Dozzle, Beszel, and Uptime Kuma. |

> [!IMPORTANT]
> - `SMTP_URL` must include the protocol (e.g., `smtps://` for port 465, or `smtp://` for port 587).
> - Example: `SMTP_URL="smtps://smtp.gmail.com:465"`
> - Use an App Password (not your main password) if using Gmail!

### Deep Telemetry & Storage Insights
Every backup run logs a structured summary report to standard output (viewable directly in Dozzle at `https://logs.example.com`):

```text
======================================================================
📊 BACKUP REPORT: my_server (2026-08-22 19:20:00 UTC)
======================================================================
Status:            ✅ SUCCESS
Execution Time:    2m 14s (134s)
Target Snapshot:   mycloud:/backups/my_server/2026-08-Wk4
Notification Mode: on_failure

📦 Transfer Statistics:
  • Data Transferred:   1.42 GiB
  • Files Transferred:  84 / 84
  • Files Checked:      12,450 / 12,450
  • Files Deleted:      4
  • Error Count:        0

💾 Storage & Quota Insights:
  • Local Source Size:  45.8 GiB (/data)
  • Host Disk Usage:    52% used (142 GiB free of 298 GiB)
  • Cloud Snapshot:     Total objects: 12450, Total size: 45.8 GiB
  • Cloud Remote Quota: 1.25 TiB used | 750 GiB free | 2.00 TiB total

🗑️ Retention Policy (4 Weeks):
  • Purged Snapshots:   None (within retention window)
======================================================================
```

### Bandwidth Saving (`--copy-dest`)
The script is configured to look at the previous week's backup folder. When the week rolls over and a new folder is created, it tells your cloud provider to perform a **server-side copy** of unchanged files instead of uploading them from your home internet again.

## 3. Remote Deployment with Arcane / GitOps

This stack uses the official `rclone/rclone:latest` image directly from Docker Hub and mounts scripts automatically. No custom image building or Docker registry login is required!

1. Open **Arcane Cockpit** (`https://arcane.example.com`).
2. Click **Projects** $\rightarrow$ **New Project**.
3. Set:
   * **Name:** `backup-sync`
   * **Git Repository:** `https://github.com/medzarka/homelab-rclone-sync.git`
   * **Branch:** `main`
4. Provide the `.env` variables from `.env.example`.
5. Click **Deploy**. Arcane will pull the official Rclone image and start the backup daemon automatically.

## 4. Local Usage

If you are running this on your local machine, simply start the service in the background. It will build automatically:
```bash
docker-compose up -d --build
```

Check the logs to see if it scheduled correctly:
```bash
docker logs -f homelab_rclone_sync
```

To run a backup manually immediately (for testing):
```bash
docker exec homelab_rclone_sync /scripts/backup.sh
```

## 5. Troubleshooting & Error Handling

- **Containers won't pause?** Ensure the `homelab_rclone_sync` container has access to `/var/run/docker.sock` (this is configured in `docker-compose.yaml` by default).
- **Emails aren't sending?** Check your SMTP URL and credentials. Some providers require `smtps://` while others expect `smtp://`.
- **Rclone errors?** Check the output logs for the container. The script includes advanced error handling that will stop the retention policy (deletions) from running if the main sync fails, keeping your old backups safe.
- **Error: `"/scripts/backup.sh": is a directory: permission denied`?** This is a classic Docker gotcha. If you copied `docker-compose.yaml` to a new server but forgot to copy the actual `scripts/backup.sh` file, Docker assumes you wanted to mount a directory and automatically creates an empty folder named `backup.sh`. To fix this: run `sudo rm -rf scripts/backup.sh`, copy the actual script file over to your server, and recreate the container.

> [!WARNING]
> Keep your `.env` file secure, as it now contains the access tokens to your cloud storage!
