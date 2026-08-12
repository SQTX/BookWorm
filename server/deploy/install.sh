#!/usr/bin/env bash
#
# One-command install of the BookWorm API on a fresh Ubuntu server.
#
#   curl -fsSL https://raw.githubusercontent.com/SQTX/BookWorm/dev/server/deploy/install.sh \
#     | sudo bash -s -- --domain api.example.com
#
# or, from a checkout:
#
#   sudo ./install.sh                      # HTTPS via nip.io on this machine's IPv4
#   sudo ./install.sh --domain api.example.com
#   sudo ./install.sh --no-tls             # plain HTTP on :80, for a private network
#
# Idempotent: safe to re-run. Existing configuration is kept, not regenerated —
# rotating a secret must be a deliberate act, not a side effect of re-running an
# installer.
#
# You are asked for exactly one secret: the password for the API account, which
# is the only one a human ever types. The database password and the token
# signing key are generated here and never displayed, because nothing outside
# this machine needs them. Every manual-editing step in the earlier runbook was
# a place to leave a placeholder behind, and one of them duly was.

set -euo pipefail

REPO_URL="https://github.com/SQTX/BookWorm.git"
BRANCH="${BOOKWORM_BRANCH:-dev}"
APP_DIR=/opt/bookworm
DATA_DIR=/var/lib/bookworm
CONF_DIR=/etc/bookworm
ENV_FILE="$CONF_DIR/api.env"
SERVICE_USER=bookworm
DB_NAME=bookworm
DB_USER=bookworm
NODE_MAJOR=24
PORT=3000

DOMAIN=""
USE_TLS=1
SEED_EMAIL_ARG=""

# ─── output ──────────────────────────────────────────────────────────────────

step()  { printf '\n\033[1;34m==>\033[0m \033[1m%s\033[0m\n' "$1"; }
ok()    { printf '    \033[32m✓\033[0m %s\n' "$1"; }
info()  { printf '      %s\n' "$1"; }
warn()  { printf '    \033[33m!\033[0m %s\n' "$1"; }
die()   { printf '\n\033[31m✗ %s\033[0m\n\n' "$1" >&2; exit 1; }

# ─── arguments ───────────────────────────────────────────────────────────────

while [ $# -gt 0 ]; do
    case "$1" in
        --domain) DOMAIN="${2:-}"; shift 2 ;;
        --email)  SEED_EMAIL_ARG="${2:-}"; shift 2 ;;
        --no-tls) USE_TLS=0; shift ;;
        --branch) BRANCH="${2:-}"; shift 2 ;;
        -h|--help)
            sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'
            exit 0 ;;
        *) die "unknown option: $1" ;;
    esac
done

# ─── preflight ───────────────────────────────────────────────────────────────

step "Checking the host"

# The first thing that went wrong last time: half the commands need root and
# say so one at a time, leaving the machine in a partial state.
[ "$(id -u)" -eq 0 ] || die "Run as root:  sudo $0 $*"

command -v apt-get > /dev/null || die "This installer targets Ubuntu (no apt-get found)."

UBUNTU_VERSION=$(. /etc/os-release && echo "${VERSION_ID:-unknown}")
ok "Ubuntu $UBUNTU_VERSION"

ARCH=$(dpkg --print-architecture)
case "$ARCH" in
    amd64|arm64) ok "architecture $ARCH" ;;
    *) die "Unsupported architecture $ARCH — sharp and @node-rs/argon2 ship prebuilt binaries for amd64 and arm64 only." ;;
esac

# ─── packages ────────────────────────────────────────────────────────────────

step "Installing packages"

export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
# postgresql without a version suffix follows whatever the release ships — 16 on
# 24.04, 18 on 26.04. Pinning a number here would break on the next release.
apt-get install -y -qq git curl ufw zstd ca-certificates gnupg postgresql postgresql-contrib > /dev/null
ok "git, curl, ufw, zstd, postgresql"

