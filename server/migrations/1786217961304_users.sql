-- The accounts table, deliberately split from the ownership migration that
-- follows it.
--
-- Splitting is not tidiness. On a database that already holds rows, the two
-- steps deadlock if combined: the ownership migration needs an account to
-- assign existing rows to, but the account cannot be created before the table
-- exists. Two migrations let an operator stop in between:
--
--   npx node-pg-migrate up 1     # this file — users table exists
--   npm run seed:user            # create the account
--   npx node-pg-migrate up       # ownership, backfills to that account
--
-- On an empty database (the server's own) the order does not matter: `up`
-- applies both, the backfill finds nothing to do, and the account is seeded
-- afterwards.
--
-- No credential appears here. Accounts are created by scripts/seed-user.js from
-- environment variables — this repository is public.

-- Up Migration

-- Case-insensitive email, enforced by the column type rather than by
-- remembering to lowercase at every call site.
CREATE EXTENSION IF NOT EXISTS citext;

CREATE TABLE users (
    id             SERIAL PRIMARY KEY,
    email          CITEXT NOT NULL UNIQUE,
    password_hash  TEXT NOT NULL,
    created_at     TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

-- Down Migration

DROP TABLE users;
-- citext is left installed: other things may come to depend on it, and dropping
-- an extension is not the business of the migration that happened to add it.
