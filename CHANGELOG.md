# Changelog

Notable changes to BookWorm. Newest first. Versions follow
[semantic versioning](https://semver.org): the desktop application's version is
the project's version, and the server and iPhone app ship alongside it.

Kept from v1.5.0 onward; earlier releases are described in their
[GitHub release notes](https://github.com/SQTX/BookWorm/releases).

---

## v1.7.0 — 2026-10-28

Things to earn and books to get back — and the month in which the desktop
refused to open three times, which is now the last such month.

### Added

- **🏆 Achievements.** Thirty-nine across ten metrics: library size, books read,
  books read this year, pages, series completed, genres, longest streak,
  rereads, ratings, notes taken. A panel slides in at the top right with
  artwork, a title, one line and a chime; several earned by one action queue
  and play in turn rather than stacking. A sidebar page lists all of them —
  earned ones accented and dated, locked ones dimmed with a progress bar and an
  `n / target` counter, because an achievement whose shape nobody can see is
  not a goal, it is a surprise (#67).
  - The first run seeds silently. A library of years satisfies a dozen of the
    catalogue at once, and fifteen notifications for things done long ago is
    not a welcome. Everything after that is a real event and is announced.
  - Nothing is ever taken away. Deleting a book can drop a count back under a
    threshold; the achievement stays.
  - Earning and announcing are separate facts. A book finished on the phone
    while the desktop is closed is earned then and announced at the next
    launch, oldest first; an application killed mid-notification has not
    consumed it.
  - Local to the machine and deliberately not synced: both clients read the
    same library and reach the same result on their own.
  - Artwork for the shelf and books-finished families, three tiers past a
    thousand, and a reference (`docs/achievements.md`) generated from the
    catalogue by `desktop/tools/gen-achievement-docs.py` — which refuses on a
    half-described entry rather than emitting a document with holes.
- **📚 Lending.** Record a book going to somebody, or coming from somebody,
  with a name, a date and a note — from the card's right-click menu or the
  book's own page. A book that is out wears its holder's name on its card. The
  Lending tab lists what is out, what is borrowed and, behind a toggle,
  everything returned, longest-out first: with no due dates, age is the only
  signal for "this one has probably been forgotten" (#67).
  - One book cannot be in two places. Enforced by a partial unique index in
    the database rather than a check in C++, so two windows cannot both slip
    between a read and a write.
  - Not a fifth status. A lent book is still read, or still being read, and
    a status would have made every filter and statistic decide what lending
    meant.
  - Local, like achievements, but for the opposite reason: a loan is primary
    data that exists nowhere else. The ZIP backup is what makes that safe.
- **The application says why it did not open.** A missing PostgreSQL driver,
  or a database that does not answer, now puts up a dialog naming the cause
  and the one command that fixes it, in Polish or English by system locale.
  Both used to log a line to the console and exit — from the Dock, the same
  as not opening at all (#68).
- `desktop/tools/build-qpsql-driver.sh` builds the Qt PostgreSQL driver in one
  command, against whatever `qtbase` Homebrew has installed (#68).

### Fixed

- **🔴 The desktop stopped opening after every Homebrew Qt upgrade.** Homebrew
  ships no PostgreSQL driver for Qt, so it is built by hand — and it was
  stored in Qt's own plugin tree inside the Cellar, which every `brew upgrade`
  of `qtbase` deletes. A version bump does it, and so does a bare revision bump
  (`6.11.2` → `6.11.2_1`) with no Qt change at all: three dead launches in one
  month. The driver now lives in the application's own data directory, which
  nothing else touches. It links through `/opt/homebrew/opt/*` symlinks, and a
  plugin built against Qt 6.N loads under any later 6.x, so one build lasts
  until Qt 7 (#68).
- **🔴 The desktop asked for the server password after a day away.** Not the
  tokens: macOS wanted to ask whether this build may read the stored session,
  and the application refused the question on the user's behalf, which failed
  the read and demanded the password. The panel is allowed through — one
  "Always Allow" settles it — every Keychain call runs on one serialised
  worker, never the main thread, and the bundle is re-signed ad-hoc after each
  build so there is an identity for the grant to attach to. Three token faults
  found alongside, each able to end a session on its own: a refresh that
  failed because the server was *unreachable* signed the user out; a rejected
  token stayed in the Keychain and was replayed at every launch; and launch
  fired two exchanges in the same second with the same expired token. Tokens
  now refresh before they expire, read from the JWT's own `exp`, and a
  rotation in flight collects further requests rather than starting a second
  one (#66).
- **🔴 Server: a rotation whose reply was lost was read as theft.** Refresh
  tokens are single-use and a replay revokes every session — right, except
  when the response carrying the new pair never arrived, which the desktop
  hits at shutdown on a six-second deadline. `refresh_tokens.replaced_by` now
  tells the two apart: a revoked token whose successor was never presented,
  within sixty seconds, gets a fresh pair; one whose successor has been used
  is a replay and everything goes. **Needs a migration** (`npm run
  migrate:up`) (#66).
- **🔴 Server: correcting a reading session's date wedged sync forever.** The
  push matched on (book, day, source), but `uuid` carries its own unique
  constraint and a statement can name only one target. A moved session hit
  the uuid key, the transaction aborted, and the client resent the same batch
  every two minutes — twenty minutes of it in one log. A row already known by
  its uuid is now moved rather than inserted, its pages folded into whichever
  day it lands on, so nothing is counted twice and the vacated day keeps
  nothing (#65).
- The notification's accent rail had square corners standing proud of the
  panel's curve. A narrow `Rectangle` cannot round past half its own width,
  whatever radius it is given; the accent is now a full-size plate with the
  surface inset on top, one shape whose curves cannot disagree (#67).

### Changed

- Build paths use `/opt/homebrew/opt/*` rather than versioned Cellar
  directories, so a Qt bump needs no edit to the build command.
  `docs/INSTALL-DESKTOP.md` §3 is one command now, and §4 no longer asks for
  the Qt version.
- `docs/ARCHITECTURE.md` describes the two desktop-only tables and why neither
  crosses the wire.
- The macOS bundle reports the real version. `project()` had said 1.0 since
  the first commit, so Finder's Get Info showed 1.0 for every release; it now
  follows the project version, as the About dialog always did.

### Housekeeping

- `.claude/worktrees/` is ignored (#69).

---

## v1.6.0 — 2026-08-12

Backups you can configure with a command, and the iOS refresh that was written
but never reached `main`.

### Added

- **Server backups are configurable without editing systemd.**
  `server/scripts/backup-config.sh` reports the schedule, the retention and what
  is on disk, and changes any of it in one command: `set-interval`, `set-keep`,
  `set-keep-days`, `at_now`, `prune`, `list`. Also available as `npm run
  backup:status`, `backup:now` and friends.
- **`at_now`** takes a backup immediately and **waits for the verdict** —
  printing the service's result, the tail of its output, the archive it wrote
  and how many are now kept. A command that returns instantly and leaves you to
  read a journal is not an answer to "back up now"; the question being asked is
  whether it worked.
- **Retention by count.** `KEEP_COUNT` (default 14) is now the primary rule:
  when a new backup is written, the oldest beyond that number is deleted
  together with its cover archive. The old age-based rule survives as an
  optional second one, off by default — "30 days" of hourly backups is 720
  archives, which is not what anyone picturing a month of backups means.
- Eleven tests covering retention, run against the real script and a real
  directory. It is the one part of the system whose job is to delete files.

### Changed

- Backup settings live in `/etc/bookworm/backup.env`, separate from the secrets
  in `api.env`. The installer writes it only when absent, so re-running the
  installer never resets an operator's choices, and `set-interval` writes a
  systemd drop-in rather than editing the unit, for the same reason.
- `RUNBOOK.md` section 9 rewritten around the new commands.
- `at_now` prints only the output of the run it just started. It had been
  showing the last twelve journal lines of the unit, so an earlier backup came
  along for the ride and a single command appeared to have run twice — a
  misleading answer to "did it work?" is worse than none.

### Recovered

- **iOS: the list re-reads the server every minute** while the app is on screen.
  The commit existed and was tested, and reached its branch after that branch
  had already been squashed into `dev` — so it shipped in no release. The phone
  had no periodic refresh at all in v1.5.0: it asked at launch, on foreground
  and on a pull, and otherwise showed what it had.

---

## v1.5.0 — 2026-08-12

The release where the library stopped living on one machine. An iPhone app, and
the synchronisation fixes that were needed to make a second device tell the
truth.

### Added

- **📱 iPhone app** (`ios/`) — one screen, one job: move the page count on the
  books you are reading. SwiftUI, no third-party packages, free personal signing
  (#48).
  - A page change is a **proposal until you confirm it**, so brushing the slider
    while scrolling the list cannot rewrite your reading history (#52).
  - The slider's fine adjustment: drag away from the track and the rate drops to
    a quarter, then a tenth. `−`/`+` move a single page.
  - Starred books are pinned to the top with a gold edge, ordered by how close
    to finished they are; a collapsed "to read" section sits at the bottom and
    is fetched only when opened.
  - Works offline: writes are persisted to a queue **before** they are
    attempted, coalesced per book, and flushed on launch, on foreground and on a
    refresh.
  - The list re-reads the server every minute while the app is on screen (#53).
  - "Stay signed in on this phone" survives the seven-day provisioning expiry
    that a free Apple ID imposes.
- **⚙️ Desktop: a synchronise button** in the Library header, its icon turning
  while an exchange runs (#56).
- **📚 Documentation** — `docs/ARCHITECTURE.md` for the whole system, and two
  installation guides: desktop-only and the full environment (#57).

### Fixed

- **🔴 Nothing edited on the Mac ever reached the server.** The push selects
  rows by `client_updated_at`, and no local write moved it — a trigger moved
  only `updated_at`. New books synced; edited ones never did, silently. Forty-
  seven of them on the author's machine. Local writes now stamp the clock, and a
  one-off repair releases what was stranded (#54).
- **🔴 The same fault on the server, in the other direction.** REST writes moved
  only the server clock, so a change made through the API *was* sent to other
  clients and then discarded by their merge rule as too old — with a `200` and
  no error anywhere. This affected `POST /books/:id/progress` too, which would
  have made the iPhone app's whole purpose fail quietly (#49).
- **Desktop: pulled rows were invisible until the app restarted.**
  `remoteChangesApplied` had never been connected to anything; the data was in
  the database and the window was showing a list built before the exchange
  finished (#51).
- **Desktop: nothing exchanged between launch and shutdown.** Now every two
  minutes, when the window comes forward, and three seconds after an edit (#51,
  #56).
- **iOS: a stuck queued write masked the server's value for that book forever.**
  A refresh now pushes before it pulls, and a queued write is dropped once the
  server is seen to already hold it (#53).
- **iOS: a pull-to-refresh could be answered from the URL cache**, so the
  request never left the phone and yesterday's page count was presented as
  fresh. Covers keep their cache; the library does not (#52).

### Changed

- `client_updated_at` is now written by every local write on both the desktop
  and the server, and never by either side's sync-apply path. The rule is
  documented in `docs/API.md` and `docs/ARCHITECTURE.md`.
- The desktop's version constant was three releases behind the tags; it now
  tracks them.

### Housekeeping

- Removed 2318 SwiftPM build artefacts committed by mistake, and taught
  `.gitignore` about `.build/` (#50).
- CI: a path-filtered iOS workflow — `swift test` for the logic package, an
  unsigned simulator build for the app.

---

## Earlier releases

| Version | |
| --- | --- |
| v1.4.x | The iOS brief, and the decision to distribute with free personal signing |
| v1.3.2 | Two-way sync in the desktop app, covers included, verified against the real library |
| v1.3.x | The server: Fastify API, PostgreSQL, deployed to a VPS behind Caddy |
| v1.2.x | Backup and restore, reading sessions, statistics |

See [Releases](https://github.com/SQTX/BookWorm/releases) for the detail.
