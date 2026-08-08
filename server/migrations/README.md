# Migrations

Numbered SQL migrations applied by `node-pg-migrate`, which records what it has
already run in a `pgmigrations` table.

**The server owns the schema.** Clients never issue DDL. This matters because
the desktop app currently creates the schema itself, in
`DatabaseManager::initializeSchema()`, with idempotent
`ALTER TABLE ... ADD COLUMN IF NOT EXISTS` statements on every launch. That
works only while exactly one program owns the database. Once the server exists,
"whichever client starts first defines the schema" has no single source of truth
and lets two machines drift apart.

Order of work:

1. **Baseline** — transcribe the schema `initializeSchema()` produces today into
   the first numbered migration. Verified by diffing a database built from the
   migration against a restored dump of the real one; it must be an exact match.
2. **Multi-tenancy** (Phase 1) — `users`, the global-catalogue/per-user split,
   owner scoping and row-level security.
3. `initializeSchema()`'s DDL is retired when the desktop app moves onto the API
   in Phase 4.

## Running

```bash
npm run migrate:up
```

Reads `DATABASE_URL` from `.env`, the same connection string the app uses, so
the two cannot disagree about which database they are pointed at.

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
