# BookWorm — how the whole thing works

Three programs, one library. This document explains what each part is, how they
fit together, and — more usefully — the handful of rules that hold the system
upright. Every rule below was broken at least once during development; each one
cost real time, and each is cheaper to read than to rediscover.

For the exact HTTP contract see [`API.md`](API.md). For installing any of this,
see [`INSTALL-DESKTOP.md`](INSTALL-DESKTOP.md) or [`INSTALL-FULL.md`](INSTALL-FULL.md).

---

## 1. The parts

```
┌─────────────────────┐        ┌──────────────────────┐        ┌──────────────────┐
│  desktop/           │        │  server/             │        │  ios/            │
│  Qt6 C++/QML, macOS │◄──────►│  Node + Fastify      │◄──────►│  SwiftUI, iPhone │
│                     │  /v1/  │  PostgreSQL          │  /v1/  │                  │
│  local PostgreSQL   │  sync  │                      │  REST  │  no local library│
│  `wormbook`         │        │  `bookworm` (its own)│        │                  │
└─────────────────────┘        └──────────────────────┘        └──────────────────┘
     curates a library              holds the networked copy         records reading
```

**`desktop/`** — the whole application. Adding books, editing metadata, covers,
quotes, highlights, statistics, challenges, backups. It owns a PostgreSQL
database on the same machine and **works completely without a server**; sync is
off by default and says nothing about it.

**`server/`** — a single-user API. It exists so a second device can exist. It
has its **own** database, deliberately not the desktop's: the ownership
migration adds a `NOT NULL user_id` the desktop knows nothing about, so pointing
the server at `wormbook` would stop the desktop being able to insert a book.
`npm run migrate` refuses to run against `wormbook` for that reason.

**`ios/`** — one screen, one job: move the page count on books being read. It
holds no library of its own, writes one field through one endpoint, and
deliberately does **not** implement the sync protocol.

The two clients therefore speak to the server in different ways, and this is a
design decision rather than an accident:

| | desktop | iOS |
| --- | --- | --- |
| Protocol | `/v1/sync` — whole-library exchange | plain REST — `/v1/books`, `/v1/books/:id/progress` |
| Local store | full PostgreSQL copy | a cache and a small write queue |
| Offline | fully usable | reads from cache, queues writes |
| Identity of a row | `uuid`, minted by whichever client created it | `id`, the server's integer |

---

## 2. The desktop application

```
User → QML signal → BookController (Q_INVOKABLE) → DatabaseManager → PostgreSQL
                                                 ↓
                                   BookModel::setBooks() → QML bindings → UI
```

- **DatabaseManager** — singleton. One connection, all SQL, and idempotent
  schema migrations that run on every launch (`ALTER TABLE … ADD COLUMN IF NOT
  EXISTS`). There is no migration tool; the schema catches up by itself.
- **Book** — a plain struct, 25 fields.
- **BookModel** — `QAbstractListModel`, 23 roles. The Library grid uses several
  of these at once: a priority model and one per status, so the page can render
  labelled sections without the QML re-sorting anything.
- **BookController** — the only type QML talks to for data. Filters, sorting,
  CSV, Markdown export, undo of a delete.
- **StatisticsProvider** — every statistic is a SQL query, not a loop over the
  model; year filtering happens in the database.
- **SyncManager** — everything network. Off unless configured.
- **BackupManager** — `pg_dump` + covers + manifest, zipped and verified before
  it reaches the destination.

### Sync on the desktop, in order

1. **On launch** — push, then pull. Push first, always: a pull alone strands
   anything edited while the last run was offline.
2. **Every two minutes**, and when the window is brought to the front (unless an
   exchange happened in the last twenty seconds).
3. **Three seconds after an edit**, restarted by each further edit, so one
   editing session is one exchange.
4. **On shutdown**, bounded by a six-second deadline. Exceeding it costs
   nothing: the cursor and the deletion queue only advance on success.

