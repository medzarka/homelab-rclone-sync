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
3. Replace the placeholder in `config/rclone.conf` with your actual rclone remote configuration. You can generate one on your local machine by running `rclone config` and pasting the result here.

> [!WARNING]
> You **must** edit the `config/rclone.conf` file and provide valid cloud credentials *before* starting the rclone container with `docker-compose up`. If the configuration is missing or invalid, the backups will immediately fail.
4. (Optional) Add patterns to `config/exclude.txt` for files and folders you want to ignore.
5. Review the backup logic in `scripts/backup.sh`.

## 2. Important Configuration Options

### Application Consistency (Container Pausing)
If you are backing up databases (like PostgreSQL, MySQL) or apps that constantly write to disk, you risk getting a corrupted backup if they write a file while rclone is syncing it.

> [!TIP]
> You can pause containers during the backup by listing their names in the `.env` file under `CONTAINERS_TO_PAUSE`.
> Example: `CONTAINERS_TO_PAUSE="nextcloud-db plex"`

The script will automatically run `docker pause <name>` before the sync, and `docker unpause <name>` right after. If the backup crashes for any reason, the script's `trap` mechanism guarantees the containers will be unpaused before the script exits.

### Email Alerts
To receive emails when a backup succeeds or fails, configure the SMTP settings in the `.env` file.

> [!IMPORTANT]
> - `SMTP_URL` must include the protocol (e.g., `smtps://` for port 465, or `smtp://` for port 587).
> - Example: `SMTP_URL="smtps://smtp.gmail.com:465"`
> - Use an App Password (not your main password) if using Gmail!

### Bandwidth Saving (`--copy-dest`)
The script is configured to look at the previous week's backup folder. When the week rolls over and a new folder is created, it tells your cloud provider to perform a **server-side copy** of unchanged files instead of uploading them from your home internet again.

## 3. Usage

Start the backup service in the background:
```bash
docker-compose up -d
```

Check the logs to see if it scheduled correctly:
```bash
docker logs -f homelab_rclone_sync
```

To run a backup manually immediately (for testing):
```bash
docker exec homelab_rclone_sync /scripts/backup.sh
```

## 4. Troubleshooting & Error Handling

- **Containers won't pause?** Ensure the `homelab_rclone_sync` container has access to `/var/run/docker.sock` (this is configured in `docker-compose.yaml` by default).
- **Emails aren't sending?** Check your SMTP URL and credentials. Some providers require `smtps://` while others expect `smtp://`.
- **Rclone errors?** Check the output logs for the container. The script includes advanced error handling that will stop the retention policy (deletions) from running if the main sync fails, keeping your old backups safe.

> [!WARNING]
> Keep your `rclone.conf` file secure, as it contains the access tokens to your cloud storage!
