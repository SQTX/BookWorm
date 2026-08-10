# Deployment Runbook

Target: 4 GB RAM, 2 vCPU, 40 GB disk, current LTS Linux. Sizing reasoning is in
the [roadmap](../../docs/superpowers/plans/2026-08-07-server-api-ios-roadmap.md);
in short, disk is not the constraint at this scale — RAM is.

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
adduser --system --group --home /opt/bookworm bookworm
mkdir -p /var/lib/bookworm/backups /var/lib/bookworm/covers /etc/bookworm
chown -R bookworm:bookworm /opt/bookworm /var/lib/bookworm
```

SSH keys only, password authentication off, firewall default-deny with 22, 80
and 443 open. **Not 5432.**

## 2. PostgreSQL

```bash
# postgresql.conf
listen_addresses = 'localhost'

createuser bookworm --pwprompt
createdb --owner=bookworm bookworm
```

## 3. Node

Match the version in `.nvmrc` — currently 24. Dev/prod parity is the point;
"whatever the distro packages" drifts.

## 4. Application

```bash
git clone https://github.com/SQTX/BookWorm.git /opt/bookworm
cd /opt/bookworm/server
npm ci --omit=dev
```

`npm ci`, never `npm install`: it installs exactly the committed lockfile and
fails if that lockfile and `package.json` disagree.

## 5. Configuration

```bash
install -m 0640 -o root -g bookworm /dev/null /etc/bookworm/api.env
```

```ini
DATABASE_URL=postgres://bookworm:PASSWORD@localhost:5432/bookworm
JWT_SECRET=<openssl rand -base64 48>
PORT=3000
HOST=127.0.0.1
COVER_DIR=/var/lib/bookworm/covers
LOG_LEVEL=info
```

Root-owned, group-readable by `bookworm`. Not in the repository, not in the
systemd unit — the unit is world-readable.

`JWT_SECRET` must be at least 32 characters; the server refuses to start
otherwise. Rotating it logs every device out, which is a blunt but effective
way to revoke everything.

## 6. Schema and account

```bash
export $(grep -v '^#' /etc/bookworm/api.env | xargs)
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

Terminate TLS at the proxy and forward to `127.0.0.1:3000`. The app sets
`trustProxy`, so the proxy must set `X-Forwarded-For` — rate limiting keys on
the client address, and without it every request appears to come from the proxy
and one client can throttle everyone.

## 9. Backups

```bash
# /etc/systemd/system/bookworm-backup.service  → ExecStart=/opt/bookworm/server/scripts/backup-db.sh
# /etc/systemd/system/bookworm-backup.timer    → OnCalendar=daily
systemctl enable --now bookworm-backup.timer
```

`BACKUP_DIR` defaults to `/var/lib/bookworm/backups`, `KEEP_DAYS` to 30. The
script verifies each dump with `pg_restore --list` before promoting it out of
`.part`, and rotates **only after** a successful run so a failing backup can
never delete the last good one.

**Covers are included in the backup.** They are files, not rows: a
database-only dump restores a library in which every image is missing, and the
loss is silent because the book rows still carry their hashes. The script
archives `COVER_DIR` alongside the dump.

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
| Logs | `journalctl -u bookworm-api -f` |
| Health | `curl -s localhost:3000/health` — `503` means the database is unreachable |
| Disk | `df -h` — covers will dominate once they exist |
| Failed logins | `journalctl -u bookworm-api | grep 'failed login'` |
| Token theft | `journalctl -u bookworm-api | grep 'reuse detected'` — should be empty; a hit means a refresh token was used twice |

## Upgrades

```bash
cd /opt/bookworm && git pull
cd server && npm ci --omit=dev
npm run migrate:up          # take a backup first
systemctl restart bookworm-api
```

Run the backup before the migration, not after.

---

## Known gaps

- **No monitoring beyond the health endpoint.** Nothing pages anyone.
- **One account.** No registration, no password reset — re-run `seed:user` with
  `SEED_FORCE=yes` to change the password.
