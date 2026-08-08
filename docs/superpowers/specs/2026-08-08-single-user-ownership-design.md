# Phase 1 — Ownership and Authentication (single user)

**Status:** Design. Not started.

**Goal:** Give every row an owner and put the API behind a login, so the database can move off `localhost` without being open to whoever finds it.

**Scope decision (2026-08-08):** the server is a private system for one person — the author's own devices. Not a product, not a family instance, not public.

**Baseline:** `v1.1.0`, plus the `server/` scaffold and the baseline migration on `dev`.

---

## What this phase is, in one paragraph

Add a `users` table with exactly one row, hang a `user_id` on the tables that represent user data, backfill the existing 95 books to that row, and put every client-facing endpoint behind a bearer token. Nothing else. The multi-account machinery — registration, email verification, password reset, row-level security, the global-catalogue split — is deliberately **not** built, and this document records why, and what would trigger building it.

## Why the scope shrank

An earlier draft of the roadmap argued for splitting a global book catalogue from per-user data during this phase, on the grounds that retrofitting it later would be expensive. That reasoning does not survive the single-user answer:

- The split exists to let many users share one copy of a book's metadata and cover. With one user there is nothing to share, so it buys **zero** and costs a join on every read.
- The retrofit it was meant to avoid is real but modest at this scale: a few hundred books, one migration, done on a machine the author controls, with no other clients to coordinate.

Building it now would be complexity carried for years against a benefit that may never arrive. **Deferred.**

The `user_id` scoping is the opposite case and stays, because the asymmetry runs the other way:

| | Now (1 user) | Later (retrofit) |
| --- | --- | --- |
| Add `user_id` column | One `ALTER`, backfill one value | Same `ALTER`, plus rewriting every query and endpoint that was written without it |
| Catalogue split | Two tables, joins everywhere, no benefit | One migration over a few hundred rows |

Do the cheap-now/expensive-later thing. Skip the expensive-now/cheap-later thing.

---

## Data model

### `users`

```
id            SERIAL PRIMARY KEY
email         CITEXT NOT NULL UNIQUE
password_hash TEXT NOT NULL          -- Argon2id, native binding
created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
```

One row, created by a seed script (below). No self-registration endpoint exists, so there is no signup path to attack.

`CITEXT` rather than `VARCHAR`: email is case-insensitive in practice, and enforcing that in the column beats remembering to lowercase at every call site. Requires `CREATE EXTENSION IF NOT EXISTS citext`.

### Ownership columns

`user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE` on:

- `books`
- `tags`
- `challenges`
- `reading_sessions`

**Not** on `book_tags`, `favorite_quotes`, `highlights` — those hang off a book and inherit its owner through the existing `ON DELETE CASCADE`. Duplicating the owner there would create two sources of truth that can disagree.

`reading_sessions` is the deliberate exception to that rule: it *could* reach its owner through `book_id`, but the statistics queries aggregate sessions by date across all books, and forcing a join through `books` on every one of them is a cost paid forever to avoid one column. Denormalised on purpose.

### Indexes

Every scoped table gets a composite index **leading with `user_id`**, because with an owner filter on every query a trailing `user_id` is close to useless:

```
books             (user_id, status)
books             (user_id, end_date)
tags              (user_id)
challenges        (user_id, deadline)
reading_sessions  (user_id, session_date)
```

The existing single-column indexes on `status`, `end_date`, `genre` and `deadline` are superseded by these and should be dropped in the same migration rather than left to accumulate.

### The constraint that must not break

`reading_sessions` currently has `UNIQUE (book_id, session_date, source)`. It stays exactly as is — **not** widened to include `user_id`.

`book_id` already implies the owner, so adding `user_id` to the key would weaken it: the same book could then hold two sessions for one date under different owners. The uniqueness is what makes `recordSession()`'s `ON CONFLICT ... LEAST/GREATEST` merge idempotent and order-independent, which is the property that will let the desktop and the phone push the same session in any order and converge. Preserve it.

---

## Migration

