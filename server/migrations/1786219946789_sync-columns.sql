-- Columns the sync protocol needs.
--
-- Design: docs/superpowers/specs/2026-08-08-sync-protocol-design.md
--
-- Three additions per synced table, each for a specific reason:
--
--   uuid        Server SERIAL ids cannot identify a row created offline — two
--               devices would both mint id 96 for different books. The integer
--               id stays as the local primary key; the UUID is what crosses
--               machines.
--
--   updated_at  The pull filter. Maintained by a trigger rather than by each
--               query, because a write that forgets to touch it does not fail —
--               the row simply never syncs again, silently, which is the worst
--               kind of bug to find later.
--
--   deleted_at  A hard DELETE cannot propagate: a device that never saw the row
--               cannot tell "deleted" from "never existed", so the next pull
--               resurrects it. Tombstones also make the desktop's undoDelete()
--               durable — today it restores from an in-memory snapshot that
--               dies with the process.
--
-- book_tags is deliberately absent. It syncs as the `tags` array on a book
-- rather than as an entity of its own, so it needs no identity or timestamps.

-- Up Migration

-- gen_random_uuid() is built into PostgreSQL 13+, so no extension is needed.

ALTER TABLE books            ADD COLUMN uuid UUID NOT NULL DEFAULT gen_random_uuid();
ALTER TABLE tags             ADD COLUMN uuid UUID NOT NULL DEFAULT gen_random_uuid();
ALTER TABLE challenges       ADD COLUMN uuid UUID NOT NULL DEFAULT gen_random_uuid();
ALTER TABLE favorite_quotes  ADD COLUMN uuid UUID NOT NULL DEFAULT gen_random_uuid();
ALTER TABLE highlights       ADD COLUMN uuid UUID NOT NULL DEFAULT gen_random_uuid();
ALTER TABLE reading_sessions ADD COLUMN uuid UUID NOT NULL DEFAULT gen_random_uuid();

ALTER TABLE books            ADD CONSTRAINT books_uuid_key            UNIQUE (uuid);
ALTER TABLE tags             ADD CONSTRAINT tags_uuid_key             UNIQUE (uuid);
ALTER TABLE challenges       ADD CONSTRAINT challenges_uuid_key       UNIQUE (uuid);
ALTER TABLE favorite_quotes  ADD CONSTRAINT favorite_quotes_uuid_key  UNIQUE (uuid);
ALTER TABLE highlights       ADD CONSTRAINT highlights_uuid_key       UNIQUE (uuid);
ALTER TABLE reading_sessions ADD CONSTRAINT reading_sessions_uuid_key UNIQUE (uuid);

-- books already has updated_at from the baseline.
ALTER TABLE tags             ADD COLUMN updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW();
ALTER TABLE challenges       ADD COLUMN updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW();
ALTER TABLE favorite_quotes  ADD COLUMN updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW();
ALTER TABLE highlights       ADD COLUMN updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW();
ALTER TABLE reading_sessions ADD COLUMN updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW();

-- books.updated_at was nullable with a default; sync filters on it, and a NULL
-- would make the row invisible to every pull.
UPDATE books SET updated_at = COALESCE(updated_at, created_at, NOW()) WHERE updated_at IS NULL;
ALTER TABLE books ALTER COLUMN updated_at SET NOT NULL;

ALTER TABLE books            ADD COLUMN deleted_at TIMESTAMP WITH TIME ZONE;
ALTER TABLE tags             ADD COLUMN deleted_at TIMESTAMP WITH TIME ZONE;
ALTER TABLE challenges       ADD COLUMN deleted_at TIMESTAMP WITH TIME ZONE;
ALTER TABLE favorite_quotes  ADD COLUMN deleted_at TIMESTAMP WITH TIME ZONE;
ALTER TABLE highlights       ADD COLUMN deleted_at TIMESTAMP WITH TIME ZONE;
ALTER TABLE reading_sessions ADD COLUMN deleted_at TIMESTAMP WITH TIME ZONE;

