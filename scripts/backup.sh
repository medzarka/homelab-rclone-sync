#!/bin/sh
# ==============================================================================
# Enhanced Homelab Rclone Backup & Telemetry Runner
# ==============================================================================

START_EPOCH=$(date +%s)
START_DATE=$(date "+%Y-%m-%d %H:%M:%S %Z")

# Configuration mapped from Docker environment variables
REMOTE_NAME="${CLOUD_REMOTE_NAME:-mycloud}"
DEST_PATH="${CLOUD_DEST_PATH:-/backups}"
RETENTION="${RETENTION_WEEKS:-4}"
SOURCE_DIR="/data"
NOTIFY_POLICY=$(echo "${EMAIL_NOTIFY_MODE:-on_failure}" | tr '[:upper:]' '[:lower:]' | tr -d ' ')

# Determine VM_NAME (hostname identification)
if [ -n "$VM_NAME" ]; then
    : # Keep explicit VM_NAME
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
DAY=$(date +%d | sed 's/^0*//')
WEEK=$(( (DAY - 1) / 7 + 1 ))
FOLDER_NAME="${YEAR}-${MONTH}-Wk${WEEK}"
BACKUP_DEST="${REMOTE_NAME}:${DEST_PATH}/${VM_NAME}/${FOLDER_NAME}"

