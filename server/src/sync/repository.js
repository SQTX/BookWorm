/**
 * Sync storage.
 *
 * Design: docs/superpowers/specs/2026-08-08-sync-protocol-design.md
 *
 * Two operations. Pull returns everything of the caller's that changed after a
 * timestamp, tombstones included. Push upserts a batch by UUID, resolving
 * conflicts by the rules the spec sets out — which differ per table because the
 * data has different shapes.
 */

/**
 * Tables that cross machines. `book_tags` is absent on purpose: it travels as
 * the `tags` array on a book rather than as an entity with its own identity.
 */
export const SYNCED_TABLES = ['books', 'tags', 'challenges', 'favoriteQuotes', 'highlights', 'readingSessions'];

const PULL_QUERIES = {
  books: `
    SELECT uuid, title, author, genre, page_count AS "pageCount",
           start_date AS "startDate", end_date AS "endDate", rating, status, notes,
           isbn, publisher, publication_year AS "publicationYear",
           publication_date AS "publicationDate", language,
           cover_image_path AS "coverImagePath", item_type AS "itemType",
           is_non_fiction AS "isNonFiction", is_priority AS "isPriority",
           audio_mode AS "audioMode", current_page AS "currentPage", series,
           summary, review, read_count AS "readCount",
           client_updated_at AS "updatedAt", deleted_at AS "deletedAt",
           COALESCE(
             (SELECT array_agg(t.name ORDER BY t.name)
                FROM book_tags bt JOIN tags t ON t.id = bt.tag_id
               WHERE bt.book_id = books.id AND t.deleted_at IS NULL),
             ARRAY[]::varchar[]
           ) AS tags
      FROM books
     WHERE user_id = $1 AND updated_at > $2
     ORDER BY updated_at`,

  tags: `
    SELECT uuid, name, color, client_updated_at AS "updatedAt", deleted_at AS "deletedAt"
      FROM tags WHERE user_id = $1 AND updated_at > $2 ORDER BY updated_at`,

  challenges: `
    SELECT uuid, name, target_books AS "targetBooks", deadline, metric,
           target_value AS "targetValue", period_unit AS "periodUnit",
           period_count AS "periodCount",
           client_updated_at AS "updatedAt", deleted_at AS "deletedAt"
      FROM challenges WHERE user_id = $1 AND updated_at > $2 ORDER BY updated_at`,

  // Quotes and highlights have no user_id of their own — they hang off a book
  // and inherit its owner, so the scope comes from the join.
  favoriteQuotes: `
    SELECT q.uuid, b.uuid AS "bookUuid", q.quote, q.page,
           q.client_updated_at AS "updatedAt", q.deleted_at AS "deletedAt"
      FROM favorite_quotes q JOIN books b ON b.id = q.book_id
     WHERE b.user_id = $1 AND q.updated_at > $2 ORDER BY q.updated_at`,

  highlights: `
    SELECT h.uuid, b.uuid AS "bookUuid", h.title, h.page, h.note,
           h.client_updated_at AS "updatedAt", h.deleted_at AS "deletedAt"
      FROM highlights h JOIN books b ON b.id = h.book_id
     WHERE b.user_id = $1 AND h.updated_at > $2 ORDER BY h.updated_at`,

  readingSessions: `
    SELECT s.uuid, b.uuid AS "bookUuid", s.session_date AS "sessionDate",
           s.page_start AS "pageStart", s.page_end AS "pageEnd", s.source,
           s.client_updated_at AS "updatedAt", s.deleted_at AS "deletedAt"
      FROM reading_sessions s JOIN books b ON b.id = s.book_id
     WHERE s.user_id = $1 AND s.updated_at > $2 ORDER BY s.updated_at`,
};

/**
 * Everything of this owner's that changed after `since`, tombstones included.
 *
 * The epoch is the default so a first sync pulls the whole library through the
 * same path as an incremental one — one code path, exercised constantly,
 * instead of a bootstrap path used once and therefore never debugged.
 *
 * @param {import('pg').Pool} pool
 * @param {number} userId
 * @param {string} since ISO timestamp
 */
export async function pullChanges(pool, userId, since = '1970-01-01T00:00:00Z') {
  const changes = {};

  for (const [table, query] of Object.entries(PULL_QUERIES)) {
    const { rows } = await pool.query(query, [userId, since]);
    changes[table] = rows;
  }

  return changes;
}

/**
 * The server's clock, which is what the client must use as its next `since`.
 *
 * Never the client's own: a clock a few seconds fast would skip every row
 * written in the gap, permanently and silently, because those rows are already
 * older than the next cursor.
 */
export async function serverTime(pool) {
  const { rows } = await pool.query('SELECT NOW() AS now');
  return rows[0].now;
}

/**
 * @param {import('pg').PoolClient} client
 * @param {number} userId
 * @param {string} bookUuid
 * @returns {Promise<number | null>}
 */
async function bookIdOf(client, userId, bookUuid) {
  const { rows } = await client.query('SELECT id FROM books WHERE uuid = $1 AND user_id = $2', [
    bookUuid,
    userId,
  ]);
  return rows[0]?.id ?? null;
}

