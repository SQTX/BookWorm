# Migrations

Numbered SQL migrations live in `migrations/` and are applied by
`node-pg-migrate`, which records what it has already run in a `pgmigrations`
table.

> This document sits here rather than in `migrations/` because node-pg-migrate
> requires a numeric prefix on **every** file in that directory and aborts the
> whole run on anything it cannot parse — a README included.

**The server owns the schema.** Clients never issue DDL. This matters because
the desktop app currently creates the schema itself, in
`DatabaseManager::initializeSchema()`, with idempotent
`ALTER TABLE ... ADD COLUMN IF NOT EXISTS` statements on every launch. That
works only while exactly one program owns the database. Once the server exists,
"whichever client starts first defines the schema" has no single source of truth
and lets two machines drift apart.

Order of work:

1. ~~**Baseline**~~ — done: `1786206990363_baseline-schema.sql` reproduces the
   schema `initializeSchema()` produces, verified byte-for-byte against a
   `pg_dump --schema-only` of the live database.
2. ~~**Ownership**~~ — done: `..._users.sql` and `..._ownership.sql`.
3. `initializeSchema()`'s DDL is retired when the desktop app moves onto the API
   in Phase 4.

## Why ownership is two migrations, not one

On a database that already holds rows the two steps deadlock if combined: the
backfill needs an account to assign existing rows to, but the account cannot be
created before the `users` table exists. Splitting lets an operator stop in
between:

```bash
npx node-pg-migrate up 1     # users table exists
npm run seed:user            # create the account
npx node-pg-migrate up       # ownership, backfills to that account
```

On an empty database — which is what the server actually has, since the real
library arrives through the API in Phase 4 — order does not matter: `up` applies
both, the backfill finds nothing to do, and the account is seeded afterwards.

Run against rows with no account, the ownership migration raises and the whole
thing rolls back rather than inventing an owner.

## Creating the account

```bash
SEED_EMAIL=you@example.com SEED_PASSWORD='...' npm run seed:user
```

Credentials come from the environment, never a file — this repository is public.
There is no registration endpoint, so this is the only way an account exists.
Re-running refuses to overwrite unless `SEED_FORCE=yes`.

## Why the baseline is a plain CREATE TABLE

It is written as final-state `CREATE TABLE` with inline constraints, not as a
replay of the app's `CREATE`-then-`ALTER` history. PostgreSQL derives object
names from the DDL form, so the inline style reproduces the live names exactly:

| DDL form | Generated name |
| --- | --- |
| `SERIAL PRIMARY KEY` | `<table>_id_seq`, `<table>_pkey` |
| inline `CHECK` | `<table>_<column>_check` |
| inline `UNIQUE` | `<table>_<columns>_key` |
| inline `REFERENCES` | `<table>_<column>_fkey` |

Column order is part of the comparison too, which is why the columns the app
added later (`item_type` onward) stay last, in the order it added them.

## Running

```bash
npm run migrate:up
```

Reads `DATABASE_URL` from `.env`, the same connection string the app uses, so
the two cannot disagree about which database they are pointed at.

### The guard

Every `migrate` script runs `scripts/guard-database.js` first, which refuses if
`DATABASE_URL` names the desktop app's live library (`wormbook`). The ownership
migration adds a `NOT NULL user_id` column that the desktop app knows nothing
about, so applying it there would stop the app inserting a book — quietly, until
the next time someone added one.

Override with `ALLOW_LIVE_DATABASE=i-understand`, which is only correct in
Phase 4, once the desktop app talks to the API instead of to PostgreSQL.

## Rules

- **Never edit a migration that has been applied anywhere.** Add a new one.
- Develop against a scratch database, never against `wormbook`:
  ```bash
  createdb wormbook_dev_scratch
  # ... test ...
  dropdb wormbook_dev_scratch
  ```
- Take a backup before running anything destructive against real data. The
  desktop app has a verified backup path in Settings → Backup.
- A migration that cannot be rolled back must be proven on a restored copy of
  the real dump first.
