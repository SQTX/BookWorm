-- Ownership: give every row an owner.
--
-- Design: docs/superpowers/specs/2026-08-08-single-user-ownership-design.md
--
-- The users table is created by the migration before this one, deliberately
-- split so an operator can seed an account in between on a database that
-- already holds rows. Combined, the two steps deadlock: the backfill needs an
-- account, and the account cannot exist before the table does.
--
-- user_id goes on books, tags, challenges and reading_sessions only.
-- book_tags, favorite_quotes and highlights hang off a book and inherit its
-- owner through the existing ON DELETE CASCADE; duplicating the owner there
-- would create two sources of truth that can disagree.
--
-- reading_sessions is the deliberate exception to that rule: it could reach its
-- owner via book_id, but the statistics queries aggregate sessions by date
-- across all books, and forcing a join through books on every one of those is a
-- cost paid forever to avoid one column.
--
-- On the server's own database this runs against empty tables — the real
-- library stays in wormbook until Phase 4 uploads it through the API, so the
-- backfill finds nothing to do. The nullable-backfill-NOT NULL sequence is kept
-- anyway so the migration is correct on a populated database too, and refuses
-- loudly rather than inventing an owner if it is run somewhere with rows and no
-- account.

-- Up Migration

-- Nullable first: a NOT NULL column with no default cannot be added to a table
-- that already has rows.
ALTER TABLE books            ADD COLUMN user_id INTEGER REFERENCES users(id) ON DELETE CASCADE;
ALTER TABLE tags             ADD COLUMN user_id INTEGER REFERENCES users(id) ON DELETE CASCADE;
ALTER TABLE challenges       ADD COLUMN user_id INTEGER REFERENCES users(id) ON DELETE CASCADE;
ALTER TABLE reading_sessions ADD COLUMN user_id INTEGER REFERENCES users(id) ON DELETE CASCADE;

DO $$
DECLARE
    owner_id INTEGER;
    orphans  INTEGER;
BEGIN
    SELECT min(id) INTO owner_id FROM users;

    SELECT (SELECT count(*) FROM books)
         + (SELECT count(*) FROM tags)
         + (SELECT count(*) FROM challenges)
         + (SELECT count(*) FROM reading_sessions)
      INTO orphans;

    IF orphans > 0 AND owner_id IS NULL THEN
        -- Refuse rather than invent an owner. Silently assigning rows to an
        -- account nobody created is worse than stopping here.
        RAISE EXCEPTION
            'Found % existing rows but no account to own them. Roll back to the users '
            'migration, run "npm run seed:user", then re-apply this one.', orphans;
    END IF;

    IF owner_id IS NOT NULL THEN
        UPDATE books            SET user_id = owner_id WHERE user_id IS NULL;
        UPDATE tags             SET user_id = owner_id WHERE user_id IS NULL;
        UPDATE challenges       SET user_id = owner_id WHERE user_id IS NULL;
        UPDATE reading_sessions SET user_id = owner_id WHERE user_id IS NULL;
    END IF;
END $$;

ALTER TABLE books            ALTER COLUMN user_id SET NOT NULL;
ALTER TABLE tags             ALTER COLUMN user_id SET NOT NULL;
ALTER TABLE challenges       ALTER COLUMN user_id SET NOT NULL;
ALTER TABLE reading_sessions ALTER COLUMN user_id SET NOT NULL;

-- tags.name was globally unique. With an owner it must be unique per owner
-- instead, or a second account could never reuse a tag name the first had taken.
ALTER TABLE tags DROP CONSTRAINT tags_name_key;
ALTER TABLE tags ADD CONSTRAINT tags_user_id_name_key UNIQUE (user_id, name);

-- Composite indexes leading with user_id. With an owner filter on every query a
-- trailing user_id is close to useless, so these supersede the single-column
-- indexes from the baseline rather than sitting alongside them.
DROP INDEX idx_books_status;
DROP INDEX idx_books_end_date;
DROP INDEX idx_challenges_deadline;
DROP INDEX idx_reading_sessions_date;

CREATE INDEX idx_books_user_status ON books(user_id, status);
CREATE INDEX idx_books_user_end_date ON books(user_id, end_date);
CREATE INDEX idx_tags_user ON tags(user_id);
CREATE INDEX idx_challenges_user_deadline ON challenges(user_id, deadline);
CREATE INDEX idx_reading_sessions_user_date ON reading_sessions(user_id, session_date);

-- idx_books_genre stays: genre filtering is not owner-scoped in the current
-- queries, and narrowing it is a Phase 2 question once the real access
-- patterns exist rather than a guess made here.

-- NOTE: reading_sessions' UNIQUE (book_id, session_date, source) is deliberately
-- NOT widened to include user_id. book_id already implies the owner, so adding
-- it would weaken the key — the same book could then hold two sessions for one
-- date. That uniqueness is what makes recordSession()'s
-- ON CONFLICT ... LEAST/GREATEST merge idempotent and order-independent, which
-- is the property that lets two clients push the same session in any order and
-- converge. Do not "fix" this.

-- Down Migration

DROP INDEX idx_reading_sessions_user_date;
DROP INDEX idx_challenges_user_deadline;
DROP INDEX idx_tags_user;
DROP INDEX idx_books_user_end_date;
DROP INDEX idx_books_user_status;

CREATE INDEX idx_books_status ON books(status);
CREATE INDEX idx_books_end_date ON books(end_date);
CREATE INDEX idx_challenges_deadline ON challenges(deadline);
CREATE INDEX idx_reading_sessions_date ON reading_sessions(session_date);

ALTER TABLE tags DROP CONSTRAINT tags_user_id_name_key;
ALTER TABLE tags ADD CONSTRAINT tags_name_key UNIQUE (name);

ALTER TABLE reading_sessions DROP COLUMN user_id;
ALTER TABLE challenges       DROP COLUMN user_id;
ALTER TABLE tags             DROP COLUMN user_id;
ALTER TABLE books            DROP COLUMN user_id;
