# Install — the full environment

Desktop app **+** your own server **+** the iPhone app, synchronising both ways.

Pick this if you want your library on more than one device. If a single Mac is
all you need, [`INSTALL-DESKTOP.md`](INSTALL-DESKTOP.md) is a shorter and
complete answer, and you can come back here later without undoing anything.

**Time:** about an hour. Fifteen minutes of it is Homebrew; twenty is the
server; the rest is Xcode.

---

## What you are building

```
   Mac                          your server                     iPhone
┌──────────┐   /v1/sync      ┌────────────────┐   /v1/books   ┌──────────┐
│ BookWorm │◄───────────────►│ Fastify + PG   │◄─────────────►│ BookWorm │
│ Qt app   │  whole library  │ behind Caddy   │  one field    │ Progress │
└──────────┘                 └────────────────┘               └──────────┘
```

The server holds one account — yours. There is no registration endpoint and no
second user; see [`ARCHITECTURE.md`](ARCHITECTURE.md) for why the two clients
speak to it differently.

---

## Step 1 — the desktop application

Follow [`INSTALL-DESKTOP.md`](INSTALL-DESKTOP.md) sections 1–5 and come back
here. Leave sync alone for now; it is configured in step 4, after there is
something to point it at.

Do not skip the Qt PostgreSQL driver section. It is the one step that is not
automatic, and its failure looks like a broken install rather than a missing
file.

---

## Step 2 — the server

### The short way (a VPS)

Ubuntu LTS, 4 GB RAM, 2 vCPU, 40 GB disk. On the machine:

```bash
curl -fsSL https://raw.githubusercontent.com/SQTX/BookWorm/dev/server/deploy/install.sh \
  | sudo bash -s -- --domain api.example.com
```

Without `--domain` it uses `<your-ipv4>.nip.io`, which earns a real Let's
Encrypt certificate without buying a domain. `--no-tls` serves plain HTTP for a
private network — acceptable on a LAN, never on the open internet.

It asks for exactly one thing: the password for your account. The database
password and the token signing key are generated and never displayed, because
nothing outside that machine needs them.

The script is idempotent — re-running it upgrades the code and leaves existing
secrets alone. What it sets up: code in `/opt/bookworm`, config in
`/etc/bookworm/api.env`, data in `/var/lib/bookworm/{backups,covers}`, a systemd
service, Caddy terminating TLS in front of Node on loopback, and a daily backup
timer.

Full detail, and what to do when a step fails, is in
[`../server/deploy/RUNBOOK.md`](../server/deploy/RUNBOOK.md).

### The local way (same Mac, for trying it out)

```bash
brew install node
cd server
cp .env.example .env
```

Edit `.env`:

- `DATABASE_URL` — **a different database from the desktop's.**
  `postgres://$(whoami)@localhost:5432/bookworm_dev`. This is not a
  preference: the server's ownership migration adds a `NOT NULL user_id` column
  that the desktop knows nothing about, so pointing the server at `wormbook`
  would stop the desktop being able to add a book. `npm run migrate` refuses to
  run against `wormbook` for exactly this reason.
- `JWT_SECRET` — `openssl rand -base64 48`. The server refuses to start with
  anything under 32 characters.

Then:

```bash
createdb bookworm_dev
npm ci
npm run migrate:up
SEED_EMAIL=you@example.com SEED_PASSWORD='choose-a-good-one' npm run seed:user
npm start
```

Check it:

```bash
curl -s localhost:3000/health     # {"status":"ok"}
```

A locally-run server is plain HTTP on loopback. That is fine for the desktop and
fine for the simulator; a physical iPhone needs the VPS route, or at least a
machine it can reach with a certificate it trusts.

### Verify it from outside

```bash
server/scripts/smoke-test.sh https://api.example.com
```

Ten checks — health, anonymous rejection, login, create, progress, the sync feed
and its cursor, token rotation, delete, logout.

---

## Step 3 — decide which library wins

**Read this before connecting anything.** The first exchange between a desktop
and a server is the one moment where data can be lost, and it is the one moment
the software will not decide for you.

- Desktop has books, server is empty → everything uploads. Normal.
- Server has books, desktop is empty → everything downloads. Normal.
- **Both hold data** → BookWorm stops and asks. It cannot merge them: rows are
  matched by `uuid`, minted by whichever client created them, so the same book
  added on two machines is two rows with two uuids and nothing can tell that
  from two different books. Whichever side you pick, the other's contents are
  not merged in.

