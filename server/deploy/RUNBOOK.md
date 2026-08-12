# Deployment Runbook

## The short version

```bash
curl -fsSL https://raw.githubusercontent.com/SQTX/BookWorm/dev/server/deploy/install.sh \
  | sudo bash -s -- --domain api.example.com
```

Without `--domain` it uses `<your-ipv4>.nip.io`, which gets a real Let's Encrypt
certificate without buying anything. `--no-tls` serves plain HTTP for a private
network.

It asks for one thing: the password for the API account. The database password
and the token signing key are generated and never shown, because nothing
outside the machine needs them — and every manual edit is somewhere a
placeholder can be left behind, which is exactly what happened the first time
this was done by hand.

Idempotent. Re-running upgrades the code and leaves existing secrets alone.

The rest of this document is what the script does, for when it fails or you want
to understand a step.

---

Target: **Ubuntu LTS**, 4 GB RAM, 2 vCPU, 40 GB disk. Sizing reasoning is in the
[roadmap](../../docs/superpowers/plans/2026-08-07-server-api-ios-roadmap.md); in
short, disk is not the constraint at this scale — RAM is.

Check the release first, because it decides the PostgreSQL version and every
config path below:

```bash
lsb_release -ds                          # e.g. Ubuntu 24.04.1 LTS
PG=$(pg_config --version 2>/dev/null | grep -oE '[0-9]+' | head -1)
```

| Ubuntu | Default PostgreSQL |
| --- | --- |
| 24.04 LTS | 16 |
| 22.04 LTS | 14 |

Either works — the migrations need 13 or newer for `gen_random_uuid()`.

---

## The rules that are not negotiable

1. **PostgreSQL never listens on a public interface.** `listen_addresses = 'localhost'`.
   Not during setup, not "just to test". Port 5432 is scanned continuously.
2. **Node never faces the internet.** It binds loopback; the reverse proxy
   terminates TLS in front of it.
3. **No secret enters the repository.** It is public. A committed credential is
   indexed within minutes and `git revert` does not remove it from history.
4. **A backup that has never been restored is a hypothesis**, not a backup.

---

## 1. Host

```bash
apt update && apt install -y git curl ufw zstd
adduser --system --group --home /opt/bookworm bookworm
mkdir -p /var/lib/bookworm/backups /var/lib/bookworm/covers /etc/bookworm
chown -R bookworm:bookworm /opt/bookworm /var/lib/bookworm
```

`zstd` is what the backup script prefers for the cover archive; without it the
script falls back to gzip, which works but compresses less well.

Firewall — default deny, and **not 5432**:

```bash
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp && ufw allow 80/tcp && ufw allow 443/tcp
ufw enable && ufw status
```

SSH keys only. In `/etc/ssh/sshd_config` set `PasswordAuthentication no`, then
`systemctl restart ssh`. Confirm you can still log in from a second terminal
**before** closing the first one.

## 2. PostgreSQL

```bash
apt update
apt install -y postgresql postgresql-contrib
```

**`postgresql-contrib` is not optional.** It provides `citext`, which the
accounts migration uses for case-insensitive email. Without it `npm run
migrate:up` fails on the very first migration with `could not open extension
control file`, which reads like a broken migration rather than a missing
package.

Confirm the bind address — check it, do not assume it:

```bash
PGVER=$(ls /etc/postgresql)            # 16 on 24.04, 14 on 22.04
grep ^listen_addresses /etc/postgresql/$PGVER/main/postgresql.conf
```

It must be `localhost`. That is Ubuntu's default, but a VPS image may have been
changed.

```bash
sudo -u postgres createuser bookworm --pwprompt
sudo -u postgres createdb --owner=bookworm bookworm

# Prove citext is available before going further.
sudo -u postgres psql -d bookworm -c 'CREATE EXTENSION IF NOT EXISTS citext;'
```

## 3. Node

Ubuntu's own `nodejs` package lags well behind, so use NodeSource and match
`.nvmrc` — currently 24. Dev/prod parity is the point; "whatever the distro
packages" drifts.

```bash
curl -fsSL https://deb.nodesource.com/setup_24.x | bash -
apt install -y nodejs
node --version                          # must be v24.x
```

`sharp` and `@node-rs/argon2` ship prebuilt binaries for linux-x64 and
linux-arm64, so no compiler is needed — which is what the "no build toolchain on
the server" rule in D1 was protecting.

## 4. Application

`adduser --system --home /opt/bookworm` already created that directory owned by
`bookworm`, and this clone runs as root — so the files land root-owned inside a
bookworm-owned tree. Git then refuses every later command with
`fatal: detected dubious ownership`, which silently turns a `git pull` into a
no-op: the next `npm ci` reinstalls the *old* lockfile and the failure appears
somewhere else entirely.

Tell git this repository is trusted, then hand the tree back to the service user
once the install is done:

```bash
git config --global --add safe.directory /opt/bookworm

git clone https://github.com/SQTX/BookWorm.git /opt/bookworm
cd /opt/bookworm/server
npm ci --omit=dev

chown -R bookworm:bookworm /opt/bookworm
```