A row arriving from the server is written by `SyncRepository`, which is
deliberately a different path from `DatabaseManager` — see rule 1 below.

---

## 3. The server

Fastify, PostgreSQL, one account. No registration endpoint; the account is
created by `npm run seed:user`.

- **Auth** — short-lived access token, rotating refresh token. Presenting a
  refresh token twice is treated as theft and revokes every session.
- **Books** — REST CRUD, plus `/progress` and `/complete`, which exist because
  each does two things atomically (see rule 3).
- **Covers** — stored by the SHA-256 of the uploaded bytes, served as WebP,
  cached for a year because a hash always denotes the same bytes.
- **Sync** — `GET /v1/sync?since=…` pulls; `POST /v1/sync` pushes and pulls in
  one exchange.

Deployment is a systemd unit behind Caddy, which terminates TLS. PostgreSQL
listens on loopback only. See [`../server/deploy/RUNBOOK.md`](../server/deploy/RUNBOOK.md).

**Backups** are a second systemd unit on a timer, and everything about them is
one command — `scripts/backup-config.sh status | set-interval | set-keep |
at_now | prune | list`. Retention counts backups rather than days, because age
and interval interact badly: "keep 30 days" of hourly backups is 720 archives.
A dump and its cover archive are one unit and are deleted together, since a
database restored into a library with no images fails silently — the book rows
still carry their hashes. Rotation runs only after a *successful* backup, so a
broken job cannot delete the last good one, and the schedule is a systemd
drop-in so an upgrade cannot reset it.

---

## 4. The iOS app

- **`BookWormKit`** — a local Swift package holding the models, HTTP, the write
  queue and the log. It builds for macOS too, which is the point: `swift test`
  runs the whole of the logic in about a second with no simulator and no code
  signing.
- **The app target** — SwiftUI, the Keychain, cover decoding. Nothing else.

Behaviour worth knowing: writes are persisted to a queue *before* they are
attempted; the list re-reads the server every minute while the app is on screen;
a page change is a proposal until it is confirmed, so brushing a slider while
scrolling cannot rewrite a page.

---

## 5. The rules that hold it together

### Rule 1 — `updated_at` and `client_updated_at` are not interchangeable

Every synced row carries two timestamps and they answer different questions.

- **`updated_at`** — server time. It drives the **pull cursor**: "give me
  everything that changed after this".
- **`client_updated_at`** — when the *user* made the edit. It decides
  **last-write-wins**, and both sides apply the same comparison.

Three consequences, each of which has bitten:

1. A write that moves only `updated_at` is *sent* to the other clients and then
   **discarded** by their merge rule, because it arrives claiming to be as old
   as the row they already hold. Nothing errors. This is what made a book
   starred on the phone never appear on the Mac.
2. A local edit that moves neither is never even selected for the push
   (`WHERE client_updated_at > cursor`). This is what made the Mac's edits never
   reach the phone — forty-seven of them, silently.
3. Therefore: **every local write stamps `client_updated_at`; the sync apply
   path never does.** A row from the server keeps the edit time it came with, or
   both sides stop agreeing about who won.

### Rule 2 — rows are matched by `uuid`, never by `id`

`id` is per-database. `uuid` is minted by whichever client created the row and
travels with it. This is also why two libraries that both already hold data
**cannot be merged automatically**: the same book added on two machines has two
uuids, and nothing can distinguish that from two different books. The desktop
asks the user which side wins rather than guessing.

### Rule 3 — progress is not a field, it is an operation

`POST /v1/books/:id/progress` writes the book **and** records a reading session,
atomically. A client that instead `PATCH`es `currentPage` gets a book whose
statistics are quietly wrong, and a `200` telling it everything is fine. The
desktop's streaks, pages-per-day chart and heatmap are all built from those
sessions.

Reading sessions merge with `LEAST`/`GREATEST` on a `UNIQUE (book_id,
session_date, source)` key, so pushing the same day twice is safe and
order-independent. That key must never gain `user_id` — CI pins it.

