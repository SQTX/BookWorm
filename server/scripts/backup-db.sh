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
#   KEEP_COUNT     default 14   how many backups to keep — the primary rule
#   KEEP_DAYS      default 0    additionally drop anything older, 0 = off
#
# Settings are read from BACKUP_CONFIG (default /etc/bookworm/backup.env) when
# it exists, so `backup-config.sh` can change them without anyone editing a
# systemd unit or this file. Environment variables still win, which is what
# makes the script testable.
#
# Run with --prune-only to apply retention without taking a backup.
#
# Covers are included. They are files on disk, not rows, so a database-only
# dump restores a library in which every image is missing — and the loss is
# silent, because the book rows still carry their hashes.

set -euo pipefail

BACKUP_CONFIG="${BACKUP_CONFIG:-/etc/bookworm/backup.env}"
if [ -f "$BACKUP_CONFIG" ]; then
    # Anything already in the environment wins over the file: a one-off run with
    # a different directory should not need the file edited and put back.
    saved_dir="${BACKUP_DIR:-}" saved_count="${KEEP_COUNT:-}" saved_days="${KEEP_DAYS:-}"
    # shellcheck disable=SC1090
    . "$BACKUP_CONFIG"
    [ -n "$saved_dir" ] && BACKUP_DIR="$saved_dir"
    [ -n "$saved_count" ] && KEEP_COUNT="$saved_count"
    [ -n "$saved_days" ] && KEEP_DAYS="$saved_days"
fi

BACKUP_DIR="${BACKUP_DIR:-/var/lib/bookworm/backups}"
COVER_DIR="${COVER_DIR:-/var/lib/bookworm/covers}"
KEEP_COUNT="${KEEP_COUNT:-14}"
KEEP_DAYS="${KEEP_DAYS:-0}"

# Zero would mean "delete everything, keep nothing", which no operator ever
# means and which would empty the directory on the next successful run.
if ! [ "$KEEP_COUNT" -ge 1 ] 2>/dev/null; then
    echo "KEEP_COUNT must be a whole number of at least 1 (got '$KEEP_COUNT')" >&2
    exit 1
fi

# The covers archive belonging to a dump shares its timestamp, which is how a
# pair is deleted together rather than leaving a database with no images.
covers_for() {
    local stamp="$1"
    ls "$BACKUP_DIR/covers_$stamp".tar.* 2>/dev/null || true
}

prune() {
    mkdir -p "$BACKUP_DIR"

    # Stamps are UTC yyyy-mm-dd_HHMM, so sorting the names sorts them by time.
    local dumps
    dumps=$(ls -1 "$BACKUP_DIR"/bookworm_*.dump 2>/dev/null | sort || true)
    [ -z "$dumps" ] && return 0

    local total kept_from removed=0
    total=$(printf '%s\n' "$dumps" | wc -l | tr -d ' ')

    if [ "$total" -gt "$KEEP_COUNT" ]; then
        local doomed
        doomed=$(printf '%s\n' "$dumps" | head -n "$((total - KEEP_COUNT))")
        while IFS= read -r dump; do
            [ -z "$dump" ] && continue
            local stamp
            stamp=$(basename "$dump" .dump); stamp="${stamp#bookworm_}"
            rm -f "$dump"
            # shellcheck disable=SC2046
            rm -f $(covers_for "$stamp")
            removed=$((removed + 1))
        done <<< "$doomed"
    fi

    # Age is a second, optional rule rather than the main one: with an hourly
    # timer, "older than 30 days" is 720 archives, which is not what anyone
    # picturing "a month of backups" has in mind.
    if [ "$KEEP_DAYS" -gt 0 ] 2>/dev/null; then
        local by_age
        by_age=$(find "$BACKUP_DIR" \( -name 'bookworm_*.dump' -o -name 'covers_*.tar.*' \) \
                      -type f -mtime "+$KEEP_DAYS" -print -delete | wc -l | tr -d ' ')
        [ "$by_age" -gt 0 ] && echo "rotated out $by_age file(s) older than $KEEP_DAYS days"
    fi

    kept_from=$(ls -1 "$BACKUP_DIR"/bookworm_*.dump 2>/dev/null | wc -l | tr -d ' ')
    [ "$removed" -gt 0 ] && echo "rotated out $removed backup(s); $kept_from of $KEEP_COUNT kept"
    return 0
}

if [ "${1:-}" = "--prune-only" ]; then
    prune
    exit 0
fi

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
# good one — the newest archive is now on disk, and retention counts from it.
prune

# A backup that has never been restored is a hypothesis. The runbook has the
# drill; this line is the reminder that it exists.
echo "reminder: verify a restore periodically — see deploy/RUNBOOK.md"