The `chown` comes after `npm ci`, not before: node_modules is created by the
install and would otherwise be root-owned in a tree the service reads as
`bookworm`.

`npm ci`, never `npm install`: it installs exactly the committed lockfile and
fails if that lockfile and `package.json` disagree.

`node-pg-migrate` is a runtime dependency, not a development one, precisely
because migrations run here — `--omit=dev` must not remove the tool the next
step needs.

## 5. Configuration

```bash
install -m 0640 -o root -g bookworm /dev/null /etc/bookworm/api.env
```

```ini
DATABASE_URL=postgres://bookworm:REPLACE_WITH_DB_PASSWORD@localhost:5432/bookworm
JWT_SECRET=REPLACE_WITH_OPENSSL_OUTPUT
PORT=3000
HOST=127.0.0.1
COVER_DIR=/var/lib/bookworm/covers
LOG_LEVEL=info
```

Both `REPLACE_WITH_` values are placeholders. Left in place they produce
`password authentication failed` and a refusal to start — failures that look
like a wrong password and a broken build rather than an unfinished edit.
Confirm the substitution rather than assuming it:

```bash
grep -E '^(DATABASE_URL|JWT_SECRET)' /etc/bookworm/api.env | grep REPLACE_WITH \
  && echo 'STOP: placeholders still present' || echo 'placeholders replaced'
```

Root-owned, group-readable by `bookworm`. Not in the repository, not in the
systemd unit — the unit is world-readable.

`JWT_SECRET` must be at least 32 characters; the server refuses to start
otherwise. Rotating it logs every device out, which is a blunt but effective
way to revoke everything.

### The database password goes inside a URL

`DATABASE_URL` is parsed as a URL, so a password containing `#`, `/`, `?` or a
second `:` does not mean what it looks like — `#` starts a fragment, `/` starts
a path. The failure surfaces as `password authentication failed`, which sends
you hunting for a wrong password rather than a quoting problem.

`@` and `!` happen to survive; the others do not. The reliable fix is to avoid
the question:

```bash
# A password with nothing a URL can misread.
openssl rand -base64 24 | tr -d '/+=' 
```

If you must keep a password containing special characters, percent-encode it in
the URL (`#` → `%23`, `/` → `%2F`, `?` → `%3F`, `:` → `%3A`).

### Prove the connection before going further

```bash
set -a; . /etc/bookworm/api.env; set +a
psql "$DATABASE_URL" -c 'SELECT 1'
```

One command, and it separates "wrong password" from "wrong URL" from "server not
listening" before any migration is involved. If this fails, nothing after it can
work.

## 6. Schema and account

```bash
cd /opt/bookworm/server
# `set -a` exports everything the file defines. Do NOT use
# `export $(grep ... | xargs)`: word-splitting mangles any value containing a
# space or a quote, so a strong password silently becomes a wrong one and the
# failure looks like bad credentials.
set -a; . /etc/bookworm/api.env; set +a

npm run migrate:up
SEED_EMAIL=you@example.com SEED_PASSWORD='...' npm run seed:user
```

There is no registration endpoint, so this is the only way an account exists —
and therefore no signup path to attack.

## 7. Service

```bash
cp deploy/bookworm-api.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now bookworm-api
systemctl status bookworm-api
curl -s localhost:3000/health   # {"status":"ok"}
```

The first log line reports the mode and the bind address. If it says
`development`, the environment file is not being read.

## 8. Reverse proxy and TLS

Caddy is not in Ubuntu's repositories; add its own:

```bash
apt install -y debian-keyring debian-archive-keyring apt-transport-https
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' \
  | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' \
  | tee /etc/apt/sources.list.d/caddy-stable.list
apt update && apt install -y caddy
```

`/etc/caddy/Caddyfile`:

```
api.example.com {
    reverse_proxy 127.0.0.1:3000
}
```

```bash
systemctl reload caddy
```

Caddy obtains and renews the certificate itself, provided the DNS A record
already points here and ports 80 and 443 are open.

Terminate TLS at the proxy and forward to `127.0.0.1:3000`. The app sets
`trustProxy`, so the proxy must set `X-Forwarded-For` — rate limiting keys on
the client address, and without it every request appears to come from the proxy
and one client can throttle everyone.

## 9. Backups

Armed by the installer and running daily. Nothing here needs doing by hand — the
section exists so that changing it later does not require reading the script.

```bash
sudo /opt/bookworm/server/scripts/backup-config.sh status
```

```
Schedule
  timer      active
  interval   daily
  next run   Thu 2026-08-13 03:00:00 CEST
  last run   Wed 2026-08-12 03:00:04 CEST
  last exit  success

Retention
  keep       14 backups
  also drop  (age rule off)
  directory  /var/lib/bookworm/backups
  config     /etc/bookworm/backup.env

On disk
  backups    14
  oldest     bookworm_2026-07-30_0300.dump
  newest     bookworm_2026-08-12_0300.dump
  size       412M
  free       28G
```

### Changing the schedule and the retention

