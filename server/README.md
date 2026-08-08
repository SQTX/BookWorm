# BookWorm Server

Multi-tenant REST API backing the desktop and iOS clients.

**Status:** scaffold. Health endpoint and configuration only — no data endpoints,
no authentication, no schema yet. See the
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
cp .env.example .env
```

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
curl -s localhost:3000/v1/
```

## Testing

```bash
npm test
```

`node:test` plus Fastify's `inject()`. No port is bound and no PostgreSQL is
needed — the pool is stubbed. Nothing here touches a real database.

## Layout

```
server/
├── src/
│   ├── server.js      Process entry: real env, port binding, signals
│   ├── app.js         Fastify factory — testable, binds nothing
│   ├── config.js      Environment validation, fails fast at startup
│   ├── db.js          pg pool and liveness probe
│   └── routes/
│       └── health.js  Operational endpoints (unversioned by design)
├── migrations/        node-pg-migrate; see its README
└── test/
```

`server.js` holds only what a test must not do. Everything else is reachable
through `buildApp()`.

## Conventions

- **Every SQL value is a bound parameter** (`$1`, `$2`). No ORM means injection
  is no longer prevented by construction; string-concatenated SQL is a bug.
- **Client-facing routes live under `/v1`.** A released version never changes
  meaning. Phones cannot be force-updated, and the monorepo does nothing about
  that — only versioning does.
- **Every endpoint declares a response schema.** Without TypeScript this is the
  main barrier against leaking a field by accident.
- `/health` reports usability and nothing else — no versions, hostnames or
  database details.
- **No secrets in the repository.** Configuration comes from the environment.
