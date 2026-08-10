#!/usr/bin/env bash
#
# Back up the server's database.
#
# The desktop app has had a verified backup path for a long time; the server's
# database would have had none, which is the more exposed of the two — it is the
# one reachable from the internet.
#
# Writes a custom-format dump, verifies it can be listed, then rotates. Designed
# for a systemd timer or cron:
#
#   0 3 * * *  /opt/bookworm/server/scripts/backup-db.sh >> /var/log/bookworm-backup.log 2>&1
#
# Environment:
#   DATABASE_URL   required
#   BACKUP_DIR     default /var/lib/bookworm/backups
#   COVER_DIR      default /var/lib/bookworm/covers
#   KEEP_DAYS      default 30
#
# Covers are included. They are files on disk, not rows, so a database-only
# dump restores a library in which every image is missing — and the loss is
# silent, because the book rows still carry their hashes.

set -euo pipefail

BACKUP_DIR="${BACKUP_DIR:-/var/lib/bookworm/backups}"
COVER_DIR="${COVER_DIR:-/var/lib/bookworm/covers}"
KEEP_DAYS="${KEEP_DAYS:-30}"

if [ -z "${DATABASE_URL:-}" ]; then
    echo "DATABASE_URL is not set" >&2
    exit 1
fi

mkdir -p "$BACKUP_DIR"

stamp=$(date -u +%Y-%m-%d_%H%M)
target="$BACKUP_DIR/bookworm_$stamp.dump"

# Remove the partial file on ANY exit path, including pg_dump failing under
# set -e. Without this a failed run leaves a .part behind, and a directory
# slowly filling with them looks like backups in progress rather than a job
# that has been broken for weeks.
covers_target="$BACKUP_DIR/covers_$stamp.tar.zst"

cleanup() { rm -f "$target.part" "$covers_target.part"; }
trap cleanup EXIT

# Write to .part first. A dump interrupted halfway through must not be mistaken
# for a good one — which is exactly what happens when the name is claimed up
# front and the process dies.
pg_dump --format=custom --file="$target.part" "$DATABASE_URL"

# Verify before promoting. An unreadable dump that sits in the directory looking
# like a backup is worse than no backup, because it stops anyone looking further.
if ! pg_restore --list "$target.part" > /dev/null 2>&1; then
    echo "backup verification failed, discarding $target.part" >&2
    rm -f "$target.part"
    exit 1
fi

# Covers, if any exist. Content-addressed and immutable, so this compresses
# well and never needs to re-copy a file that has not changed name.
if [ -d "$COVER_DIR" ] && [ -n "$(ls -A "$COVER_DIR" 2>/dev/null)" ]; then
    if command -v zstd > /dev/null 2>&1; then
        tar -C "$COVER_DIR" -cf - . | zstd -q -o "$covers_target.part"
    else
        covers_target="${covers_target%.zst}.gz"
        tar -C "$COVER_DIR" -czf "$covers_target.part" .
    fi

    # Verify the archive lists cleanly before promoting, for the same reason the
    # dump is verified: an unreadable archive that looks like a backup is worse
    # than none.
    if ! tar -tf "$covers_target.part" > /dev/null 2>&1; then
        echo "cover archive verification failed, discarding" >&2
        exit 1
    fi

    mv "$covers_target.part" "$covers_target"
    echo "covers written: $covers_target ($(du -h "$covers_target" | cut -f1))"
else
    echo "no covers to back up"
fi

mv "$target.part" "$target"
# Promoted successfully, so there is nothing partial left to clean up.
trap - EXIT
echo "backup written: $target ($(du -h "$target" | cut -f1))"

# Rotate only after a successful run, so a failing backup never deletes the last
# good one.
deleted=$(find "$BACKUP_DIR" \( -name 'bookworm_*.dump' -o -name 'covers_*.tar.*' \) -type f -mtime "+$KEEP_DAYS" -print -delete | wc -l)
[ "$deleted" -gt 0 ] && echo "rotated out $deleted backup(s) older than $KEEP_DAYS days"

# A backup that has never been restored is a hypothesis. The runbook has the
# drill; this line is the reminder that it exists.
echo "reminder: verify a restore periodically — see deploy/RUNBOOK.md"