One numbered migration, additive, following the baseline.

1. `CREATE EXTENSION IF NOT EXISTS citext`
2. Create `users`
3. Insert the single account, taking email and password hash from environment variables — **never** a literal in the migration file, which is committed to a public repository
4. Add `user_id` to the four tables as **nullable**
5. Backfill every existing row to that account
6. `SET NOT NULL` on all four
7. Create the composite indexes, drop the superseded single-column ones

Steps 4–6 in that order rather than adding `NOT NULL` directly: a `NOT NULL` column with no default cannot be added to a populated table.

### Verification, before it touches anything real

- Restore a `pg_dump` of the live database into a scratch database
- Run the migration there
- Assert: `users` has exactly 1 row; every scoped table has 0 rows with `user_id IS NULL`; `books` still has 95 rows; the `reading_sessions` unique constraint is unchanged
- Round-trip `down` then `up`, confirm the schema is stable
- Only then run it against the real database, with a backup taken first

The desktop app must still work unchanged at this point — it does not know about `user_id`, and a `NOT NULL` column with no default would break its inserts. **Therefore the migration is not applied to the developer's live database until Phase 4 moves the desktop app onto the API.** Until then it lives on the server's own database only. This is the single most likely way to break the working app by accident, and it is the reason the ordering matters.

---

## Authentication

Minimal, but real. A private system on a public network still needs a lock.

- **Hashing:** Argon2id via a native binding. Not bcrypt, not a pure-JS implementation.
- **Login:** `POST /v1/auth/login` with email and password, returns a short-lived access token and a longer-lived refresh token.
- **Tokens:** signed with a secret from the environment. The secret is generated once, stored outside the repository, and rotating it logs every device out — acceptable for one user.
- **Transport:** the desktop app stores tokens in the macOS Keychain, never in `QSettings`, which is a plaintext plist.
- **Rate limiting** on the login route regardless of there being one account. One account means one password to brute-force, which makes the limit more useful, not less.
- **Everything under `/v1` requires a valid token**, enforced by a hook rather than per-route, so a new endpoint is protected by default instead of by remembering.

Not built: registration, email verification, password reset, sessions list, MFA. Password changes happen by re-running the seed script.

### Seed script

`npm run seed:user` — reads email and password from the environment, hashes, inserts or updates. Refuses to run if a user already exists unless explicitly forced, so it cannot silently overwrite the account.

---

## Out of scope, and what would bring it back

| Deferred | Trigger to build it |
| --- | --- |
| Global catalogue / per-user instance split | A second account exists **and** cover storage is measurably duplicated |
| Row-level security | A second account exists — RLS protects against cross-account leaks, which need two accounts to leak between |
| Self-registration, email verification, password reset | Anyone other than the author needs an account |
| Abuse handling, GDPR export and deletion | Public registration |

Recorded so that "we skipped it" stays a decision with a condition attached, rather than something quietly forgotten.

---

## Open questions

1. **Does the desktop app keep working against the local database during Phases 2–3?** The plan above says yes — the migration lands on the server's database only, and the desktop app is untouched until Phase 4. Worth confirming, because the alternative (migrating the local database now) means the desktop app breaks immediately and Phase 4 becomes urgent rather than planned.
2. **Token lifetime?** A private single-user system can afford long-lived tokens; the trade is that a stolen token stays valid longer. Suggest 15 minutes for access and 30 days for refresh, revisited if it proves annoying on the phone.

---

## Success criteria

- [ ] `users` holds exactly one account, created without any credential appearing in the repository
- [ ] All four scoped tables carry a `NOT NULL user_id` and no orphan rows
- [ ] The `reading_sessions` unique constraint is byte-identical to the baseline
- [ ] `POST /v1/auth/login` returns tokens for the right password and a uniform failure for a wrong email or a wrong password — distinguishing them tells an attacker which half was right
- [ ] Every `/v1` route rejects a missing, malformed or expired token
- [ ] The migration has been proven on a restored copy of the real dump
- [ ] The desktop app still runs, untouched, against its own database
