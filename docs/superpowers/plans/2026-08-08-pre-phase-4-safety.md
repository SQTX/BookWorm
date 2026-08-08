# Pre-Phase-4 Safety Net

**Purpose:** make it impossible to break the working desktop app by accident while the server is built, and make it provable that nothing was lost when the app is finally moved onto the API.

**Done:** 2026-08-08, before any Phase 1 work.

---

## The hazard this closes

The ownership migration adds `user_id INTEGER NOT NULL` to `books`. The desktop app knows nothing about that column, so the moment the migration lands on `wormbook` the app can no longer insert a book.

The failure is quiet. Nothing breaks at launch; the library still displays; it fails the next time a book is added, which could be days later — long after the cause is obvious.

Worse, the server's `.env.example` originally shipped with `DATABASE_URL` pointing at `wormbook`. Anyone copying it and running `npm run migrate:up` — the documented first step — would have migrated the live library. The trap was in the repository, on the happy path, waiting.

## What was done

### 1. A proven backup

```
~/Backups/BookWorm/wormbook_pre-phase4_2026-08-08_2131.dump   (custom format, 29 kB)
~/Backups/BookWorm/wormbook_pre-phase4_2026-08-08_2131.sql    (plain SQL, 44 kB)
```

**Restore drill run, not just assumed.** The custom-format dump was restored into a scratch database and every table compared against the live one:

| Table | Live | Restored |
| --- | --- | --- |
| books | 95 | 95 |
| tags | 8 | 8 |
| book_tags | 16 | 16 |
| favorite_quotes | 0 | 0 |
| highlights | 0 | 0 |
| challenges | 1 | 1 |
| reading_sessions | 12 | 12 |

The scratch database was dropped afterwards. An untested backup is not a backup — this one has been restored.

> These dumps cover the database only. Cover images live outside it, at absolute paths under `~/Pictures`, and no migration touches them. For a backup including covers, use the app's own Settings → Backup.

### 2. The dangerous default removed

`.env.example` now points at `bookworm_dev` — the server's own database — with a comment explaining why it is deliberately not `wormbook`.

### 3. A guard that refuses

`server/scripts/guard-database.js` runs before every `migrate` script and exits non-zero if `DATABASE_URL` names a protected database. Overriding it requires `ALLOW_LIVE_DATABASE=i-understand` exactly; truthy values like `1`, `true` or `yes` do not unlock it, because a guard that accepts anything non-empty gets bypassed by accident.

Verified against the real database:

- `DATABASE_URL=...wormbook npm run migrate:up` → **exit 1**, refused
- `wormbook` afterwards: no `pgmigrations` table, no `user_id` column, still 95 books — the migration never ran
- A wrong override value → **exit 1**
- `bookworm_dev` → migration applies normally, 8 tables

The error message says what to do, not merely that something is wrong. A guard that blocks without pointing at the fix gets disabled by whoever hits it.

### 4. A fingerprint for proving Phase 4 lost nothing

`server/scripts/library-fingerprint.sql` — read-only, deterministic.

```bash
psql -qtA -d wormbook -f server/scripts/library-fingerprint.sql
```

Baseline captured 2026-08-08, before any server work touched anything:

```
books=95
tags=8
book_tags=16
favorite_quotes=0
highlights=0
challenges=1
reading_sessions=12
status_reading=17
status_read=54
status_planned=24
total_pages_read=493
sum_read_count=54
books_fingerprint=f96bb371401850a75a588375ba116098
```

Row counts alone would not catch a book whose rating was silently reset, so the hash rolls up title, author, status, rating and progress — the fields a user would notice going wrong.

**Phase 4 exit criterion:** this output must be identical after the desktop app is running against the API. `status_abandoned` is absent because no book currently has that status; it will appear if one does, which is a real change rather than a fault.

---

## What remains dangerous

The guard protects the migration path. It does **not** protect against:

- `psql` run by hand against `wormbook`
- The desktop app's own `initializeSchema()`, which still owns the local schema until Phase 4
- Dropping the database outright

Those stay a matter of care. The guard closes the one route that was both easy to take and documented as the first step.
