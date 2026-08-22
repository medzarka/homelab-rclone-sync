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
    [ -n "$RCLONE_CONFIG_PASS" ] && echo "[$(date)] 🔐 RCLONE_CONFIG_PASS detected for encrypted rclone.conf."
else
    echo "[$(date)] WARNING: RCLONE_CONF_BASE64 is empty. Rclone may not be able to connect."
fi

# Set up exclude rules
if [ -f "/config/rclone/exclude.txt" ] && [ -s "/config/rclone/exclude.txt" ]; then
    echo "[$(date)] 📄 Using custom exclude rules from mounted exclude.txt."
elif [ -n "$EXCLUDE_TXT_BASE64" ]; then
    echo "[$(date)] Injecting exclude rules from EXCLUDE_TXT_BASE64 variable..."
    echo "$EXCLUDE_TXT_BASE64" | base64 -d > /config/rclone/exclude.txt
elif [ -f "/scripts/exclude.txt.sample" ]; then
    echo "[$(date)] ℹ️ No custom exclude.txt provided. Applying default rules from exclude.txt.sample."
    cp /scripts/exclude.txt.sample /config/rclone/exclude.txt
else
    touch /config/rclone/exclude.txt
fi

echo "[$(date)] Setting up cron schedule: ${BACKUP_CRON}"

# Set the cron schedule
echo "${BACKUP_CRON} /scripts/backup.sh" > /etc/crontabs/root

# Run the cron daemon in the foreground, logging to stderr
exec crond -f -l 2
