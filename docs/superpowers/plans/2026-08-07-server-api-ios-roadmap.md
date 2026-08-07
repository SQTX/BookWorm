# Server, API and iOS Client — Roadmap

**Goal:** Move BookWorm from a single-user desktop app talking to `localhost:5432` to a multi-tenant service: PostgreSQL and a REST API on a VPS, the existing Qt desktop app as the first API client, and a free/test iOS app as the second.

**Baseline:** `v1.0.0` (commit `2dbe3c3`) — the last desktop-only version. Everything in this roadmap is measured against it.

**Status:** Planning. No phase started.

**Branch policy:** Every phase, and every fix inside a phase, gets its own branch and its own PR into `dev`. Nothing is committed straight to `dev` or `main`. `main` moves only at release time, and every release gets an annotated tag.

---

## Read This First

The user's database is real data — 95 books, reading sessions, ratings, notes accumulated over time. There is no other copy beyond the ZIP backups.

Rules for every phase below:

1. **Take a backup before any schema migration.** The app already has a verified backup path (Settings → Backup); use it, and record the archive path in the phase's findings.
2. **Develop migrations against a scratch database**, never against `wormbook`.
3. **Postgres never listens on a public interface.** Not during development, not "temporarily for testing". The moment it has a public port it will be found and attacked — Postgres on 5432 is scanned continuously.
4. A migration that cannot be rolled back must be proven on a restored copy of the real dump before it touches the real database.

Scratch database pattern, already used by the restore work:
```bash
createdb wormbook_dev_scratch
psql -q -d wormbook_dev_scratch -f /path/to/database.sql
# ... test against wormbook_dev_scratch ...
dropdb wormbook_dev_scratch
```

---

## Current State (v1.0.0)

| Aspect | Today |
| --- | --- |
| Data access | `DatabaseManager` singleton, direct `QSqlDatabase` calls from the desktop process |
| Connection | `localhost:5432`, database `wormbook`, user `sqtx`, **no password** |
| Ownership | None. Every row is implicitly the single user's |
| Covers | Absolute filesystem paths in `books.cover_image_path`, pointing wherever the user picked the file |
| Sync | None. One machine, one copy |
| Schema | 7 tables: `books`, `tags`, `book_tags`, `favorite_quotes`, `highlights`, `challenges`, `reading_sessions` |
| Migrations | Idempotent `ALTER TABLE ... ADD COLUMN IF NOT EXISTS` in `DatabaseManager::initializeSchema()`, run on every launch |

Three properties of the current code matter for what follows:

- **`initializeSchema()` is already an idempotent migration runner.** It is the right place to hang the multi-tenant migration, and it already runs on every client launch.
- **`recordSession()` is already sync-friendly.** The `ON CONFLICT (book_id, session_date, source) DO UPDATE SET page_start = LEAST(...), page_end = GREATEST(...)` merge is idempotent and order-independent: two clients can push the same session in any order and converge on the same row. This is a rare property — preserve it rather than replacing it with last-write-wins.
- **`addPages()` and `markAsRead()` are the only progress paths**, and both write the book *and* the session. Any API must keep that invariant server-side, or a client will be able to bypass session recording.

---

## Target Architecture

```
iOS app  ─┐
          ├─→  HTTPS  →  REST API  →  PostgreSQL   (VPS, private network)
Desktop  ─┘                    ↓
                         Object storage  (covers, content-addressed)
```

- Clients never speak SQL. `DatabaseManager` on the desktop becomes an API client behind the same interface, so `BookController` and all QML stay unchanged.
- Covers are uploaded to the server, re-encoded, and stored by content hash.
- The API owns every business invariant that the desktop currently enforces in C++.

---

## Sizing (measured, not guessed)

From the user's own library on 2026-08-07:

| Metric | Value |
| --- | --- |
| Books | 95 |
| `books` table | 152 kB → **~1.6 kB per book** |
| Whole `wormbook` database | 8.4 MB (~7.5 MB is empty PostgreSQL catalog overhead) |
| Covers | 102 files, 7.9 MB — **avg 79 kB**, median 47 kB, p90 132 kB, max 1.34 MB |

