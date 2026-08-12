#!/usr/bin/env bash
#
# Configure and inspect the backup schedule.
#
# Two settings decide everything: how often a backup runs, and how many are
# kept. Both were previously spread across a systemd unit and a default inside
# the backup script, so changing either meant editing a file most people would
# rather not touch and remembering `daemon-reload`. This is that, done properly.
#
#   backup-config.sh status                  what is configured, and what exists
#   backup-config.sh set-interval <spec>     hourly | 6h | daily | weekly | …
#   backup-config.sh set-keep <n>            how many backups to keep
#   backup-config.sh list                    the archives on disk
#   backup-config.sh at_now                  take a backup now, and wait for it
#   backup-config.sh prune                   apply retention now
#
# Anything that changes configuration needs root, because the timer and the
# config file are root-owned. `status` and `list` do not.

set -euo pipefail

CONFIG="${BACKUP_CONFIG:-/etc/bookworm/backup.env}"
SERVICE=bookworm-backup.service
TIMER=bookworm-backup.timer
OVERRIDE_DIR="/etc/systemd/system/$TIMER.d"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Defaults must match backup-db.sh, or `status` reports something the backup
# does not do.
DEFAULT_DIR=/var/lib/bookworm/backups
DEFAULT_KEEP_COUNT=14
DEFAULT_KEEP_DAYS=0

die() { echo "error: $*" >&2; exit 1; }
need_root() { [ "$(id -u)" -eq 0 ] || die "needs root: try sudo $0 $*"; }
has_systemd() { command -v systemctl > /dev/null 2>&1; }

# Environment beats the config file, which beats the defaults — the same
# precedence backup-db.sh applies, and it has to be the same or `status` reports
# one thing while a run does another.
load() {
    local from_env_dir="${BACKUP_DIR:-}"
    local from_env_count="${KEEP_COUNT:-}"
    local from_env_days="${KEEP_DAYS:-}"

    BACKUP_DIR="$DEFAULT_DIR"; KEEP_COUNT="$DEFAULT_KEEP_COUNT"; KEEP_DAYS="$DEFAULT_KEEP_DAYS"
    if [ -f "$CONFIG" ]; then
        # shellcheck disable=SC1090
        . "$CONFIG"
    fi

    [ -n "$from_env_dir" ] && BACKUP_DIR="$from_env_dir"
    [ -n "$from_env_count" ] && KEEP_COUNT="$from_env_count"
    [ -n "$from_env_days" ] && KEEP_DAYS="$from_env_days"
    return 0
}

write_config() {
    need_root "$@"
    mkdir -p "$(dirname "$CONFIG")"
    cat > "$CONFIG" <<EOF
# BookWorm backup settings. Written by backup-config.sh — safe to edit by hand,
# but note that the script rewrites the whole file.
#
# KEEP_COUNT is the rule that matters: how many backups exist at once. When a
# new one is written, the oldest beyond this number is deleted along with its
# cover archive.
#
# KEEP_DAYS is an optional second rule, off by default (0). It is age-based, so
# it interacts with the interval: with an hourly timer, 30 days is 720 files.
BACKUP_DIR=$BACKUP_DIR
KEEP_COUNT=$KEEP_COUNT
KEEP_DAYS=$KEEP_DAYS
EOF
    chmod 0644 "$CONFIG"
}

# Friendly names for the intervals anyone actually asks for. Anything else is
# passed through to systemd, which is stricter than this script could be.
calendar_for() {
    case "$1" in
        hourly)        echo "hourly" ;;
        2h|2hours)     echo "*-*-* 00/2:00:00" ;;
        4h|4hours)     echo "*-*-* 00/4:00:00" ;;
        6h|6hours)     echo "*-*-* 00/6:00:00" ;;
        12h|12hours)   echo "*-*-* 00/12:00:00" ;;
        daily)         echo "daily" ;;
        weekly)        echo "weekly" ;;
        monthly)       echo "monthly" ;;
        *)             echo "$1" ;;
    esac
}

