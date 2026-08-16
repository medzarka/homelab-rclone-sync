FROM rclone/rclone:latest

# Install docker-cli and curl
RUN apk add --no-cache docker-cli curl

# Copy the backup and entrypoint scripts into the image
COPY scripts/backup.sh /scripts/backup.sh
COPY scripts/entrypoint.sh /scripts/entrypoint.sh

# Ensure they are executable
RUN chmod +x /scripts/backup.sh /scripts/entrypoint.sh

# Use the custom entrypoint
ENTRYPOINT ["/scripts/entrypoint.sh"]