Covers are ~98% of the volume. Text is noise.

**Per user, 500 books:**

| Item | Unoptimised | Re-encoded (WebP 400×600 + thumbnail) |
| --- | --- | --- |
| Book rows + quotes, highlights, notes | ~3 MB | ~3 MB |
| `reading_sessions`, 10 years (~7k rows) | ~2 MB | ~2 MB |
| Covers | 40 MB | **~22 MB** |
| **Total** | **~45 MB** | **~27 MB** |

**40 GB VPS disk**, after subtracting OS (2–3 GB), PostgreSQL + WAL (1–2 GB), runtime and images (2–5 GB) and 20% headroom, leaves **~25–28 GB for user data** — provided backups go off-box.

| Scale | Usage | Fits in 40 GB? |
| --- | --- | --- |
| 1–10 accounts × 500 books | 0.05–0.5 GB | Enormous headroom |
| 100 accounts | ~3 GB | Comfortable |
| 1000 accounts, covers optimised | ~27 GB | Tight but fits |
| 1000 accounts, covers as-uploaded | ~45 GB | **Does not fit** |

Verdict: 40 GB is ample for the intended scale. **RAM is the real constraint** — 2 GB minimum, 4 GB recommended (PostgreSQL `shared_buffers` 512 MB + API + OS).

Two decisions are cheap now and expensive to retrofit, so they belong in Phase 2, not "later":
1. **Server-side re-encoding on upload.** The grid card renders covers at 180×300; storing a 1.34 MB original is waste.
2. **Content-addressed storage** — filename is the SHA-256 of the file bytes. The same popular cover is stored once for all users, so the marginal cover cost of a new account approaches zero.

---

## Phases

Each phase is one or more branches and PRs into `dev`. A phase is done when its PR is merged and its exit criteria are demonstrably met.

### Phase 0 — Groundwork *(no server yet)*

Removes the assumptions that would otherwise block everything else.

- [ ] Move DB credentials out of `constants.h` into runtime configuration (env vars / `QSettings`), keeping the current local defaults so nothing breaks
- [ ] Set a password on the local `wormbook` role and prove the app works with authentication on
- [ ] Write down the full current schema as a numbered baseline migration, so the server and desktop share one source of truth instead of `initializeSchema()` being the only definition
- [ ] Decide the API stack and record the choice as an ADR *(see Open Questions)*

**Exit:** desktop app runs against a password-protected local PostgreSQL, configured at runtime, with the schema captured as a versioned migration.

### Phase 1 — Multi-tenant schema

The largest and least reversible change. Do it locally, against a scratch database, before any VPS exists.

- [ ] `users` table: id, email, password hash (Argon2id), created_at, verified flag
- [ ] Split the global book catalogue from per-user data. Title, author, ISBN, publisher, publication year, cover — global and shareable. Status, rating, current page, dates, `is_priority`, `read_count`, notes, summary, review — per user
- [ ] Add owner scoping to `tags`, `book_tags`, `favorite_quotes`, `highlights`, `challenges`, `reading_sessions`
- [ ] Composite indexes leading with the owner column on every scoped table
- [ ] Row-level security policies as defence in depth, so an API bug cannot leak across accounts
- [ ] Migration that assigns all existing rows to a first user account, run against a restored copy of the real dump and verified by row counts per table

**Exit:** a restored copy of the real database migrates cleanly, all 95 books belong to one account, and the desktop app still shows exactly what it showed at `v1.0.0`.

> The catalogue/instance split is the part to get right now. Bolting it on after covers and API clients exist means rewriting both.

### Phase 2 — API and authentication