current_calendar() {
    has_systemd || { echo "(no systemd on this machine)"; return; }
    systemctl show "$TIMER" -p TimersCalendar --value 2>/dev/null \
        | sed 's/.*OnCalendar=//; s/ ;.*//' | head -1
}

cmd_status() {
    load
    echo "Schedule"
    if has_systemd; then
        printf '  timer      %s\n' "$(systemctl is-active "$TIMER" 2>/dev/null || echo inactive)"
        printf '  interval   %s\n' "$(current_calendar)"
        printf '  next run   %s\n' "$(systemctl show "$TIMER" -p NextElapseUSecRealtime --value 2>/dev/null || echo unknown)"
        printf '  last run   %s\n' "$(systemctl show "$SERVICE" -p ExecMainStartTimestamp --value 2>/dev/null || echo never)"
        printf '  last exit  %s\n' "$(systemctl show "$SERVICE" -p Result --value 2>/dev/null || echo unknown)"
    else
        echo "  systemd not present — nothing is scheduled on this machine"
    fi

    echo
    echo "Retention"
    printf '  keep       %s backups\n' "$KEEP_COUNT"
    if [ "${KEEP_DAYS:-0}" -gt 0 ] 2>/dev/null; then
        printf '  also drop  anything older than %s days\n' "$KEEP_DAYS"
    else
        printf '  also drop  (age rule off)\n'
    fi
    printf '  directory  %s\n' "$BACKUP_DIR"
    printf '  config     %s\n' "$([ -f "$CONFIG" ] && echo "$CONFIG" || echo "$CONFIG (not written yet — defaults in use)")"

    echo
    echo "On disk"
    local count
    count=$(ls -1 "$BACKUP_DIR"/bookworm_*.dump 2>/dev/null | wc -l | tr -d ' ')
    printf '  backups    %s\n' "$count"
    if [ "$count" -gt 0 ]; then
        printf '  oldest     %s\n' "$(basename "$(ls -1 "$BACKUP_DIR"/bookworm_*.dump | sort | head -1)")"
        printf '  newest     %s\n' "$(basename "$(ls -1 "$BACKUP_DIR"/bookworm_*.dump | sort | tail -1)")"
        printf '  size       %s\n' "$(du -sh "$BACKUP_DIR" 2>/dev/null | cut -f1)"
    fi
    printf '  free       %s\n' "$(df -h "$BACKUP_DIR" 2>/dev/null | awk 'NR==2 {print $4}')"

    # A backup nobody has restored is a hypothesis, and status is where someone
    # is most likely to be reassured by numbers alone.
    echo
    echo "A restore has to be rehearsed to count — see deploy/RUNBOOK.md."
}

