# Server, API and iOS Client — Roadmap

**Goal:** Move BookWorm from a single-user desktop app talking to `localhost:5432` to a multi-tenant service: PostgreSQL and a REST API on a VPS, the existing Qt desktop app as the first API client, and a free/test iOS app as the second.

**Baseline:** `v1.0.0` (commit `2dbe3c3`) — the last desktop-only version. Everything in this roadmap is measured against it.

**Status:** Planning. No phase started.

**Server stack:** Node.js, plain JavaScript, npm. Fastify, `pg` with hand-written SQL, `node-pg-migrate`. One repository, three directories. See [Decisions](#decisions).

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
iOS app  ─┐                 Node.js
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

## Decisions

### D1 — Server stack: Node.js *(decided 2026-08-07)*

The API is written in JavaScript on Node.js, managed with npm.

Consequences that shape the phases below:

- **Node LTS, pinned.** Pin the major version in `.nvmrc` and `package.json` `engines`, and use the same version on the VPS. Node's release cadence is fast enough that "whatever is installed" drifts.
- **Memory footprint is a real constraint, not a footnote.** A Node process on a 4 GB VPS sharing the box with PostgreSQL should run with an explicit `--max-old-space-size` rather than letting V8 size its heap against total system RAM — otherwise the two compete for the same memory under load.
- **Cover re-encoding is CPU-bound and must not run on the event loop.** `sharp` (libvips) releases the loop for the actual encode, which is why it is the right choice over pure-JS encoders. On 2 vCPU, cap concurrent encodes rather than accepting unbounded parallel uploads.
- **Argon2id needs a native binding** (`argon2` or `@node-rs/argon2`). Do not substitute a pure-JS implementation, and do not fall back to bcrypt without deciding to.
- **`npm ci` with a committed lockfile** for reproducible deploys. Never `npm install` on the server.
- **Dependency surface is the security surface.** npm's transitive dependency depth makes supply chain the most likely attack path in this stack. Keep direct dependencies few, enable `npm audit` in CI, and prefer the standard library where it is adequate.

### D2 — JavaScript, not TypeScript *(decided 2026-08-07)*

The server is written in plain JavaScript. TypeScript was considered and rejected as overkill for a storage-and-sync service.

Consequence: the type safety TS would have given at compile time has to come from somewhere else at runtime, or it does not exist at all. Two cheap substitutes, both required rather than optional:

- **Request and response schemas on every endpoint** (D3 gives them for free). Malformed input is rejected at the edge, before it reaches any handler.
- **JSDoc type annotations** on shared helpers and data shapes. Editors read them, so autocomplete and obvious-mistake detection still work without a build step.

### D3 — Framework: Fastify *(decided 2026-08-08)*

Chosen over Express and Nest.

- **Schema-based validation is built in, not bolted on.** With two independent clients (desktop and iOS) writing to one database, per-endpoint schemas are the barrier that stops a client bug from writing garbage — this matters more here than framework popularity.
- Express would need validation added as a separate dependency and applied by hand on every route; easy to forget one.
- Nest is heavier and designed around TypeScript decorators, which conflicts with [D2](#d2--javascript-not-typescript-decided-2026-08-07).

### D4 — Data access: `pg` with hand-written SQL *(decided 2026-08-08)*

No ORM, no query builder. The `pg` driver, parameterised SQL written by hand.

- **The schema already depends on what ORMs abstract worst:** `ON CONFLICT ... LEAST/GREATEST` session merging, `CHECK` constraints on rating and status, and the row-level security planned for Phase 1.
- **The queries already exist** in `DatabaseManager`. Porting known-good SQL from C++ beats re-deriving it through an abstraction.
- Prisma's main payoff is its generated types, which [D2](#d2--javascript-not-typescript-decided-2026-08-07) rules out.
- **Every query must be parameterised** (`$1`, `$2`). Hand-written SQL means SQL injection is now a live risk that an ORM would have removed by construction — string-concatenated SQL is a bug, not a shortcut.

### D5 — Migrations: numbered files, owned by the server *(decided 2026-08-08)*

Tool: `node-pg-migrate`. Plain SQL in numbered files, applied in order, with applied versions tracked in the database.

The project already has migrations — `DatabaseManager::initializeSchema()` runs idempotent `ALTER TABLE ... ADD COLUMN IF NOT EXISTS` on every launch. That works only while exactly one program owns the database.

Once the server exists, that assumption breaks: "whichever client starts first defines the schema" has no single source of truth and lets two machines drift apart. So:

- **The server owns the schema.** Clients never issue DDL.
- `initializeSchema()`'s DDL is retired once the desktop app moves onto the API (Phase 4), and the schema it currently creates becomes the numbered baseline migration in Phase 0.
- The same tool must produce that baseline *and* the Phase 1 tenancy migration. Picking it after Phase 1 would mean hand-reconciling the most dangerous migration in the project.

### D6 — One repository, three directories *(decided 2026-08-08, supersedes the earlier three-repo decision)*

All three codebases live in this repository:

```
BookWorm/
├── desktop/     C++/Qt, CMake      — the existing app
├── server/      Node.js, npm       — API and migrations
├── ios/         Xcode              — mobile client
└── docs/        shared planning
```

**Why this reverses the earlier call.** The first version of D6 chose three separate repositories and then listed contract drift as a cost to be managed by discipline. That weighed CI hygiene above contract integrity, which is the wrong order. A monorepo removes the drift structurally instead of asking a human to prevent it:

- **A server change and its client changes are one commit.** Half of a contract change cannot be merged — either the whole thing lands or none of it does. Across three repos the same change is three pull requests that someone has to keep in step, and eventually will not.
- **One working directory for a coding agent or a developer.** One `git status`, one branch, one review covering the whole change. Split repos force context switching and produce three disconnected PRs that no reviewer sees as a unit.
- The original objection — CMake and npm colliding in CI — is solved by path-filtered workflows (`on.push.paths`). The desktop workflow runs only for `desktop/**`, the server workflow only for `server/**`. That is configuration, not architecture.

**What a monorepo does not fix, and must not be assumed to fix.**

It removes drift *in source*. It does nothing about drift *in what is deployed*. The server updates in seconds; a phone in a user's pocket does not update at all until they choose to, and there is no way to force it. One commit in a repository does not change that.

So everything below stays mandatory from Phase 2, monorepo or not:

- **The API contract is a versioned OpenAPI document in `server/`.** It is the interface definition; clients follow it.
- **The API is versioned in the URL** (`/v1/...`) and a released version never changes meaning.
- **Breaking changes ship as a new version**, with the old one kept alive until clients have moved. Additive changes go to the existing version.
- Clients send a version identifier, so the server can tell a user their app is too old instead of failing obscurely.

> The trap to avoid: concluding that because the repo is unified, versioning is unnecessary. The monorepo protects the developer at edit time. Versioning protects the user at run time. They solve different problems and neither substitutes for the other.

**Migration into this layout** (Phase 0): `git mv` the existing tree into `desktop/`, leaving `docs/`, `README.md` and `.gitignore` at the root. History is preserved. CMake resource paths are relative to `CMakeLists.txt` and the tree moves as a unit, so they stay valid; `qrc:` paths are unaffected entirely. What must be updated: the build commands and paths in `CLAUDE.md`, `.gitignore`'s `build/` entry, and any absolute path in CI. The local `build/` directory is regenerated, not moved.

---

## Phases

Each phase is one or more branches and PRs into `dev`. A phase is done when its PR is merged and its exit criteria are demonstrably met.

### Phase 0 — Groundwork *(no server yet)*

Removes the assumptions that would otherwise block everything else.

- [ ] Move DB credentials out of `constants.h` into runtime configuration (env vars / `QSettings`), keeping the current local defaults so nothing breaks
- [ ] Set a password on the local `wormbook` role and prove the app works with authentication on
- [ ] Write down the full current schema as a numbered baseline migration, so the server and desktop share one source of truth instead of `initializeSchema()` being the only definition
- [x] ~~Decide the API stack~~ — see [D1](#d1--server-stack-nodejs-decided-2026-08-07)–[D6](#d6--three-repositories-decided-2026-08-08)
- [ ] Restructure into the monorepo layout: `git mv` the existing tree into `desktop/`, update `CLAUDE.md` build paths and `.gitignore`, confirm a clean build from the new location *(D6)*
- [ ] Add path-filtered CI workflows so `desktop/**` and `server/**` build independently
- [ ] Scaffold `server/`: Fastify, `pg`, `node-pg-migrate`, pinned LTS in `.nvmrc` and `engines`, committed lockfile, lint + format, test runner, `npm ci` in CI
- [ ] Port the schema `initializeSchema()` currently creates into the numbered baseline migration *(D5)* — verified by diffing a database built from the migrations against a restored dump of the real one

**Exit:** the repository is in the `desktop/` + `server/` layout and the desktop app still builds and runs from its new location against a password-protected local PostgreSQL, configured at runtime; `server/` holds a baseline migration that reproduces the current schema exactly; both CI workflows are green.

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

- [ ] Auth: registration, login, refresh tokens, password reset. Argon2id via a native binding, short-lived access tokens
- [ ] CRUD endpoints mirroring `BookController`'s invokable surface
- [ ] Progress endpoints that preserve the invariant: recording pages writes the book *and* the session in one transaction, server-side
- [ ] Session merge stays `ON CONFLICT ... LEAST/GREATEST` — idempotent, order-independent
- [ ] Cover upload: accept, **validate by decoding rather than by extension or declared MIME type**, re-encode to WebP 400×600 plus a 120×180 thumbnail, store by SHA-256, deduplicate
- [ ] Bound cover processing: cap upload size, cap concurrent encodes, stream uploads to disk instead of buffering whole files in memory
- [ ] Rate limiting on auth endpoints
- [ ] Health endpoint and structured logs
- [ ] Reject unhandled promise rejections loudly in development; ensure one failing request cannot take the process down in production

**Exit:** every operation the desktop app performs today is reachable over HTTP, covered by API tests, with a documented contract.

### Phase 3 — VPS deployment

- [ ] Provision (4 GB RAM, 2 vCPU, 40 GB disk), non-root user, SSH keys only, password auth off, firewall default-deny
- [ ] PostgreSQL with `listen_addresses = 'localhost'` — never public
- [ ] Reverse proxy with TLS in front of Node — Node does not terminate TLS or face the internet directly
- [ ] Node runs as an unprivileged user under a process supervisor that restarts it on crash, with `--max-old-space-size` set so it cannot starve PostgreSQL
- [ ] Deploy from a committed lockfile with `npm ci`; no `npm install` and no build toolchain on the server
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

> **Resolved:** stack, language, framework, data layer, migration tool and repository layout — see [D1](#d1--server-stack-nodejs-decided-2026-08-07)–[D6](#d6--three-repositories-decided-2026-08-08). Nothing now blocks Phase 0.

1. **Hosting provider and OS image?** Blocks Phase 3, not Phase 0. Needs to support 4 GB RAM / 2 vCPU / 40 GB and a current LTS Linux.
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
