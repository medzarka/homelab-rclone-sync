#!/bin/sh

# Default cron to daily if not provided
BACKUP_CRON=${BACKUP_CRON:-"0 2 * * *"}

echo "[$(date)] Starting rclone backup service..."

# Install curl and docker-cli if missing on startup
if ! command -v curl >/dev/null 2>&1 || ! command -v docker >/dev/null 2>&1; then
    echo "[$(date)] 📦 Installing required runtime dependencies (curl, docker-cli)..."
    apk add --no-cache curl docker-cli >/dev/null 2>&1 || echo "Warning: Failed to install apk packages"
fi

# Create config directory
mkdir -p /config/rclone

# Inject rclone config from base64 environment variable
if [ -n "$RCLONE_CONF_BASE64" ]; then
    echo "[$(date)] Injecting rclone config from RCLONE_CONF_BASE64 variable..."
    echo "$RCLONE_CONF_BASE64" | base64 -d > /config/rclone/rclone.conf
    [ -n "$RCLONE_CONFIG_PASS" ] && echo "[$(date)] 🔐 RCLONE_CONFIG_PASS detected for encrypted rclone.conf."
else
    echo "[$(date)] WARNING: RCLONE_CONF_BASE64 is empty. Rclone may not be able to connect."
fi

# Check exclude configuration
if [ -f "/config/rclone/exclude.txt" ] && [ ! -d "/config/rclone/exclude.txt" ] && [ -s "/config/rclone/exclude.txt" ]; then
    echo "[$(date)] 📄 Detected custom exclude rules file at /config/rclone/exclude.txt."
else
    echo "[$(date)] ℹ️ Using default built-in exclude rules."
fi

echo "[$(date)] Setting up cron schedule: ${BACKUP_CRON}"

# Set the cron schedule
echo "${BACKUP_CRON} /scripts/backup.sh" > /etc/crontabs/root

# Run the cron daemon in the foreground, logging to stderr
exec crond -f -l 2
