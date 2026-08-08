-- Deterministic fingerprint of a BookWorm library.
--
-- Run it against the live database before Phase 4 and again after the desktop
-- app has been moved onto the API. Identical output means nothing was lost in
-- the move. Read-only: it writes nothing and locks nothing.
--
--   psql -qtA -d wormbook -f server/scripts/library-fingerprint.sql
--
-- The md5 rolls up the fields a user would actually notice going wrong — title,
-- author, status, rating, progress — so a single silently corrupted row changes
-- the hash. Row counts alone would not catch a book whose rating was reset.
--
-- Ordered by id explicitly: string_agg has no defined order without it, and an
-- unordered aggregate would produce a different hash on every run.

SELECT 'books=' || count(*) FROM books
UNION ALL SELECT 'tags=' || count(*) FROM tags
UNION ALL SELECT 'book_tags=' || count(*) FROM book_tags
UNION ALL SELECT 'favorite_quotes=' || count(*) FROM favorite_quotes
UNION ALL SELECT 'highlights=' || count(*) FROM highlights
UNION ALL SELECT 'challenges=' || count(*) FROM challenges
UNION ALL SELECT 'reading_sessions=' || count(*) FROM reading_sessions
-- Ordered explicitly. GROUP BY imposes no order, so these rows came back in
-- whatever sequence the plan produced — which changes after anything that
-- rewrites the table, such as ADD COLUMN with a volatile default. A comparison
-- tool that is not deterministic reports differences that are not there, and
-- teaches you to ignore the ones that are.
UNION ALL SELECT * FROM (
    SELECT 'status_' || status || '=' || count(*) FROM books GROUP BY status ORDER BY status
) AS status_counts
UNION ALL SELECT 'total_pages_read=' || coalesce(sum(page_end - page_start), 0) FROM reading_sessions
UNION ALL SELECT 'sum_read_count=' || coalesce(sum(read_count), 0) FROM books
UNION ALL SELECT 'books_fingerprint=' || md5(string_agg(
         id || '|' || title || '|' || author || '|' || status || '|' ||
         coalesce(rating::text, '') || '|' || coalesce(current_page::text, ''),
         E'\n' ORDER BY id))
     FROM books;
