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
4. (Optional) Do the same for any exclude patterns in the `EXCLUDE_TXT_BASE64` variable in the `.env` file.
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

## 3. Remote Deployment with Dockhand (Building the Image)

Since this project now uses a custom Docker image to bundle the scripts directly (avoiding tricky bind-mount errors on remote VPSs), you need to build and push the image to a registry before deploying it via Dockhand.

1. **Build the image locally:**
   ```bash
   docker-compose build
   ```
2. **Push the image to your registry:**
   Assuming you are using Docker Hub with your GitHub username, push the image:
   ```bash
   docker push medzarka/homelab-rclone-sync:latest
   ```
3. **Deploy via Dockhand:**
   Now, Dockhand can simply pull this image on any VPS. 
   *(Since we inject the configuration via the `.env` file, this deployment is 100% self-contained. You do not need to manually copy any configuration files to the remote servers!)*

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
