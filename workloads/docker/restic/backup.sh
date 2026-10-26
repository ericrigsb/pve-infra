#!/usr/bin/env bash
# Based on https://blog.bithive.space/post/automatic-backups-with-restic/
# This script is intended to be run by a systemd timer

# Note: deliberately no `set -e`. restic returns 3 when some source files
# could not be read but the snapshot was still created, and `set -e` aborted
# this script on that code before `restic forget` ever ran -- so the repo
# accumulated one snapshot per day forever. Exit codes are handled explicitly.
set -o pipefail

# Paths to backup in a file and tag for backups
BACKUP_PATHS="/etc/backup/paths"
BACKUP_TAG=systemd.timer

# How many backups to keep.
RETENTION_DAYS=7
RETENTION_WEEKS=4
RETENTION_MONTHS=12
RETENTION_YEARS=1

source /etc/backup/restic_env

EXIT_CODE=0
SUMMARY=""

# Read line-by-line. The old `for line in $(cat "$BACKUP_PATHS")` word-split
# on whitespace, so any path containing a space was torn into fragments.
while IFS= read -r line || [ -n "$line" ]; do
       [ -z "$line" ] && continue
       case "$line" in \#*) continue ;; esac

       echo "==> backing up $line"
       restic backup \
              --verbose \
              --one-file-system \
              --tag "$BACKUP_TAG" \
              --host "$HOST" \
              "$line"
       rc=$?

       case $rc in
              0) SUMMARY="${SUMMARY}\nOK   $line" ;;
              # Snapshot WAS created, so pruning is still safe.
              3) SUMMARY="${SUMMARY}\nWARN $line -- some files unreadable, snapshot created anyway" ;;
              # No snapshot created. Do not prune.
              *) SUMMARY="${SUMMARY}\nFAIL $line -- restic exit $rc"; EXIT_CODE=1 ;;
       esac
done < "$BACKUP_PATHS"

# Remove old Backups. Skipped when no snapshot was created, so a hard backup
# failure can never prune away the snapshots we still depend on.
if [ "$EXIT_CODE" -ne 0 ]; then
       SUMMARY="${SUMMARY}\nPRUNE SKIPPED -- backup failed, preserving existing snapshots"
else
       echo "==> pruning"
       if restic forget \
              --verbose \
              --tag "$BACKUP_TAG" \
              --prune \
              --keep-daily "$RETENTION_DAYS" \
              --keep-weekly "$RETENTION_WEEKS" \
              --keep-monthly "$RETENTION_MONTHS" \
              --keep-yearly "$RETENTION_YEARS"; then
              SUMMARY="${SUMMARY}\nPRUNE OK"
       else
              rc=$?
              SUMMARY="${SUMMARY}\nPRUNE FAIL -- restic exit $rc"
              EXIT_CODE=1
       fi
fi

# Check if everything is fine
RESTIC_CHECK=$(restic check 2>&1)
check_rc=$?
if [ "$check_rc" -ne 0 ]; then
       SUMMARY="${SUMMARY}\nCHECK FAIL -- restic exit $check_rc"
       EXIT_CODE=1
else
       SUMMARY="${SUMMARY}\nCHECK OK"
fi

# Setup email message. Some variables in restic_env. Uses ssmtp.
MAIL_TXT="Subject: $SUBJECT\n\n$SUMMARY\n\n$RESTIC_CHECK"
echo -e "$MAIL_TXT" | ssmtp "$EMAIL" || echo "WARNING: failed to send notification email"

echo "Backup done!"

exit "$EXIT_CODE"