cmd_set_interval() {
    [ $# -eq 1 ] || die "usage: $0 set-interval <hourly|6h|daily|weekly|OnCalendar spec>"
    has_systemd || die "no systemd here; run the backup from cron instead"
    need_root set-interval "$1"

    local spec; spec=$(calendar_for "$1")
    systemd-analyze calendar "$spec" > /dev/null 2>&1 \
        || die "systemd does not understand '$spec' — try: hourly, 6h, daily, weekly"

    mkdir -p "$OVERRIDE_DIR"
    # The empty assignment first is required: OnCalendar is a list, so without
    # it the new value is *added* to the unit's and the backup runs on both
    # schedules — which looks like the setting being ignored.
    cat > "$OVERRIDE_DIR/interval.conf" <<EOF
[Timer]
OnCalendar=
OnCalendar=$spec
EOF
    systemctl daemon-reload
    systemctl restart "$TIMER"
    echo "interval set to '$spec'"
    printf 'next run: %s\n' "$(systemctl show "$TIMER" -p NextElapseUSecRealtime --value)"
}

cmd_set_keep() {
    [ $# -eq 1 ] || die "usage: $0 set-keep <number of backups to keep>"
    [ "$1" -ge 1 ] 2>/dev/null || die "keep must be a whole number of at least 1"
    load
    KEEP_COUNT="$1"
    write_config set-keep "$1"
    echo "keeping $KEEP_COUNT backups"
    echo "run '$0 prune' to apply it now, or let the next backup do it"
}

cmd_set_keep_days() {
    [ $# -eq 1 ] || die "usage: $0 set-keep-days <days, or 0 to turn the age rule off>"
    [ "$1" -ge 0 ] 2>/dev/null || die "days must be 0 or more"
    load
    KEEP_DAYS="$1"
    write_config set-keep-days "$1"
    [ "$KEEP_DAYS" -eq 0 ] && echo "age rule off" || echo "also dropping anything older than $KEEP_DAYS days"
}

cmd_list() {
    load
    ls -1 "$BACKUP_DIR"/bookworm_*.dump > /dev/null 2>&1 || { echo "no backups in $BACKUP_DIR"; return; }
    printf '%-34s %8s   %s\n' "BACKUP" "SIZE" "COVERS"
    for dump in $(ls -1 "$BACKUP_DIR"/bookworm_*.dump | sort); do
        local stamp covers
        stamp=$(basename "$dump" .dump); stamp="${stamp#bookworm_}"
        covers=$(ls -1 "$BACKUP_DIR/covers_$stamp".tar.* 2>/dev/null | head -1 || true)
        printf '%-34s %8s   %s\n' "$(basename "$dump")" "$(du -h "$dump" | cut -f1)" \
               "$([ -n "$covers" ] && du -h "$covers" | cut -f1 || echo '—')"
    done
}

# Take a backup right now and say how it went.
#
# `systemctl start` on a Type=oneshot unit waits for it to finish, so this is
# synchronous either way — which is the point. A command that returns instantly
# and leaves you to go and read a journal is not an answer to "back up now"; the
# question being asked is whether it worked.
cmd_at_now() {
    load

    if has_systemd && [ "$(id -u)" -eq 0 ]; then
        echo "running $SERVICE…"
        # Do not let a failure exit before the diagnosis below is printed: an
        # unexplained non-zero status is the least useful thing this could do.
        systemctl start "$SERVICE" || true
        local result
        result=$(systemctl show "$SERVICE" -p Result --value)
        journalctl -u "$SERVICE" -n 12 --no-pager -o cat 2>/dev/null || true
        if [ "$result" != "success" ]; then
            die "backup failed ($result) — full output: journalctl -u $SERVICE -n 50"
        fi
    else
        # No systemd, or not root: run it directly. DATABASE_URL has to come
        # from somewhere, and on a server that somewhere is the API's env file.
        if [ -z "${DATABASE_URL:-}" ] && [ -f /etc/bookworm/api.env ] && [ -r /etc/bookworm/api.env ]; then
            # shellcheck disable=SC1091
            . /etc/bookworm/api.env
            export DATABASE_URL
        fi
        "$SCRIPT_DIR/backup-db.sh"
    fi

    local newest
    newest=$(ls -1t "$BACKUP_DIR"/bookworm_*.dump 2>/dev/null | head -1 || true)
    if [ -n "$newest" ]; then
        printf 'newest backup: %s (%s)\n' "$(basename "$newest")" "$(du -h "$newest" | cut -f1)"
        printf 'kept: %s of %s\n' \
            "$(ls -1 "$BACKUP_DIR"/bookworm_*.dump 2>/dev/null | wc -l | tr -d ' ')" "$KEEP_COUNT"
    fi
}

cmd_prune() {
    "$SCRIPT_DIR/backup-db.sh" --prune-only
}

case "${1:-status}" in
    status)         shift || true; cmd_status ;;
    set-interval)   shift; cmd_set_interval "$@" ;;
    set-keep)       shift; cmd_set_keep "$@" ;;
    set-keep-days)  shift; cmd_set_keep_days "$@" ;;
    list)           shift || true; cmd_list ;;
    at_now|at-now|now|run)
                    shift || true; cmd_at_now ;;
    prune)          shift || true; cmd_prune ;;
    -h|--help|help)
        sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
        ;;
    *) die "unknown command '$1' — try: $0 --help" ;;
esac
