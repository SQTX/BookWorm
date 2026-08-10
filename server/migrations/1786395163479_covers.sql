-- Cover images, stored by content hash.
--
-- The identity of a cover is its bytes, not its filename or its owner. Two
-- accounts adding the same edition upload the same file and share one stored
-- copy; the same user re-uploading an unchanged image is a no-op. That is why
-- the hash is the primary key.
--
-- Covers are ~98% of this application's storage volume (measured: 102 files,
-- 7.9 MB, against 152 kB of book rows), so deduplication and re-encoding are
-- where the disk budget is won or lost.
--
-- books.cover_hash is what syncs. books.cover_image_path stays, and stays
-- local: it points at wherever the user picked the file on that machine, which
-- is meaningless on any other. Keeping both means the desktop can go on showing
-- its local file while the synced identity travels separately.

-- Up Migration

CREATE TABLE covers (
    -- SHA-256 of the ORIGINAL uploaded bytes, hex. Hashing the original rather
    -- than the re-encoded output means re-uploading the same file is detected
    -- before any CPU is spent on it.
    hash          CHAR(64) PRIMARY KEY,
    byte_size     INTEGER NOT NULL,
    width         INTEGER NOT NULL,
    height        INTEGER NOT NULL,
    -- Not an owner column: a cover belongs to its content. Ownership is
    -- expressed by which books reference it, which is also what makes sharing
    -- between accounts free rather than a leak.
    created_at    TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

ALTER TABLE books ADD COLUMN cover_hash CHAR(64) REFERENCES covers(hash);

-- Finding which books use a cover is how the sweep decides whether a file is
-- still needed.
CREATE INDEX idx_books_cover_hash ON books(cover_hash) WHERE cover_hash IS NOT NULL;

-- Down Migration

DROP INDEX idx_books_cover_hash;
ALTER TABLE books DROP COLUMN cover_hash;
DROP TABLE covers;
