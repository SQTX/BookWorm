# Changelog

Notable changes to BookWorm. Newest first. Versions follow
[semantic versioning](https://semver.org): the desktop application's version is
the project's version, and the server and iPhone app ship alongside it.

Kept from v1.5.0 onward; earlier releases are described in their
[GitHub release notes](https://github.com/SQTX/BookWorm/releases).

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