if ! command -v node > /dev/null || [ "$(node -v | sed 's/v\([0-9]*\).*/\1/')" != "$NODE_MAJOR" ]; then
    # Ubuntu's own nodejs lags several majors behind; the app pins its version
    # in .nvmrc and CI runs the same one.
    curl -fsSL "https://deb.nodesource.com/setup_${NODE_MAJOR}.x" | bash - > /dev/null 2>&1
    apt-get install -y -qq nodejs > /dev/null
fi
ok "node $(node -v)"

# ─── users and directories ───────────────────────────────────────────────────

step "Creating the service user and directories"

if ! id "$SERVICE_USER" > /dev/null 2>&1; then
    adduser --system --group --home "$APP_DIR" "$SERVICE_USER" > /dev/null
fi
mkdir -p "$DATA_DIR/backups" "$DATA_DIR/covers" "$CONF_DIR"
chown -R "$SERVICE_USER:$SERVICE_USER" "$DATA_DIR"
ok "user $SERVICE_USER, $DATA_DIR, $CONF_DIR"

# ─── firewall ────────────────────────────────────────────────────────────────

step "Configuring the firewall"

ufw --force default deny incoming > /dev/null
ufw --force default allow outgoing > /dev/null
for p in 22 80 443; do ufw allow "$p/tcp" > /dev/null; done
# --force skips the "may disrupt existing ssh connections" prompt, which is safe
# because 22 was allowed on the line above.
ufw --force enable > /dev/null
ok "22, 80, 443 open — 5432 is not, and must never be"

# ─── postgresql ──────────────────────────────────────────────────────────────

step "Setting up PostgreSQL"

systemctl enable --now postgresql > /dev/null 2>&1 || true

PG_VERSION=$(ls /etc/postgresql 2>/dev/null | sort -n | tail -1)
[ -n "$PG_VERSION" ] || die "PostgreSQL is installed but no cluster exists in /etc/postgresql."
ok "PostgreSQL $PG_VERSION"

PG_CONF="/etc/postgresql/$PG_VERSION/main/postgresql.conf"
LISTEN=$(grep -E "^\s*listen_addresses" "$PG_CONF" | tail -1 | sed "s/.*=\s*'\([^']*\)'.*/\1/" || true)
if [ -n "$LISTEN" ] && [ "$LISTEN" != "localhost" ] && [ "$LISTEN" != "127.0.0.1" ]; then
    die "listen_addresses is '$LISTEN' in $PG_CONF. PostgreSQL must not accept connections from outside this host; set it to 'localhost' and re-run."
fi
# An absent or commented setting means PostgreSQL's own default, which is
# localhost. Saying so beats printing nothing and leaving it ambiguous, which is
# what the manual check did.
ok "listen_addresses: ${LISTEN:-localhost (default)}"

if [ -f "$ENV_FILE" ] && grep -q '^DATABASE_URL=' "$ENV_FILE"; then
    info "reusing the existing database credentials"
    DB_PASSWORD=""
else
    # No characters a URL can misread. A password containing # or / silently
    # truncates the connection string and surfaces as "password authentication
    # failed", which sends you looking in the wrong place entirely.
    DB_PASSWORD=$(openssl rand -base64 33 | tr -d '/+=' | cut -c1-32)
fi

if sudo -u postgres psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='$DB_USER'" | grep -q 1; then
    [ -n "$DB_PASSWORD" ] && sudo -u postgres psql -q -c "ALTER ROLE $DB_USER PASSWORD '$DB_PASSWORD';"
else
    sudo -u postgres psql -q -c "CREATE ROLE $DB_USER LOGIN PASSWORD '$DB_PASSWORD';"
fi

sudo -u postgres psql -tAc "SELECT 1 FROM pg_database WHERE datname='$DB_NAME'" | grep -q 1 \
    || sudo -u postgres createdb --owner="$DB_USER" "$DB_NAME"