# --- Email Alerting Function ---
send_email() {
    local subject="$1"
    local message="$2"
    
    if [ -n "$SMTP_URL" ] && [ -n "$SMTP_USER" ] && [ -n "$SMTP_TO" ]; then
        echo "[$(date)] 📧 Dispatching email alert: $subject"
        local tmp_mail="/tmp/mail.txt"
        echo "From: \"Rclone Backup (${VM_NAME})\" <${SMTP_FROM:-${SMTP_USER}}>" > "$tmp_mail"
        echo "To: \"${SMTP_TO}\"" >> "$tmp_mail"
        echo "Subject: ${subject}" >> "$tmp_mail"
        echo "MIME-Version: 1.0" >> "$tmp_mail"
        echo "Content-Type: text/plain; charset=UTF-8" >> "$tmp_mail"
        echo "" >> "$tmp_mail"
        echo "${message}" >> "$tmp_mail"
        
        curl -sS --ssl-reqd \
          --url "$SMTP_URL" \
          --user "$SMTP_USER:$SMTP_PASSWORD" \
          --mail-from "${SMTP_FROM:-${SMTP_USER}}" \
          --mail-rcpt "$SMTP_TO" \
          --upload-file "$tmp_mail" || echo "❌ Failed to send email (check SMTP credentials / logs)."
        
        rm -f "$tmp_mail"
    else
        echo "[$(date)] ℹ️ SMTP not fully configured (SMTP_URL/USER/TO). Skipping email dispatch."
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

trap unpause_containers EXIT INT TERM

if [ -n "$CONTAINERS_TO_PAUSE" ]; then
    echo "[$(date)] Pausing containers for application consistency: ${CONTAINERS_TO_PAUSE}"
    for container in $CONTAINERS_TO_PAUSE; do
        docker pause "$container" >/dev/null 2>&1 || echo "Warning: Failed to pause $container"
    done
fi

# Find the most recent backup folder to use as a copy destination
LATEST_BACKUP=$(rclone lsf --dirs-only "${REMOTE_NAME}:${DEST_PATH}/${VM_NAME}" 2>/dev/null | sort -r | head -n 1 | sed 's|/$||')

echo "[$(date)] ======================================================================"
echo "[$(date)] 🚀 STARTING BACKUP FOR ${VM_NAME} -> ${BACKUP_DEST}"
echo "[$(date)] ======================================================================"

SYNC_LOG="/tmp/rclone_sync.log"
rm -f "$SYNC_LOG"
SYNC_SUCCESS=0

# Execute Rclone Sync
if [ -n "$LATEST_BACKUP" ] && [ "$LATEST_BACKUP" != "$FOLDER_NAME" ]; then
    echo "[$(date)] ⚡ Previous week found: ${LATEST_BACKUP}. Utilizing server-side --copy-dest to save bandwidth!"
    rclone sync "$SOURCE_DIR" "$BACKUP_DEST" \
      --verbose \
      --stats 5s \
      --transfers=4 \
      --checkers=8 \
      --tpslimit=5 \
      --timeout=5m \
      --fast-list \
      --exclude-from /config/rclone/exclude.txt \
      --copy-dest "${REMOTE_NAME}:${DEST_PATH}/${VM_NAME}/${LATEST_BACKUP}" \
      > "$SYNC_LOG" 2>&1 || SYNC_SUCCESS=$?
else
    rclone sync "$SOURCE_DIR" "$BACKUP_DEST" \
      --verbose \
      --stats 5s \
      --transfers=4 \
      --checkers=8 \
      --tpslimit=5 \
      --timeout=5m \
      --fast-list \
      --exclude-from /config/rclone/exclude.txt \
      > "$SYNC_LOG" 2>&1 || SYNC_SUCCESS=$?
fi

# Stream sync log to stdout for real-time Dozzle visibility
cat "$SYNC_LOG"

# --- Retention Policy Execution ---
PURGED_SNAPSHOTS=""
if [ $SYNC_SUCCESS -eq 0 ]; then
    echo "[$(date)] Running retention policy (Retain: ${RETENTION} weeks)..."
    OLD_FOLDERS=$(rclone lsf --dirs-only "${REMOTE_NAME}:${DEST_PATH}/${VM_NAME}" 2>/dev/null | sort -r | tail -n +$((RETENTION + 1)) | sed 's|/$||')
    if [ -n "$OLD_FOLDERS" ]; then
        for OLD_FOLDER in $OLD_FOLDERS; do
            echo "[$(date)] 🗑️ Purging expired backup snapshot: ${OLD_FOLDER}"
            if rclone purge "${REMOTE_NAME}:${DEST_PATH}/${VM_NAME}/${OLD_FOLDER}" 2>/dev/null; then
                PURGED_SNAPSHOTS="${PURGED_SNAPSHOTS} ${OLD_FOLDER}"
            else
                echo "Warning: Failed to purge ${OLD_FOLDER}"
            fi
        done
    fi
fi

# --- Telemetry & Metrics Harvesting ---
END_EPOCH=$(date +%s)
TOTAL_SECS=$((END_EPOCH - START_EPOCH))
DURATION_FMT="$(($TOTAL_SECS / 60))m $(($TOTAL_SECS % 60))s"

# 1. Parse Rclone Transfer Metrics
DATA_TRANSFERRED=$(grep -E "Transferred:[[:space:]]+[0-9.]+[[:space:]]+[kKMGT]i?B" "$SYNC_LOG" | tail -n 1 | sed 's/^[[:space:]]*Transferred:[[:space:]]*//' || echo "0 B")
FILES_TRANSFERRED=$(grep -E "Transferred:[[:space:]]+[0-9]+[[:space:]]*/[[:space:]]*[0-9]+" "$SYNC_LOG" | tail -n 1 | sed 's/^[[:space:]]*Transferred:[[:space:]]*//' || echo "0 / 0")
FILES_CHECKED=$(grep -E "Checks:[[:space:]]+[0-9]+" "$SYNC_LOG" | tail -n 1 | sed 's/^[[:space:]]*Checks:[[:space:]]*//' || echo "0 / 0")
FILES_DELETED=$(grep -E "Deleted:[[:space:]]+[0-9]+" "$SYNC_LOG" | tail -n 1 | sed 's/^[[:space:]]*Deleted:[[:space:]]*//' || echo "0")
ERRORS_COUNT=$(grep -E "Errors:[[:space:]]+[0-9]+" "$SYNC_LOG" | tail -n 1 | sed 's/^[[:space:]]*Errors:[[:space:]]*//' || echo "0")

# 2. Local Source & Host Disk Usage
LOCAL_SIZE=$(du -sh "$SOURCE_DIR" 2>/dev/null | awk '{print $1}')
LOCAL_DISK_USAGE=$(df -h "$SOURCE_DIR" 2>/dev/null | awk 'NR==2 {print $5 " used (" $4 " free of " $2 ")"}')

# 3. Cloud Snapshot Metrics
SNAPSHOT_STATS=$(rclone size "$BACKUP_DEST" 2>/dev/null | tr '\n' ', ' | sed 's/, $//')
[ -z "$SNAPSHOT_STATS" ] && SNAPSHOT_STATS="N/A"

# 4. Cloud Remote Quota
CLOUD_QUOTA=$(rclone about "${REMOTE_NAME}:" 2>/dev/null | tr '\n' ' | ' | sed 's/ | $//')
[ -z "$CLOUD_QUOTA" ] && CLOUD_QUOTA="Provider quota API not supported or query unavailable"

[ -z "$PURGED_SNAPSHOTS" ] && PURGED_SNAPSHOTS="None (within retention window)"

# Determine status label
if [ $SYNC_SUCCESS -eq 0 ]; then
    STATUS_EMOJI="✅"
    STATUS_TEXT="SUCCESS"
else
    STATUS_EMOJI="❌"
    STATUS_TEXT="FAILED (Exit Code: ${SYNC_SUCCESS})"
fi

# Build Structured Telemetry Report
REPORT=$(cat <<EOF
======================================================================
📊 BACKUP REPORT: ${VM_NAME} (${START_DATE})
======================================================================
Status:            ${STATUS_EMOJI} ${STATUS_TEXT}
Execution Time:    ${DURATION_FMT} (${TOTAL_SECS}s)
Target Snapshot:   ${BACKUP_DEST}
Notification Mode: ${NOTIFY_POLICY}

📦 Transfer Statistics:
  • Data Transferred:   ${DATA_TRANSFERRED:-0 B}
  • Files Transferred:  ${FILES_TRANSFERRED:-0}
  • Files Checked:      ${FILES_CHECKED:-0}
  • Files Deleted:      ${FILES_DELETED:-0}
  • Error Count:        ${ERRORS_COUNT:-0}

💾 Storage & Quota Insights:
  • Local Source Size:  ${LOCAL_SIZE:-Unknown} (${SOURCE_DIR})
  • Host Disk Usage:    ${LOCAL_DISK_USAGE:-Unknown}
  • Cloud Snapshot:     ${SNAPSHOT_STATS}
  • Cloud Remote Quota: ${CLOUD_QUOTA}

🗑️ Retention Policy (${RETENTION} Weeks):
  • Purged Snapshots:   ${PURGED_SNAPSHOTS}
======================================================================
EOF
)

# Print report to standard output for Dozzle and container logs
echo ""
echo "$REPORT"
echo ""

# --- Email Notification Policy Evaluation ---
SEND_NOTIFICATION=0
DAY_OF_WEEK=$(date +%u) # 1=Mon, 7=Sun

case "$NOTIFY_POLICY" in
    always|on|true|yes)
        SEND_NOTIFICATION=1
        ;;
    on_failure|errors_only|failure|error)
        if [ $SYNC_SUCCESS -ne 0 ]; then
            SEND_NOTIFICATION=1
        fi
        ;;
    weekly|summary)
        # Send on failure, OR on Sunday (day 7)
        if [ $SYNC_SUCCESS -ne 0 ] || [ "$DAY_OF_WEEK" -eq 7 ]; then
            SEND_NOTIFICATION=1
        fi
        ;;
    never|disabled|off|false|no)
        SEND_NOTIFICATION=0
        ;;
    *)
        # Default fallback: send only on failure
        if [ $SYNC_SUCCESS -ne 0 ]; then
            SEND_NOTIFICATION=1
        fi
        ;;
esac

# Dispatch Email if triggered by policy
if [ $SEND_NOTIFICATION -eq 1 ]; then
    if [ $SYNC_SUCCESS -eq 0 ]; then
        EMAIL_SUBJECT="✅ Backup Report: ${VM_NAME} [${DURATION_FMT}]"
    else
        EMAIL_SUBJECT="❌ Backup Alert: ${VM_NAME} FAILED"
        # Append tail of error log for faster troubleshooting
        REPORT="${REPORT}

⚠️ RECENT ERROR LOGS:
$(tail -n 25 "$SYNC_LOG")"
    fi
    send_email "$EMAIL_SUBJECT" "$REPORT"
else
    echo "[$(date)] 🔕 Email skipped per notification policy: '${NOTIFY_POLICY}' (Day: ${DAY_OF_WEEK}, Status: ${STATUS_TEXT})."
fi

rm -f "$SYNC_LOG"

if [ $SYNC_SUCCESS -ne 0 ]; then
    exit $SYNC_SUCCESS
fi