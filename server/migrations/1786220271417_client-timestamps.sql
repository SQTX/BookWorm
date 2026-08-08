-- Separate the sync cursor from the edit timestamp.
--
-- The previous migration used one column for both, and the two have
-- incompatible requirements:
--
--   updated_at         must be SERVER time. It is the pull cursor, so it has to
--                      be monotonic on the server — a client with a skewed
--                      clock would otherwise write rows that sort before a
--                      cursor already issued, and they would never be pulled.
--
--   client_updated_at  must be CLIENT time. It decides last-write-wins, which
--                      is a question about when the user made the edit, not
--                      about when the request happened to arrive.
--
-- Conflated, the BEFORE UPDATE trigger stamped server time over the very value
-- the LWW guard compares against. The effect: after a row had been updated
-- once, the next genuine client edit was rejected, because its timestamp was
-- older than the server clock. Silently — the push returned 200 and the change
-- was simply dropped.
--
-- The original tests missed it by using a timestamp a minute in the future,
-- which cleared the server clock by luck. A realistic edit a few milliseconds
-- later did not.

-- Up Migration

ALTER TABLE books            ADD COLUMN client_updated_at TIMESTAMP WITH TIME ZONE;
ALTER TABLE tags             ADD COLUMN client_updated_at TIMESTAMP WITH TIME ZONE;
ALTER TABLE challenges       ADD COLUMN client_updated_at TIMESTAMP WITH TIME ZONE;
ALTER TABLE favorite_quotes  ADD COLUMN client_updated_at TIMESTAMP WITH TIME ZONE;
ALTER TABLE highlights       ADD COLUMN client_updated_at TIMESTAMP WITH TIME ZONE;
ALTER TABLE reading_sessions ADD COLUMN client_updated_at TIMESTAMP WITH TIME ZONE;

-- Existing rows have never been edited by a client, so the server's own
-- timestamp is the honest starting value.
UPDATE books            SET client_updated_at = updated_at WHERE client_updated_at IS NULL;
UPDATE tags             SET client_updated_at = updated_at WHERE client_updated_at IS NULL;
UPDATE challenges       SET client_updated_at = updated_at WHERE client_updated_at IS NULL;
UPDATE favorite_quotes  SET client_updated_at = updated_at WHERE client_updated_at IS NULL;
UPDATE highlights       SET client_updated_at = updated_at WHERE client_updated_at IS NULL;
UPDATE reading_sessions SET client_updated_at = updated_at WHERE client_updated_at IS NULL;

ALTER TABLE books            ALTER COLUMN client_updated_at SET NOT NULL, ALTER COLUMN client_updated_at SET DEFAULT NOW();
ALTER TABLE tags             ALTER COLUMN client_updated_at SET NOT NULL, ALTER COLUMN client_updated_at SET DEFAULT NOW();
ALTER TABLE challenges       ALTER COLUMN client_updated_at SET NOT NULL, ALTER COLUMN client_updated_at SET DEFAULT NOW();
ALTER TABLE favorite_quotes  ALTER COLUMN client_updated_at SET NOT NULL, ALTER COLUMN client_updated_at SET DEFAULT NOW();
ALTER TABLE highlights       ALTER COLUMN client_updated_at SET NOT NULL, ALTER COLUMN client_updated_at SET DEFAULT NOW();
ALTER TABLE reading_sessions ALTER COLUMN client_updated_at SET NOT NULL, ALTER COLUMN client_updated_at SET DEFAULT NOW();

-- Down Migration

ALTER TABLE reading_sessions DROP COLUMN client_updated_at;
ALTER TABLE highlights       DROP COLUMN client_updated_at;
ALTER TABLE favorite_quotes  DROP COLUMN client_updated_at;
ALTER TABLE challenges       DROP COLUMN client_updated_at;
ALTER TABLE tags             DROP COLUMN client_updated_at;
ALTER TABLE books            DROP COLUMN client_updated_at;