-- Maintaining updated_at in a trigger, not in each UPDATE. A missed assignment
-- in a query is invisible: nothing errors, the row just stops syncing.
CREATE OR REPLACE FUNCTION touch_updated_at() RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER books_touch_updated_at            BEFORE UPDATE ON books            FOR EACH ROW EXECUTE FUNCTION touch_updated_at();
CREATE TRIGGER tags_touch_updated_at             BEFORE UPDATE ON tags             FOR EACH ROW EXECUTE FUNCTION touch_updated_at();
CREATE TRIGGER challenges_touch_updated_at       BEFORE UPDATE ON challenges       FOR EACH ROW EXECUTE FUNCTION touch_updated_at();
CREATE TRIGGER favorite_quotes_touch_updated_at  BEFORE UPDATE ON favorite_quotes  FOR EACH ROW EXECUTE FUNCTION touch_updated_at();
CREATE TRIGGER highlights_touch_updated_at       BEFORE UPDATE ON highlights       FOR EACH ROW EXECUTE FUNCTION touch_updated_at();
CREATE TRIGGER reading_sessions_touch_updated_at BEFORE UPDATE ON reading_sessions FOR EACH ROW EXECUTE FUNCTION touch_updated_at();

-- The pull query is "everything of mine changed since T", so the index has to
-- lead with the owner and then the timestamp.
CREATE INDEX idx_books_sync            ON books(user_id, updated_at);
CREATE INDEX idx_tags_sync             ON tags(user_id, updated_at);
CREATE INDEX idx_challenges_sync       ON challenges(user_id, updated_at);
CREATE INDEX idx_reading_sessions_sync ON reading_sessions(user_id, updated_at);
-- Quotes and highlights hang off a book and have no user_id of their own, so
-- their pull joins through books; the timestamp alone is the useful key.
CREATE INDEX idx_favorite_quotes_sync  ON favorite_quotes(updated_at);
CREATE INDEX idx_highlights_sync       ON highlights(updated_at);

-- Down Migration

DROP INDEX idx_highlights_sync;
DROP INDEX idx_favorite_quotes_sync;
DROP INDEX idx_reading_sessions_sync;
DROP INDEX idx_challenges_sync;
DROP INDEX idx_tags_sync;
DROP INDEX idx_books_sync;

DROP TRIGGER reading_sessions_touch_updated_at ON reading_sessions;
DROP TRIGGER highlights_touch_updated_at ON highlights;
DROP TRIGGER favorite_quotes_touch_updated_at ON favorite_quotes;
DROP TRIGGER challenges_touch_updated_at ON challenges;
DROP TRIGGER tags_touch_updated_at ON tags;
DROP TRIGGER books_touch_updated_at ON books;
DROP FUNCTION touch_updated_at();

ALTER TABLE reading_sessions DROP COLUMN deleted_at;
ALTER TABLE highlights       DROP COLUMN deleted_at;
ALTER TABLE favorite_quotes  DROP COLUMN deleted_at;
ALTER TABLE challenges       DROP COLUMN deleted_at;
ALTER TABLE tags             DROP COLUMN deleted_at;
ALTER TABLE books            DROP COLUMN deleted_at;

ALTER TABLE books ALTER COLUMN updated_at DROP NOT NULL;

ALTER TABLE reading_sessions DROP COLUMN updated_at;
ALTER TABLE highlights       DROP COLUMN updated_at;
ALTER TABLE favorite_quotes  DROP COLUMN updated_at;
ALTER TABLE challenges       DROP COLUMN updated_at;
ALTER TABLE tags             DROP COLUMN updated_at;

ALTER TABLE reading_sessions DROP COLUMN uuid;
ALTER TABLE highlights       DROP COLUMN uuid;
ALTER TABLE favorite_quotes  DROP COLUMN uuid;
ALTER TABLE challenges       DROP COLUMN uuid;
ALTER TABLE tags             DROP COLUMN uuid;
ALTER TABLE books            DROP COLUMN uuid;