# citext comes from postgresql-contrib and the accounts migration needs it.
# Failing here names the cause; failing later says "could not open extension
# control file", which reads like a broken migration.
sudo -u postgres psql -q -d "$DB_NAME" -c 'CREATE EXTENSION IF NOT EXISTS citext;' \
    || die "Could not create the citext extension. Is postgresql-contrib installed?"
ok "role $DB_USER, database $DB_NAME, citext available"

# ─── application ─────────────────────────────────────────────────────────────

step "Installing the application"

# The clone runs as root into a directory owned by the service user, so git
# refuses every later command with "dubious ownership" — and, worse, turns a
# git pull into a silent no-op that leaves you reinstalling the old lockfile.
git config --global --add safe.directory "$APP_DIR" 2>/dev/null || true

if [ -d "$APP_DIR/.git" ]; then
    git -C "$APP_DIR" fetch --quiet origin
    git -C "$APP_DIR" checkout --quiet "$BRANCH"
    git -C "$APP_DIR" reset --hard --quiet "origin/$BRANCH"
else
    git clone --quiet --branch "$BRANCH" "$REPO_URL" "$APP_DIR"
fi
ok "$BRANCH at $(git -C "$APP_DIR" rev-parse --short HEAD)"

cd "$APP_DIR/server"
npm ci --omit=dev --silent
[ -x node_modules/.bin/node-pg-migrate ] \
    || die "node-pg-migrate is missing after install — the branch may predate the fix that made it a runtime dependency."
ok "dependencies installed"

# After npm ci, because it writes node_modules as root into a tree the service
# reads as bookworm.
chown -R "$SERVICE_USER:$SERVICE_USER" "$APP_DIR"

# ─── configuration ───────────────────────────────────────────────────────────

step "Writing the configuration"

if [ -f "$ENV_FILE" ] && grep -q '^JWT_SECRET=' "$ENV_FILE"; then
    ok "$ENV_FILE exists — left untouched"
else
    JWT_SECRET=$(openssl rand -base64 48 | tr -d '\n')
    install -m 0640 -o root -g "$SERVICE_USER" /dev/null "$ENV_FILE"
    cat > "$ENV_FILE" <<EOF
# Generated by install.sh. Root-owned, readable by $SERVICE_USER.
# Not in the repository: that repository is public.
DATABASE_URL=postgres://$DB_USER:$DB_PASSWORD@localhost:5432/$DB_NAME
JWT_SECRET=$JWT_SECRET
PORT=$PORT
HOST=127.0.0.1
COVER_DIR=$DATA_DIR/covers
NODE_ENV=production
LOG_LEVEL=info
EOF
    chmod 0640 "$ENV_FILE"
    chown root:"$SERVICE_USER" "$ENV_FILE"
    ok "$ENV_FILE written with generated secrets"
    info "neither secret is displayed — nothing outside this machine needs them"
fi

set -a; . "$ENV_FILE"; set +a

psql "$DATABASE_URL" -qtAc 'SELECT 1' > /dev/null \
    || die "Cannot connect with the configured DATABASE_URL. Check $ENV_FILE."
ok "database connection verified"

# ─── schema ──────────────────────────────────────────────────────────────────

step "Applying migrations"

npm run migrate:up --silent > /tmp/bookworm-migrate.log 2>&1 \
    || { tail -20 /tmp/bookworm-migrate.log; die "Migrations failed — full log at /tmp/bookworm-migrate.log"; }
TABLES=$(psql "$DATABASE_URL" -qtAc "SELECT count(*) FROM pg_tables WHERE schemaname='public' AND tablename<>'pgmigrations'")
ok "schema applied — $TABLES tables"

# ─── account ─────────────────────────────────────────────────────────────────

step "Creating the API account"

EXISTING=$(psql "$DATABASE_URL" -qtAc 'SELECT email FROM users LIMIT 1' || true)

if [ -n "$EXISTING" ]; then
    ok "account already exists: $EXISTING"
    info "to change its password: SEED_EMAIL=$EXISTING SEED_PASSWORD='...' SEED_FORCE=yes npm run seed:user"
