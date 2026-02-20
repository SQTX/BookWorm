-- WormBook database schema
-- Run: createdb wormbook && psql wormbook < sql/init.sql

CREATE TABLE IF NOT EXISTS books (
    id               SERIAL PRIMARY KEY,
    title            VARCHAR(512) NOT NULL,
    author           VARCHAR(512) NOT NULL,
    genre            VARCHAR(128),
    page_count       INTEGER DEFAULT 0,
    start_date       DATE,
    end_date         DATE,
    rating           SMALLINT CHECK (rating >= 1 AND rating <= 10),
    status           VARCHAR(16) NOT NULL DEFAULT 'planned'
                         CHECK (status IN ('reading', 'read', 'planned')),
    notes            TEXT,
    isbn             VARCHAR(20),
    publisher        VARCHAR(256),
    publication_year SMALLINT,
    language         VARCHAR(64) DEFAULT 'English',
    cover_image_path VARCHAR(1024),
    created_at       TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at       TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS tags (
    id   SERIAL PRIMARY KEY,
    name VARCHAR(128) NOT NULL UNIQUE
);

CREATE TABLE IF NOT EXISTS book_tags (
    book_id INTEGER NOT NULL REFERENCES books(id) ON DELETE CASCADE,
    tag_id  INTEGER NOT NULL REFERENCES tags(id)  ON DELETE CASCADE,
    PRIMARY KEY (book_id, tag_id)
);

CREATE TABLE IF NOT EXISTS favorite_quotes (
    id      SERIAL PRIMARY KEY,
    book_id INTEGER NOT NULL REFERENCES books(id) ON DELETE CASCADE,
    quote   TEXT NOT NULL,
    page    INTEGER
);

CREATE INDEX IF NOT EXISTS idx_books_status ON books(status);
CREATE INDEX IF NOT EXISTS idx_books_genre ON books(genre);
CREATE INDEX IF NOT EXISTS idx_books_end_date ON books(end_date);
CREATE INDEX IF NOT EXISTS idx_book_tags_book_id ON book_tags(book_id);
CREATE INDEX IF NOT EXISTS idx_favorite_quotes_book_id ON favorite_quotes(book_id);