### Rule 4 — `null` is not `0`

A book with no recorded page count is not a book of zero pages. Writing the
wrong one is a silent edit of the user's data; it happened once, to 38 books.
The iOS app shows such books as *not started* and keeps the stored value `null`
until the user sets one.

### Rule 5 — a cover's hash is of the bytes that were *uploaded*

The server stores a re-encoded WebP, so a **downloaded file never hashes to its
own name**. Deciding "has this cover changed?" by hashing something you
downloaded produces an endless upload loop. The desktop's rule is about *where
the file came from*, not what it is called: a file living in the download
directory is never uploaded.

Covers deduplicate, so two books routinely share one file. Both sides treat
"this already exists" as the normal case.

### Rule 6 — never block the interface on the network or the Keychain

Both can take arbitrarily long, and one of them can put a system dialog in front
of the user. The desktop once failed to draw its window at all because a
Keychain read on the main thread was waiting behind a panel nobody could see.
The desktop reads it on a worker thread with interaction refused; iOS reads it
off the main actor.

Practical consequence on both platforms: **the app is unsigned or personally
signed, so every rebuild is a new identity and the stored token is unreadable.
Reconnecting once after a rebuild is a normal path, not an error** — and both
apps word it that way.

### Rule 7 — a failed write stays queued; a refused one does not

Anything the server could plausibly accept later (offline, 429, 5xx) stays on
disk until it is confirmed. Anything it will always refuse (400, 404) is dropped
and reported, because an entry that can never succeed is a lie about what is
pending. A queued write that the server turns out to already hold is dropped
too — otherwise it masks that book forever.

### Rule 8 — log what was attempted

"Nothing happened" and "nothing was attempted" are indistinguishable from
outside, and telling them apart is most of the work when sync misbehaves. The
desktop writes `sync.log` in its application-support directory; the iOS app
shows an Activity list in Settings.

---

## 6. Data model

`books` is the centre; everything else hangs off it.

```
books ──┬── book_tags ── tags
        ├── favorite_quotes
        ├── highlights
        └── reading_sessions        challenges (independent)
```

Book fields: `title`, `author`, `genre`, `pageCount`, `startDate`, `endDate`,
`rating` (1–6), `status` (`reading` | `read` | `planned` | `abandoned`),
`notes`, `isbn`, `publisher`, `publicationYear`, `publicationDate`, `language`,
`coverImagePath` (local, never synced), `coverHash` (synced), `itemType`,
`isNonFiction`, `audioMode`, `currentPage`, `series`, `summary`, `review`,
`readCount`, `isPriority`, `tags`.

Deletions are **soft**: a tombstone so the deletion can propagate, and so it can
be undone. A client must treat a tombstoned row as gone, and must keep unsent
deletions queued until the push succeeds — clearing the queue on failure loses
them permanently.

---

## 7. Repository layout

```
BookWorm/
├── README.md                     start here
├── docs/
│   ├── ARCHITECTURE.md           this file
│   ├── API.md                    the HTTP contract
│   ├── INSTALL-DESKTOP.md        desktop only
│   └── INSTALL-FULL.md           desktop + server + iPhone
├── desktop/                      Qt6 C++/QML — CMake
├── server/                       Node/Fastify — npm, node-pg-migrate
│   └── deploy/RUNBOOK.md         provisioning a VPS
└── ios/                          Swift/SwiftUI — Xcode + a local SwiftPM package
```

CI is path-filtered: a desktop change never spends a macOS runner on the Node
pipeline, and vice versa.

---

## 8. Conventions

- One branch per change, a pull request into `dev`. `main` moves only at release
  time, and every release gets an annotated tag.
- The repository is public. Code, comments, commits and documentation are in
  English; the user interface is bilingual (English / Polish, auto-detected).
- Secrets never enter the repository. `.env` is ignored, tokens live in the
  Keychain, and the server refuses to start with a JWT secret under 32
  characters — a weak secret boots happily and forges cleanly, which is worse
  than a missing one.
