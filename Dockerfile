FROM rclone/rclone:latest

# Install docker-cli and curl
RUN apk add --no-cache docker-cli curl

# Copy the backup, entrypoint scripts, and default exclude sample into the image
COPY scripts/backup.sh /scripts/backup.sh
COPY scripts/entrypoint.sh /scripts/entrypoint.sh
COPY exclude.txt.sample /scripts/exclude.txt.sample

# Ensure scripts are executable
RUN chmod +x /scripts/backup.sh /scripts/entrypoint.sh

# Use the custom entrypoint
ENTRYPOINT ["/scripts/entrypoint.sh"]