```bash
BC=/opt/bookworm/server/scripts/backup-config.sh

sudo $BC set-interval 6h        # hourly | 2h | 4h | 6h | 12h | daily | weekly | monthly
sudo $BC set-keep 30            # how many backups exist at once
sudo $BC set-keep-days 90       # optional second rule; 0 turns it off
sudo $BC run                    # take one now
sudo $BC prune                  # apply retention now, without a new backup
     $BC list                   # what is on disk, with sizes
```

`set-interval` accepts any `OnCalendar` expression systemd understands, and
refuses anything it does not — the check is `systemd-analyze calendar`, so a
typo is caught before it becomes a timer that never fires.

It writes a **drop-in** at
`/etc/systemd/system/bookworm-backup.timer.d/interval.conf` rather than editing
the unit, so an upgrade cannot silently reset your schedule. The drop-in clears
`OnCalendar` before setting it, because `OnCalendar` is a list: assigning
without clearing *adds* a schedule, and the backup then runs on both — which
looks exactly like the setting being ignored.

`set-keep` and `set-keep-days` write `/etc/bookworm/backup.env`, which the
backup service reads. The installer creates that file only if it is absent, so
re-running the installer never resets your choices.

### How retention decides

**`KEEP_COUNT` (default 14) is the rule that matters:** how many backups exist
at once. When a new one is written, the oldest beyond that number is deleted
**together with its cover archive** — a database restored into a library with no
images is a failure that announces itself only much later, since the book rows
still carry their hashes.

`KEEP_DAYS` (default 0, off) is an optional second rule by age. It is off by
default because age interacts badly with the interval: "keep 30 days" of hourly
backups is 720 archives, which is not what anyone picturing a month of backups
has in mind. Turn it on only when you want a hard ceiling on age as well as on
count.

Zero is refused. "Keep no backups" is never what anyone means, and acting on it
would empty the directory at the next successful run.

Rotation happens **only after a successful backup**, so a failing job can never
delete the last good one. Eleven tests in `test/backup-retention.test.js` run the
real script against a real directory — this is the one part of the system whose
job is to delete files, so it is not left to inspection.

### What is in a backup

`BACKUP_DIR` defaults to `/var/lib/bookworm/backups`. Each run writes a pair:

- `bookworm_<stamp>.dump` — `pg_dump --format=custom`, verified with
  `pg_restore --list` before it is promoted out of `.part`
- `covers_<stamp>.tar.zst` — the contents of `COVER_DIR`, verified the same way

**Copy backups off the machine.** A dump on the same disk as the database
protects against a mistaken `DELETE`, not against losing the machine.

---

## Restore drill

Do this once when you set the server up, then periodically. It is the only thing
that turns a backup into a fact.

```bash
createdb bookworm_restore_check
pg_restore -d bookworm_restore_check /var/lib/bookworm/backups/<newest>.dump

psql -qtA -d bookworm_restore_check -c 'SELECT count(*) FROM books;'
psql -qtA -d bookworm_restore_check -c 'SELECT count(*) FROM users;'

# Covers restore separately — they are files.
mkdir -p /tmp/cover_check && tar -C /tmp/cover_check -xf /var/lib/bookworm/backups/covers_<same-stamp>.tar.zst
# Every hash the database references should have a file:
psql -qtA -d bookworm_restore_check -c 'SELECT cover_hash FROM books WHERE cover_hash IS NOT NULL' \
  | while read -r h; do
      [ -f "/tmp/cover_check/${h:0:2}/${h:2:2}/$h.full.webp" ] || echo "MISSING $h"
    done

rm -rf /tmp/cover_check
dropdb bookworm_restore_check
```

Never restore over the live database to "test" it.

---

## Routine checks

| | |
| --- | --- |
| Service | `systemctl status bookworm-api` |
| Mode | `journalctl -u bookworm-api | grep 'starting in'` — must say `production` |
| Logs | `journalctl -u bookworm-api -f` |
| Health | `curl -s localhost:3000/health` — `503` means the database is unreachable |
| Disk | `df -h` — covers will dominate once they exist |
| Failed logins | `journalctl -u bookworm-api | grep 'failed login'` |
| Token theft | `journalctl -u bookworm-api | grep 'reuse detected'` — should be empty; a hit means a refresh token was used twice |

## Upgrades

```bash
systemctl start bookworm-backup.service     # backup BEFORE the migration
cd /opt/bookworm && git pull
cd server && npm ci --omit=dev
chown -R bookworm:bookworm /opt/bookworm    # npm ci writes as root
set -a; . /etc/bookworm/api.env; set +a
npm run migrate:up
systemctl restart bookworm-api
```

Check `git pull` actually reported new commits. A refusal on ownership grounds
prints a message and exits, and the `npm ci` that follows will happily reinstall
the version you already had.

The backup goes before the migration, not after — afterwards it captures the
state you might need to undo.

---

## Known gaps

- **No monitoring beyond the health endpoint.** Nothing pages anyone.
- **One account.** No registration, no password reset — re-run `seed:user` with
  `SEED_FORCE=yes` to change the password.
