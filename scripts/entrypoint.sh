#!/bin/sh

# Default cron to daily if not provided
BACKUP_CRON=${BACKUP_CRON:-"0 2 * * *"}

echo "[$(date)] Starting rclone backup service..."

# Create config directory
mkdir -p /config/rclone

# Inject rclone config from base64 environment variable
if [ -n "$RCLONE_CONF_BASE64" ]; then
    echo "[$(date)] Injecting rclone config from RCLONE_CONF_BASE64 variable..."
    echo "$RCLONE_CONF_BASE64" | base64 -d > /config/rclone/rclone.conf
else
    echo "[$(date)] WARNING: RCLONE_CONF_BASE64 is empty. Rclone may not be able to connect."
fi

# Inject exclude rules from base64 environment variable
if [ -n "$EXCLUDE_TXT_BASE64" ]; then
    echo "[$(date)] Injecting exclude rules from EXCLUDE_TXT_BASE64 variable..."
    echo "$EXCLUDE_TXT_BASE64" | base64 -d > /config/rclone/exclude.txt
else
    echo "[$(date)] No EXCLUDE_TXT_BASE64 provided. Creating an empty exclude file."
    touch /config/rclone/exclude.txt
fi

echo "[$(date)] Setting up cron schedule: ${BACKUP_CRON}"

# Set the cron schedule
echo "${BACKUP_CRON} /scripts/backup.sh" > /etc/crontabs/root

# Run the cron daemon in the foreground, logging to stderr
exec crond -f -l 2
