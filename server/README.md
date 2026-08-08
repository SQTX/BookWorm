# BookWorm Server

Multi-tenant REST API backing the desktop and iOS clients.

**Status:** scaffold plus the baseline schema. Health endpoint, configuration and
migrations — no data endpoints and no authentication yet. See the
[roadmap](../docs/superpowers/plans/2026-08-07-server-api-ios-roadmap.md).

## Stack

| | | Why |
| --- | --- | --- |
| Node.js 24 (LTS) | pinned in `.nvmrc` | D1 |
| JavaScript | no TypeScript | D2 — schemas and JSDoc carry the weight instead |
| Fastify | HTTP | D3 — per-endpoint schema validation is built in |
| `pg` | database | D4 — hand-written SQL, no ORM |
| `node-pg-migrate` | schema | D5 — the server owns the schema |

Three runtime dependencies. That is deliberate: in this ecosystem the dependency
tree *is* the attack surface, so anything added should earn its place.

## Setup

```bash
cd server
npm ci
createdb bookworm_dev     # the server's own database — NOT wormbook
cp .env.example .env
openssl rand -base64 48   # paste into JWT_SECRET
npm run migrate:up
SEED_EMAIL=you@example.com SEED_PASSWORD='...' npm run seed:user
```

`wormbook` is the desktop app's live library and the migrations refuse to run
against it; see [MIGRATIONS.md](MIGRATIONS.md).

Then edit `.env`. **It is gitignored and must stay that way** — this repository
is public, and a committed credential is indexed by scanners within minutes.
`git revert` does not remove it from history.

## Running

```bash
npm run dev
```

Serves on `127.0.0.1:3000` by default. Loopback is intentional: in production a
reverse proxy terminates TLS and is the only thing that reaches this port. Node
never faces the internet directly.

```bash
curl -s localhost:3000/health   # {"status":"ok"} — 503 if the database is down

# Everything under /v1 needs a token.
TOKEN=$(curl -s localhost:3000/v1/auth/login \
  -H 'content-type: application/json' \
  -d '{"email":"you@example.com","password":"..."}' | jq -r .accessToken)

curl -s localhost:3000/v1/ -H "authorization: Bearer $TOKEN"
```

| Route | Auth | Notes |
| --- | --- | --- |
| `POST /v1/auth/login` | none | 5/minute per address |
| `POST /v1/auth/refresh` | none | Rotates; replaying a used token revokes every session |
| `POST /v1/auth/logout` | none | Always 204, so tokens cannot be probed |
| `GET /v1/books` | Bearer | `?status=` filter |
| `GET/POST/PATCH/DELETE /v1/books[/:id]` | Bearer | Owner-scoped; another account's book is a 404 |
| `POST /v1/books/:id/progress` | Bearer | Moves the page **and** logs a session, atomically |
| `POST /v1/books/:id/complete` | Bearer | Status, end date, reread tally, closing session |
| `GET /v1/sync?since=` | Bearer | Everything changed since the cursor, tombstones included |
| `POST /v1/sync` | Bearer | Push a batch, then get the canonical state back |
| everything else under `/v1` | Bearer | Enforced for the prefix, not per route |

### Sync

Push and pull happen in one exchange, push first: the client's own writes come
back as the server's canonical version, so it settles on what actually landed
rather than assuming its version won.

**The cursor is `serverTime` from the response, never the client's own clock.**
A clock a few seconds fast would skip every row written in the gap, permanently
and silently.

**Two timestamps, deliberately.** `updated_at` is server time and drives the
cursor; `client_updated_at` is the user's edit time and decides last-write-wins.
Using one column for both is a silent data-loss bug — see the
[design](../docs/superpowers/specs/2026-08-08-sync-protocol-design.md).

**Reading sessions do not use last-write-wins.** They merge with
`LEAST`/`GREATEST` on `(book_id, session_date, source)`, so two devices pushing
the same reading day converge in any order and pages read can only widen.

### Why progress is its own endpoint

Moving the current page and recording the reading session must happen together,
or the statistics drift away from the library. On the desktop that invariant is
enforced in C++ (`addPages()` and `markAsRead()` are the only progress paths and
both write the book *and* a session). Once clients speak HTTP they cannot be
trusted with it, so the server owns it: `currentPage` remains an editable field
for corrections, but only `/progress` creates reading.

## Testing

```bash
npm test
```

`node:test` plus Fastify's `inject()`. No port is bound and the pool is stubbed,
so most of the suite needs no PostgreSQL.

The auth tests are the exception and are skipped unless `TEST_DATABASE_URL` is
set. Rotation and reuse detection are SQL — a transaction, a `FOR UPDATE` lock
and a bulk revoke — and a stub would only assert that the code calls the queries
it calls, which is not the same as the behaviour being right.

```bash
TEST_DATABASE_URL=postgres://sqtx@localhost:5432/bookworm_dev npm test
```

## Layout

```
server/
├── src/
│   ├── server.js      Process entry: real env, port binding, signals
│   ├── app.js         Fastify factory — testable, binds nothing
│   ├── config.js      Environment validation, fails fast at startup
│   ├── db.js          pg pool and liveness probe
│   ├── auth/
│   │   ├── routes.js  login, refresh, logout
│   │   └── tokens.js  Issuing, rotation, reuse detection
│   ├── books/
│   │   ├── routes.js      Endpoints and schemas
│   │   ├── repository.js  SQL — every query owner-scoped
│   │   └── schemas.js     Field names, shared with the desktop app
│   └── routes/
│       └── health.js  Operational endpoints (unversioned by design)
├── migrations/        Numbered SQL — see MIGRATIONS.md
└── test/
```

`server.js` holds only what a test must not do. Everything else is reachable
through `buildApp()`.

## Conventions

- **Every SQL value is a bound parameter** (`$1`, `$2`). No ORM means injection
  is no longer prevented by construction; string-concatenated SQL is a bug.
- **Every query filters on `user_id`.** Same reasoning: without an ORM nothing
  adds the owner filter for you, and a query missing it is a leak waiting for a
  second account.
- **Another account's row is a 404, never a 403.** Distinguishing them confirms
  that a given id exists.
- **Unknown request fields are rejected, not stripped.** Fastify's default is to
  remove them, which turns a client's typo into a silent data loss that looks
  like a successful write.
- **Client-facing routes live under `/v1`.** A released version never changes
  meaning. Phones cannot be force-updated, and the monorepo does nothing about
  that — only versioning does.
- **Every endpoint declares a response schema.** Without TypeScript this is the
  main barrier against leaking a field by accident.
- `/health` reports usability and nothing else — no versions, hostnames or
  database details.
- **No secrets in the repository.** Configuration comes from the environment.