/** Rows the client may set on a book. Everything else is server-owned. */
const BOOK_COLUMNS = [
  ['title', 'title'],
  ['author', 'author'],
  ['genre', 'genre'],
  ['pageCount', 'page_count'],
  ['startDate', 'start_date'],
  ['endDate', 'end_date'],
  ['rating', 'rating'],
  ['status', 'status'],
  ['notes', 'notes'],
  ['isbn', 'isbn'],
  ['publisher', 'publisher'],
  ['publicationYear', 'publication_year'],
  ['publicationDate', 'publication_date'],
  ['language', 'language'],
  ['coverImagePath', 'cover_image_path'],
  ['itemType', 'item_type'],
  ['isNonFiction', 'is_non_fiction'],
  ['isPriority', 'is_priority'],
  ['audioMode', 'audio_mode'],
  ['currentPage', 'current_page'],
  ['series', 'series'],
  ['summary', 'summary'],
  ['review', 'review'],
  ['readCount', 'read_count'],
];

function normaliseBook(row) {
  const out = { ...row };
  if (out.rating === 0) out.rating = null;
  for (const key of ['startDate', 'endDate', 'publicationDate']) {
    if (out[key] === '') out[key] = null;
  }
  return out;
}

/**
 * Last-write-wins, decided on client_updated_at — never on updated_at.
 *
 * updated_at is the pull cursor and is stamped by a trigger with server time,
 * so comparing against it rejects any client edit older than the last server
 * write. That is every realistic edit: a user types, the client stamps the
 * moment, and by the time it arrives the stored server timestamp is already
 * newer. The push returns 200 and the change vanishes.
 *
 * client_updated_at is the user's edit time and nothing overwrites it, so the
 * comparison asks the question it means to ask.
 *
 * `>` not `>=`, so ties break toward the server and the outcome cannot depend
 * on the order requests happen to arrive in.
 *
 * @param {string} table interpolated, never a user value — a bound parameter
 *   cannot stand in for an identifier in PostgreSQL.
 */
const lwwGuard = (table) => `WHERE EXCLUDED.client_updated_at > ${table}.client_updated_at`;

async function pushBooks(client, userId, rows) {
  for (const raw of rows) {
    const row = normaliseBook(raw);
    const columns = ['user_id', 'uuid', 'client_updated_at', 'deleted_at'];
    const values = [userId, row.uuid, row.updatedAt, row.deletedAt ?? null];

    for (const [key, column] of BOOK_COLUMNS) {
      if (row[key] !== undefined) {
        columns.push(column);
        values.push(row[key]);
      }
    }

    const placeholders = values.map((_, i) => `$${i + 1}`);
    const updates = columns
      .filter((c) => c !== 'user_id' && c !== 'uuid')
      .map((c) => `${c} = EXCLUDED.${c}`)
      .join(', ');

    await client.query(
      `INSERT INTO books (${columns.join(', ')}) VALUES (${placeholders.join(', ')})
       ON CONFLICT (uuid) DO UPDATE SET ${updates}
       ${lwwGuard('books')}`,
      values,
    );

    if (Array.isArray(row.tags)) {
      const id = await bookIdOf(client, userId, row.uuid);
      if (id !== null) await replaceTags(client, userId, id, row.tags);
    }
  }
}

async function replaceTags(client, userId, bookId, tags) {
  const names = [...new Set(tags.map((t) => String(t).trim()).filter(Boolean))];
  await client.query('DELETE FROM book_tags WHERE book_id = $1', [bookId]);
  if (names.length === 0) return;

  await client.query(
    `INSERT INTO tags (user_id, name) SELECT $1, unnest($2::varchar[])
     ON CONFLICT (user_id, name) DO NOTHING`,
    [userId, names],
  );
  await client.query(
    `INSERT INTO book_tags (book_id, tag_id)
     SELECT $1, t.id FROM tags t WHERE t.user_id = $2 AND t.name = ANY($3::varchar[])
     ON CONFLICT DO NOTHING`,
    [bookId, userId, names],
  );
}

async function pushTags(client, userId, rows) {
  for (const row of rows) {
    await client.query(
      `INSERT INTO tags (user_id, uuid, name, color, client_updated_at, deleted_at)
       VALUES ($1, $2, $3, $4, $5, $6)
       ON CONFLICT (uuid) DO UPDATE
          SET name = EXCLUDED.name, color = EXCLUDED.color,
              client_updated_at = EXCLUDED.client_updated_at, deleted_at = EXCLUDED.deleted_at
        ${lwwGuard('tags')}`,
      [userId, row.uuid, row.name, row.color ?? null, row.updatedAt, row.deletedAt ?? null],
    );
  }
}

