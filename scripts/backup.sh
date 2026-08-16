#!/bin/sh

# Configuration mapped from Docker environment variables
REMOTE_NAME="${CLOUD_REMOTE_NAME:-mycloud}"
DEST_PATH="${CLOUD_DEST_PATH:-/backups}"
RETENTION="${RETENTION_WEEKS:-6}"
SOURCE_DIR="/data"
# Determine the VM_NAME.
# 1. First, check if a specific VM_NAME env var is provided (for overrides)
# 2. Next, check if we mounted the host's hostname (true host name)
# 3. Finally, fallback to the container's HOSTNAME or hostname command
if [ -n "$VM_NAME" ]; then
    : # Keep VM_NAME
elif [ -f "/etc/host_hostname" ]; then
    VM_NAME=$(cat /etc/host_hostname | tr -d '\n')
else
    VM_NAME="${HOSTNAME}"
    if [ -z "$VM_NAME" ]; then
        VM_NAME=$(hostname)
    fi
fi

YEAR=$(date +%Y)
MONTH=$(date +%m)
# Strip leading zeros so it isn't treated as octal
DAY=$(date +%d | sed 's/^0*//')
WEEK=$(( (DAY - 1) / 7 + 1 ))
FOLDER_NAME="${YEAR}-${MONTH}-Wk${WEEK}"

BACKUP_DEST="${REMOTE_NAME}:${DEST_PATH}/${VM_NAME}/${FOLDER_NAME}"

# --- Email Alerting Function ---
send_email() {
    local subject="$1"
    local message="$2"
    
    if [ -n "$SMTP_URL" ] && [ -n "$SMTP_USER" ] && [ -n "$SMTP_TO" ]; then
        echo "Sending email: $subject"
        # Write to a temporary file to ensure the email format is strictly respected
        local tmp_mail="/tmp/mail.txt"
        echo "From: \"Rclone Backup\" <${SMTP_FROM}>" > "$tmp_mail"
        echo "To: \"${SMTP_TO}\"" >> "$tmp_mail"
        echo "Subject: ${subject}" >> "$tmp_mail"
        echo "" >> "$tmp_mail"
        echo "${message}" >> "$tmp_mail"
        
        curl -sS --ssl-reqd \
          --url "$SMTP_URL" \
          --user "$SMTP_USER:$SMTP_PASSWORD" \
          --mail-from "$SMTP_FROM" \
          --mail-rcpt "$SMTP_TO" \
          --upload-file "$tmp_mail" || echo "❌ Failed to send email (check docker logs for curl error)."
        
        rm -f "$tmp_mail"
    fi
}

# --- Docker Pausing / Unpausing ---
unpause_containers() {
    if [ -n "$CONTAINERS_TO_PAUSE" ]; then
        echo "[$(date)] Unpausing containers..."
        for container in $CONTAINERS_TO_PAUSE; do
            docker unpause "$container" >/dev/null 2>&1 || true
        done
    fi
}

# Ensure containers are always unpaused on script exit, interruption, or termination
trap unpause_containers EXIT INT TERM

if [ -n "$CONTAINERS_TO_PAUSE" ]; then
    echo "[$(date)] Pausing containers for application consistency..."
    for container in $CONTAINERS_TO_PAUSE; do
        docker pause "$container" || echo "Warning: Failed to pause $container"
    done
fi

# Find the most recent backup folder to use as a copy destination
LATEST_BACKUP=$(rclone lsf --dirs-only "${REMOTE_NAME}:${DEST_PATH}/${VM_NAME}" 2>/dev/null | sort -r | head -n 1 | sed 's|/$||')

echo "[$(date)] Starting backup for ${VM_NAME} to ${BACKUP_DEST}"

# Capture the exit code properly
SYNC_SUCCESS=0

if [ -n "$LATEST_BACKUP" ] && [ "$LATEST_BACKUP" != "$FOLDER_NAME" ]; then
    echo "[$(date)] Found previous week's backup: ${LATEST_BACKUP}. Using --copy-dest for server-side copying to save bandwidth!"
    rclone sync "$SOURCE_DIR" "$BACKUP_DEST" -v --transfers=4 --checkers=8 --fast-list --exclude-from /config/rclone/exclude.txt --copy-dest "${REMOTE_NAME}:${DEST_PATH}/${VM_NAME}/${LATEST_BACKUP}" || SYNC_SUCCESS=$?
else
    rclone sync "$SOURCE_DIR" "$BACKUP_DEST" -v --transfers=4 --checkers=8 --fast-list --exclude-from /config/rclone/exclude.txt || SYNC_SUCCESS=$?
fi

if [ $SYNC_SUCCESS -eq 0 ]; then
    echo "[$(date)] Backup completed successfully. Running retention policy..."
    
    rclone lsf --dirs-only "${REMOTE_NAME}:${DEST_PATH}/${VM_NAME}" | sort -r | tail -n +$((RETENTION + 1)) | while read -r OLD_FOLDER; do
        echo "[$(date)] Purging old backup: ${OLD_FOLDER}"
        rclone purge "${REMOTE_NAME}:${DEST_PATH}/${VM_NAME}/${OLD_FOLDER}" || echo "Warning: Failed to purge $OLD_FOLDER"
    done
    
    echo "[$(date)] All tasks finished successfully."
    send_email "✅ Backup Success: $VM_NAME" "The backup for $VM_NAME completed successfully at $(date)."
else
    echo "[$(date)] ❌ Backup FAILED with exit code $SYNC_SUCCESS. Skipping retention policy."
    send_email "❌ Backup Failed: $VM_NAME" "The backup for $VM_NAME failed with exit code $SYNC_SUCCESS at $(date). Please check the docker logs for more information."
    exit $SYNC_SUCCESS
fi