So: start from a fresh server, or from a fresh desktop, and take a backup first
(Settings → Backup) if you have anything to lose.

---

## Step 4 — connect the desktop

BookWorm → **Settings → Sync**:

1. Server address — `https://api.example.com` (or `http://localhost:3000`).
2. Email and password — the account from step 2.
3. **Connect.**

The first exchange runs immediately, including cover upload, which is sequential
and takes a few seconds for a full library. After that it syncs on its own:
every two minutes, three seconds after you edit something, when you bring the
window to the front, and at shutdown. The button in the Library header does it
on demand and spins while it works.

If something looks wrong, the log is at:

```
~/Library/Application Support/sqtx/BookWorm/sync.log
```

It records every exchange and why one did nothing.

> **After rebuilding the desktop app you must connect once more.** The app is
> unsigned, so each build is a new identity to macOS and cannot read the token
> the previous build stored. The log says `no session could be restored`. This
> is expected, not a fault.

---

## Step 5 — the iPhone app

Requires **Xcode 26+** and the iOS platform support (about 15 GB — check
`df -h /System/Volumes/Data` first):

```bash
xcodebuild -downloadPlatform iOS
```

Run the logic tests, which need neither simulator nor signing:

```bash
cd ios/BookWormKit && swift test
```

Then:

1. `open ios/BookWormProgress.xcodeproj`
2. Xcode → Settings → Accounts → add your Apple ID (a free one is enough).
3. Select the **BookWormProgress** target → **Signing & Capabilities** → set
   **Team** to your personal team. This is the one manual step; the project
   ships with `DEVELOPMENT_TEAM` empty so the file is not tied to one Apple ID.
   If the bundle identifier is taken, change it to anything unique.
4. Connect the iPhone, select it as the destination, press Run.
5. On the phone, first time only: Settings → General → VPN & Device Management →
   trust your developer certificate, then launch the app again.
6. In the app: server address, email, password. Leave **Stay signed in on this
   phone** on.

### The seven-day expiry

A free Apple ID signs an app for seven days. After that it refuses to launch
until you press Run again with the phone connected — under a minute. That is the
entire cost of not paying for the Developer Program, and it was a deliberate
trade: the paid account buys convenience, not capability.

Because a re-deploy can reinstall rather than re-sign, the Keychain item may go
with it. The app treats that as an ordinary path and says so; queued writes
survive it, since they live in Application Support rather than the Keychain.

---

## Step 6 — prove it works, both ways

Not "it looks right" — check the thing that would fail silently.

**Mac → phone.** Change a page on the Mac. Within about two minutes (or straight
away if you press the sync button), pull the list down on the phone. The new
number is there.

**Phone → Mac.** Move a slider on the phone, confirm with ✓. On the Mac the page
changes **and a reading session dated today appears** in Statistics → Sessions.
Check the session, not just the number: recording it is the whole reason the
progress endpoint exists, and its absence is exactly what a `PATCH` would have
caused without any error.

---

## Keeping it running

- **Server upgrades** — `server/deploy/RUNBOOK.md`, section *Upgrades*. Take the
  backup before the migration, and confirm `git pull` actually reported new
  commits; a refusal on ownership grounds prints a message and exits, and the
  `npm ci` that follows happily reinstalls what you already had.
- **Server backups** — a systemd timer writes a dump plus the covers to
  `/var/lib/bookworm/backups`, daily out of the box, keeping the newest 14.
  Both are one command to change:

  ```bash
  BC=/opt/bookworm/server/scripts/backup-config.sh
  sudo $BC status          # schedule, retention, what is on disk, free space
  sudo $BC set-interval 6h # hourly | 6h | daily | weekly | any OnCalendar spec
  sudo $BC set-keep 30     # how many backups exist at once
  sudo $BC at_now          # take a backup now, and wait for the verdict
  ```

  A backup is deleted together with its cover archive, and rotation happens only
  after a successful run, so a failing job can never remove the last good one.
  Detail in [`../server/deploy/RUNBOOK.md`](../server/deploy/RUNBOOK.md).
- **Desktop backups** — Settings → Backup. Independent of the server, and worth
  keeping even with sync on: the server is a copy, not an archive, and a
  deletion propagates.
- **The desktop needs no server.** If the server goes away, the Qt app keeps
  working exactly as it did before you connected it.
