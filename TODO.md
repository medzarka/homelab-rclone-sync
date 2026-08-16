# Backup Enhancements TODO

## Done
- [x] **Bandwidth Optimization**: Use `--copy-dest` to avoid full re-uploads.
- [x] **Speed Optimization**: Add `--fast-list`.
- [x] **Advanced Error Handling**: Catch exit codes and gracefully fail.
- [x] **Application Consistency**: Pause/Unpause a configured list of Docker containers.
- [x] **Alerting & Notifications (Email)**: Send an email on backup success or failure.

## Postponed
- [ ] **Alerting & Notifications (WhatsApp)**: Send WhatsApp alerts (e.g., via CallMeBot or Twilio).
- [ ] **Traffic Shaping & API Limits**: Implement `--bwlimit` or `--tpslimit`.
- [ ] **Client-Side Encryption (Zero-Knowledge)**: Use `rclone crypt` to encrypt files locally before uploading.