async function pushChallenges(client, userId, rows) {
  for (const row of rows) {
    await client.query(
      `INSERT INTO challenges (user_id, uuid, name, target_books, deadline, metric,
                               target_value, period_unit, period_count, client_updated_at, deleted_at)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)
       ON CONFLICT (uuid) DO UPDATE
          SET name = EXCLUDED.name, target_books = EXCLUDED.target_books,
              deadline = EXCLUDED.deadline, metric = EXCLUDED.metric,
              target_value = EXCLUDED.target_value, period_unit = EXCLUDED.period_unit,
              period_count = EXCLUDED.period_count,
              client_updated_at = EXCLUDED.client_updated_at, deleted_at = EXCLUDED.deleted_at
        ${lwwGuard('challenges')}`,
      [
        userId, row.uuid, row.name, row.targetBooks ?? 1, row.deadline, row.metric ?? 'books',
        row.targetValue ?? 1, row.periodUnit ?? 'custom', row.periodCount ?? 0,
        row.updatedAt, row.deletedAt ?? null,
      ],
    );
  }
}

async function pushQuotes(client, userId, rows) {
  for (const row of rows) {
    const bookId = await bookIdOf(client, userId, row.bookUuid);
    // A quote whose book has not arrived yet is skipped, not an error: the next
    // sync carries it once the book exists. Failing the batch would deadlock
    // two rows that simply arrived out of order.
    if (bookId === null) continue;

    await client.query(
      `INSERT INTO favorite_quotes (uuid, book_id, quote, page, client_updated_at, deleted_at)
       VALUES ($1, $2, $3, $4, $5, $6)
       ON CONFLICT (uuid) DO UPDATE
          SET quote = EXCLUDED.quote, page = EXCLUDED.page,
              client_updated_at = EXCLUDED.client_updated_at, deleted_at = EXCLUDED.deleted_at
        ${lwwGuard('favorite_quotes')}`,
      [row.uuid, bookId, row.quote, row.page ?? null, row.updatedAt, row.deletedAt ?? null],
    );
  }
}

async function pushHighlights(client, userId, rows) {
  for (const row of rows) {
    const bookId = await bookIdOf(client, userId, row.bookUuid);
    if (bookId === null) continue;

    await client.query(
      `INSERT INTO highlights (uuid, book_id, title, page, note, client_updated_at, deleted_at)
       VALUES ($1, $2, $3, $4, $5, $6, $7)
       ON CONFLICT (uuid) DO UPDATE
          SET title = EXCLUDED.title, page = EXCLUDED.page, note = EXCLUDED.note,
              client_updated_at = EXCLUDED.client_updated_at, deleted_at = EXCLUDED.deleted_at
        ${lwwGuard('highlights')}`,
      [row.uuid, bookId, row.title, row.page ?? null, row.note ?? null, row.updatedAt, row.deletedAt ?? null],
    );
  }
}

/**
 * Sessions are the exception: they do NOT use last-write-wins.
 *
 * The daily merge is idempotent and order-independent by construction — LEAST
 * and GREATEST widen the range rather than replacing it — so two devices
 * pushing the same reading day converge whatever order they arrive in, and
 * pages read can never be lost. Applying LWW here would throw that away and
 * make the outcome depend on a timestamp race.
 *
 * The conflict target is (book_id, session_date, source), not uuid: two devices
 * independently recording the same reading day generate different UUIDs for
 * what is the same session.
 */
async function pushSessions(client, userId, rows) {
  for (const row of rows) {
    const bookId = await bookIdOf(client, userId, row.bookUuid);
    if (bookId === null) continue;

    if (row.deletedAt) {
      await client.query(
        'UPDATE reading_sessions SET deleted_at = $1 WHERE uuid = $2 AND user_id = $3',
        [row.deletedAt, row.uuid, userId],
      );
      continue;
    }

    await client.query(
      `INSERT INTO reading_sessions (user_id, uuid, book_id, session_date, page_start, page_end, source, client_updated_at)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
       ON CONFLICT (book_id, session_date, source) DO UPDATE
          SET page_start = LEAST(reading_sessions.page_start, EXCLUDED.page_start),
              page_end   = GREATEST(reading_sessions.page_end, EXCLUDED.page_end)`,
      [userId, row.uuid, bookId, row.sessionDate, row.pageStart, row.pageEnd, row.source ?? 'manual', row.updatedAt],
    );
  }
}

const PUSH_HANDLERS = {
  // Books first: quotes, highlights and sessions all resolve a book UUID, so
  // within one batch the parent must land before its children.
  books: pushBooks,
  tags: pushTags,
  challenges: pushChallenges,
  favoriteQuotes: pushQuotes,
  highlights: pushHighlights,
  readingSessions: pushSessions,
};

/**
 * Apply a batch. One transaction: a partial push that half-applies would leave
 * the client unable to tell what it still owes.
 *
 * @param {import('pg').Pool} pool
 * @param {number} userId
 * @param {Record<string, object[]>} batch
 */
export async function pushChanges(pool, userId, batch) {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    for (const [table, handler] of Object.entries(PUSH_HANDLERS)) {
      const rows = batch[table];
      if (Array.isArray(rows) && rows.length > 0) {
        await handler(client, userId, rows);
      }
    }

    await client.query('COMMIT');
  } catch (err) {
    await client.query('ROLLBACK');
    throw err;
  } finally {
    client.release();
  }
}