- [ ] Auth: registration, login, refresh tokens, password reset. Argon2id hashing, short-lived access tokens
- [ ] CRUD endpoints mirroring `BookController`'s invokable surface
- [ ] Progress endpoints that preserve the invariant: recording pages writes the book *and* the session in one transaction, server-side
- [ ] Session merge stays `ON CONFLICT ... LEAST/GREATEST` — idempotent, order-independent
- [ ] Cover upload: accept, validate as an image, re-encode to WebP 400×600 plus a 120×180 thumbnail, store by SHA-256, deduplicate
- [ ] Rate limiting on auth endpoints
- [ ] Health endpoint and structured logs

**Exit:** every operation the desktop app performs today is reachable over HTTP, covered by API tests, with a documented contract.

### Phase 3 — VPS deployment

- [ ] Provision (4 GB RAM, 2 vCPU, 40 GB disk), non-root user, SSH keys only, password auth off, firewall default-deny
- [ ] PostgreSQL with `listen_addresses = 'localhost'` — never public
- [ ] Reverse proxy with TLS
- [ ] Automated off-box backups (S3/R2/Backblaze), plus a **restore drill** — an untested backup is not a backup
- [ ] Disk and memory alerting

**Exit:** the API is reachable over HTTPS, PostgreSQL is unreachable from outside the host, and a backup has been restored onto a scratch instance successfully.

### Phase 4 — Desktop app onto the API

The desktop app is the proving ground: real data, real usage, and a UI already known to work.

- [ ] Reimplement `DatabaseManager`'s public interface over HTTP so `BookController` and all QML stay untouched
- [ ] Login UI and secure token storage (macOS Keychain)
- [ ] Local cache so the app is usable offline, flushing queued changes on reconnect
- [ ] One-time upload of the existing 95 books and their covers
- [ ] Sensible failure states — the app must not look broken when the network is down

**Exit:** the desktop app runs entirely against the VPS, the user's real library is intact, and pulling the network cable degrades gracefully instead of crashing.

### Phase 5 — iOS client

- [ ] Confirm the distribution route *(see Open Questions — this gates the whole phase)*
- [ ] Read-focused first cut: library list, book detail, add pages, mark as read
- [ ] Offline cache and queued writes, same contract as desktop
- [ ] Cover thumbnails, not full images, on list screens

**Exit:** the app installs on the user's iPhone, shows the real library, and recording progress on the phone is visible on the desktop.

---

## Open Questions

These block specific phases and should be answered before that phase starts, not during it.

1. **API stack?** Blocks Phase 0. Candidates: Go (single static binary, small memory footprint, good fit for 4 GB), Python/FastAPI (fastest to write), Node/TypeScript (shared types with a future web client). No strong reason to pick C++ just because the desktop app is C++.
2. **iOS: native SwiftUI or Qt?** Blocks Phase 5. Qt reuses QML but is a poor fit for App Store polish and iOS conventions. If the phone client stays read-focused, a native SwiftUI app over the REST API is small and will feel better. This choice does not affect Phases 0–4, so it can wait — but it should be answered before Phase 5 opens, not mid-phase.
3. **Distribution?** Blocks Phase 5. Without the Apple Developer Program ($99/year) the only route is sideloading via Xcode onto the user's own device: certificates expire after 7 days and there is a 3-app limit. TestFlight requires the paid account. "Test app for me" works free; "give it to someone to try" does not.
4. **Multi-user, or just the user's own devices?** Affects how much of Phase 1's tenancy work is actually needed and whether registration must be public. Cheaper to build the scoping now either way, but public registration brings abuse handling, email verification and GDPR-shaped obligations that a private instance does not.
5. **Conflict policy for concurrent book edits?** Reading sessions merge cleanly by construction. Editing the same book's rating on two devices while offline does not. Last-write-wins per field is probably enough at this scale, but it should be a decision, not an accident.

---

## Explicitly Out of Scope

- Web client
- Social features, sharing, public profiles
- Book metadata lookup from external catalogues
- Android

---

## Related

- Spec convention: `docs/superpowers/specs/`, plans in `docs/superpowers/plans/`
- Baseline release tag: `v1.0.0`
- Each phase gets its own design spec before implementation begins
