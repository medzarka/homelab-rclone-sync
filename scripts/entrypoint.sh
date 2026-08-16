#!/bin/sh

# Default cron to daily if not provided
BACKUP_CRON=${BACKUP_CRON:-"0 2 * * *"}

echo "[$(date)] Starting rclone backup service..."
echo "[$(date)] Setting up cron schedule: ${BACKUP_CRON}"

# Set the cron schedule
echo "${BACKUP_CRON} /scripts/backup.sh" > /etc/crontabs/root

# Run the cron daemon in the foreground, logging to stderr
exec crond -f -l 2