else
    SEED_EMAIL="$SEED_EMAIL_ARG"
    if [ -z "$SEED_EMAIL" ]; then
        printf '    email for the API account (this is a login, no mail is ever sent): '
        read -r SEED_EMAIL < /dev/tty
    fi
    [ -n "$SEED_EMAIL" ] || die "An email is required — it is the login."

    # Read twice. A mistyped password here is discovered at the first login
    # attempt, with nothing to compare against.
    while :; do
        printf '    password (at least 12 characters): '
        read -rs SEED_PASSWORD < /dev/tty; echo
        printf '    again: '
        read -rs CONFIRM < /dev/tty; echo
        [ "$SEED_PASSWORD" = "$CONFIRM" ] || { warn "they differ, try again"; continue; }
        [ ${#SEED_PASSWORD} -ge 12 ] || { warn "too short"; continue; }
        break
    done

    SEED_EMAIL="$SEED_EMAIL" SEED_PASSWORD="$SEED_PASSWORD" npm run seed:user --silent > /dev/null
    unset SEED_PASSWORD CONFIRM
    ok "account $SEED_EMAIL created"
fi

# ─── services ────────────────────────────────────────────────────────────────

step "Installing services"

cp "$APP_DIR/server/deploy/bookworm-api.service" /etc/systemd/system/

# Backup settings live in their own file so `backup-config.sh` can change the
# retention without touching api.env, which holds the secrets. Written only if
# absent: re-running the installer must not reset an operator's choices.
if [ ! -f /etc/bookworm/backup.env ]; then
    cat > /etc/bookworm/backup.env <<'EOF'
# How many backups to keep. When a new one is written, the oldest beyond this
# number is deleted along with its cover archive. Change it with:
#   sudo /opt/bookworm/server/scripts/backup-config.sh set-keep 30
BACKUP_DIR=/var/lib/bookworm/backups
KEEP_COUNT=14
# Optional second rule, off by default. Age-based, so it interacts with the
# interval: hourly backups kept for 30 days is 720 files.
KEEP_DAYS=0
EOF
    chmod 0644 /etc/bookworm/backup.env
fi

cat > /etc/systemd/system/bookworm-backup.service <<EOF
[Unit]
Description=BookWorm backup
[Service]
Type=oneshot
User=$SERVICE_USER
EnvironmentFile=$ENV_FILE
EnvironmentFile=-/etc/bookworm/backup.env
ExecStart=$APP_DIR/server/scripts/backup-db.sh
EOF

cat > /etc/systemd/system/bookworm-backup.timer <<'EOF'
[Unit]
Description=BookWorm backup
[Timer]
OnCalendar=daily
Persistent=true
[Install]
WantedBy=timers.target
EOF
# An operator's chosen interval lives in a drop-in under
# bookworm-backup.timer.d/, which this file cannot clobber — that is why
# set-interval writes one rather than editing the unit.

systemctl daemon-reload
systemctl enable --now bookworm-api > /dev/null 2>&1
systemctl restart bookworm-api
systemctl enable --now bookworm-backup.timer > /dev/null 2>&1
ok "bookworm-api running, backup timer armed (see: backup-config.sh status)"

for _ in $(seq 1 20); do
    HEALTH=$(curl -fsS --max-time 3 "http://127.0.0.1:$PORT/health" 2>/dev/null || true)
    [ "$HEALTH" = '{"status":"ok"}' ] && break
    sleep 1
done
[ "$HEALTH" = '{"status":"ok"}' ] \
    || { journalctl -u bookworm-api -n 20 --no-pager; die "The service did not become healthy."; }
ok "health: ok"

# ─── tls ─────────────────────────────────────────────────────────────────────

step "Configuring TLS"

if [ "$USE_TLS" -eq 0 ]; then
    warn "--no-tls: serving plain HTTP. Credentials and tokens travel unencrypted."
    cat > /etc/caddy/Caddyfile 2>/dev/null <<EOF || true
:80 {
    reverse_proxy 127.0.0.1:$PORT
}
EOF
    PUBLIC_URL="http://$(curl -4 -fsS --max-time 5 ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')"
else
    if ! command -v caddy > /dev/null; then
        curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' \
            | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg 2>/dev/null
        curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' \
            > /etc/apt/sources.list.d/caddy-stable.list 2>/dev/null
        apt-get update -qq && apt-get install -y -qq caddy > /dev/null
    fi
    ok "caddy $(caddy version | head -1)"

    if [ -z "$DOMAIN" ]; then
        # -4 explicitly. Without it curl may answer with the IPv6 address, whose
        # colons are illegal in a hostname — nip.io then produces a name
        # Let's Encrypt rejects outright.
        IPV4=$(curl -4 -fsS --max-time 10 ifconfig.me 2>/dev/null || true)
        [ -n "$IPV4" ] || die "No IPv4 address found. Pass --domain, or --no-tls for a private network."
        DOMAIN="$IPV4.nip.io"
        info "no --domain given, using $DOMAIN"
        info "nip.io resolves any <ip>.nip.io to that address, so Let's Encrypt issues a real certificate without a purchased domain"
    fi

    RESOLVED=$(getent ahostsv4 "$DOMAIN" 2>/dev/null | awk '{print $1; exit}' || true)
    MY_IP=$(curl -4 -fsS --max-time 10 ifconfig.me 2>/dev/null || true)
    if [ -n "$RESOLVED" ] && [ -n "$MY_IP" ] && [ "$RESOLVED" != "$MY_IP" ]; then
        die "$DOMAIN resolves to $RESOLVED but this machine is $MY_IP. Fix the DNS A record first — Let's Encrypt will refuse, and repeated failures are rate limited."
    fi
    ok "$DOMAIN resolves here"

    cat > /etc/caddy/Caddyfile <<EOF
$DOMAIN {
    reverse_proxy 127.0.0.1:$PORT
}
EOF
    systemctl reload caddy 2>/dev/null || systemctl restart caddy

    printf '      waiting for the certificate'
    for _ in $(seq 1 30); do
        printf '.'
        curl -fsS --max-time 3 "https://$DOMAIN/health" > /dev/null 2>&1 && break
        sleep 2
    done
    echo

    curl -fsS --max-time 10 "https://$DOMAIN/health" > /dev/null 2>&1 \
        || { journalctl -u caddy -n 20 --no-pager | grep -iE 'error|acme' || true
             die "HTTPS did not come up for $DOMAIN. Check DNS and that ports 80 and 443 are reachable."; }

    ok "certificate issued, HTTPS live"
    PUBLIC_URL="https://$DOMAIN"
fi

# ─── first backup ────────────────────────────────────────────────────────────

step "Taking the first backup"

systemctl start bookworm-backup.service
sleep 2
BACKUPS=$(ls -1 "$DATA_DIR/backups"/*.dump 2>/dev/null | wc -l | tr -d ' ')
[ "$BACKUPS" -gt 0 ] && ok "$BACKUPS backup(s) in $DATA_DIR/backups" \
                     || warn "no backup produced — check: journalctl -u bookworm-backup"

# ─── done ────────────────────────────────────────────────────────────────────

cat <<EOF

$(printf '\033[1;32m')Done.$(printf '\033[0m')

  API          $PUBLIC_URL
  Account      ${EXISTING:-${SEED_EMAIL:-unknown}}
  Config       $ENV_FILE
  Backups      $DATA_DIR/backups (daily)

Verify it end to end, ideally from another machine:

  $APP_DIR/server/scripts/smoke-test.sh $PUBLIC_URL ${EXISTING:-${SEED_EMAIL:-you@example.com}}

Useful:

  systemctl status bookworm-api
  journalctl -u bookworm-api -f

EOF
