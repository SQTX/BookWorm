-- Baseline schema.
--
-- Reproduces exactly what DatabaseManager::initializeSchema() produces on the
-- desktop app as of v1.1.0 — not a redesign. Verified by building a scratch
-- database from this file and diffing pg_dump --schema-only against a dump of
-- the live wormbook database; the only permitted difference is node-pg-migrate's
-- own pgmigrations bookkeeping table.
--
-- Written as CREATE TABLE with inline constraints rather than as a replay of the
-- app's CREATE-then-ALTER history, because PostgreSQL derives constraint,
-- sequence and index names from the DDL form. SERIAL yields <table>_id_seq and
-- <table>_pkey, an inline CHECK yields <table>_<column>_check, an inline UNIQUE
-- yields <table>_<columns>_key, and an inline REFERENCES yields
-- <table>_<column>_fkey — matching the live database name for name.
--
-- Column order also matters: it is part of what the diff compares, so the
-- ALTER-added columns (item_type onward) stay last, in the order the app added
-- them.
--
-- This migration is additive only and touches no data. The multi-tenancy work
-- (users, catalogue/instance split, row-level security) comes in the next one.

-- Up Migration

CREATE TABLE books (
    id                SERIAL PRIMARY KEY,
    title             VARCHAR(512) NOT NULL,
    author            VARCHAR(512) NOT NULL,
    genre             VARCHAR(128),
    page_count        INTEGER DEFAULT 0,
    start_date        DATE,
    end_date          DATE,
    -- 1-6, not 1-10: the app narrowed this constraint after launch.
    rating            SMALLINT CHECK (rating >= 1 AND rating <= 6),
    status            VARCHAR(16) NOT NULL DEFAULT 'planned'
                        CHECK (status IN ('reading', 'read', 'planned', 'abandoned')),
    notes             TEXT,
    isbn              VARCHAR(20),
    publisher         VARCHAR(256),
    publication_year  SMALLINT,
    language          VARCHAR(64) DEFAULT 'English',
    cover_image_path  VARCHAR(1024),
    created_at        TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at        TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    -- Added by later app migrations, in the order they were added.
    item_type         VARCHAR(32) DEFAULT 'book',
    is_non_fiction    BOOLEAN DEFAULT FALSE,
    current_page      INTEGER DEFAULT 0,
    series            VARCHAR(256),
    publication_date  DATE,
    summary           TEXT,
    review            TEXT,
    audio_mode        VARCHAR(32) DEFAULT 'none',
    is_priority       BOOLEAN DEFAULT FALSE,
    read_count        INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE tags (
    id    SERIAL PRIMARY KEY,
    name  VARCHAR(128) NOT NULL UNIQUE,
    color VARCHAR(9) DEFAULT '#808080'
);

CREATE TABLE book_tags (
    book_id  INTEGER NOT NULL REFERENCES books(id) ON DELETE CASCADE,
    tag_id   INTEGER NOT NULL REFERENCES tags(id) ON DELETE CASCADE,
    PRIMARY KEY (book_id, tag_id)
);

CREATE TABLE favorite_quotes (
    id       SERIAL PRIMARY KEY,
    book_id  INTEGER NOT NULL REFERENCES books(id) ON DELETE CASCADE,
    quote    TEXT NOT NULL,
    page     INTEGER
);

CREATE TABLE highlights (
    id          SERIAL PRIMARY KEY,
    book_id     INTEGER NOT NULL REFERENCES books(id) ON DELETE CASCADE,
    title       VARCHAR(256) NOT NULL,
    page        INTEGER,
    note        TEXT,
    created_at  TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE TABLE challenges (
    id            SERIAL PRIMARY KEY,
    name          VARCHAR(256) NOT NULL,
    -- Legacy: superseded by target_value, kept because the live database still
    -- has it and this migration must match the live database.
    target_books  INTEGER NOT NULL DEFAULT 1,
    deadline      DATE NOT NULL,
    created_at    TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    -- 'books' | 'pages' | 'pages_per_day'. Deliberately unconstrained here: the
    -- live database has no CHECK on it, and adding one now would make this file
    -- diverge from what it is supposed to reproduce.
    metric        VARCHAR(24) NOT NULL DEFAULT 'books',
    target_value  INTEGER NOT NULL DEFAULT 1,
    period_unit   VARCHAR(12) DEFAULT 'custom',
    period_count  INTEGER DEFAULT 0
);

CREATE TABLE reading_sessions (
    id            SERIAL PRIMARY KEY,
    book_id       INTEGER NOT NULL REFERENCES books(id) ON DELETE CASCADE,
    session_date  DATE NOT NULL,
    page_start    INTEGER NOT NULL,
    page_end      INTEGER NOT NULL,
    source        VARCHAR(16) NOT NULL DEFAULT 'manual',
    created_at    TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    -- The key the app's daily-merge depends on: recordSession() upserts with
    -- ON CONFLICT ... DO UPDATE SET page_start = LEAST(...), page_end =
    -- GREATEST(...), which makes a session write idempotent and independent of
    -- arrival order. That property is what will let two clients sync without a
    -- conflict resolver, so this constraint must not be relaxed.
    UNIQUE (book_id, session_date, source)
);

CREATE INDEX idx_books_status ON books(status);
CREATE INDEX idx_books_genre ON books(genre);
CREATE INDEX idx_books_end_date ON books(end_date);
CREATE INDEX idx_book_tags_book_id ON book_tags(book_id);
CREATE INDEX idx_favorite_quotes_book_id ON favorite_quotes(book_id);
CREATE INDEX idx_challenges_deadline ON challenges(deadline);
CREATE INDEX idx_highlights_book_id ON highlights(book_id);
CREATE INDEX idx_reading_sessions_book_id ON reading_sessions(book_id);
CREATE INDEX idx_reading_sessions_date ON reading_sessions(session_date);

-- Down Migration

-- Dropped in dependency order. CASCADE is deliberately not used: if something
-- outside this migration ends up depending on these tables, the drop should
-- fail loudly rather than quietly take that dependency with it.
DROP TABLE IF EXISTS reading_sessions;
DROP TABLE IF EXISTS highlights;
DROP TABLE IF EXISTS favorite_quotes;
DROP TABLE IF EXISTS book_tags;
DROP TABLE IF EXISTS challenges;
DROP TABLE IF EXISTS tags;
DROP TABLE IF EXISTS books;
