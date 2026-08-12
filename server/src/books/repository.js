/**
 * Book storage.
 *
 * Every statement here is parameterised and every one filters on user_id. D4
 * chose hand-written SQL, which removes the ORM's built-in protection against
 * injection and against forgetting the owner filter — so both have to be
 * habits. A query without `user_id = $n` is a data leak waiting for a second
 * account.
 */
import { COLUMN_OF } from './schemas.js';

const SELECT_BOOK = `
  SELECT b.id, b.title, b.author, b.genre, b.page_count AS "pageCount",
         b.start_date AS "startDate", b.end_date AS "endDate", b.rating, b.status,
         b.notes, b.isbn, b.publisher, b.publication_year AS "publicationYear",
         b.publication_date AS "publicationDate", b.language,
         b.cover_image_path AS "coverImagePath", b.cover_hash AS "coverHash", b.item_type AS "itemType",
         b.is_non_fiction AS "isNonFiction", b.is_priority AS "isPriority",
         b.audio_mode AS "audioMode", b.current_page AS "currentPage", b.series,
         b.summary, b.review, b.read_count AS "readCount",
         b.updated_at AS "updatedAt",
         COALESCE(
           (SELECT array_agg(t.name ORDER BY t.name)
              FROM book_tags bt JOIN tags t ON t.id = bt.tag_id
             WHERE bt.book_id = b.id),
           ARRAY[]::varchar[]
         ) AS tags
    FROM books b
`;

/**
 * `0` is how the desktop expresses "unrated", but the column's CHECK only
 * admits 1-6 or NULL. Translate rather than reject: the alternative is every
 * client remembering to send null.
 *
 * @param {Record<string, unknown>} input
 */
function normalise(input) {
  const out = { ...input };
  if (out.rating === 0) out.rating = null;
  // The desktop sends '' for an unset date; DATE cannot take it.
  for (const key of ['startDate', 'endDate', 'publicationDate']) {
    if (out[key] === '') out[key] = null;
  }
  return out;
}

/**
 * @param {import('pg').Pool | import('pg').PoolClient} db
 * @param {number} userId
 */
export async function listBooks(db, userId, { status } = {}) {
  const params = [userId];
  // Tombstones are sync's business, not the API's: a soft-deleted book is gone
  // as far as every reader is concerned.
  let where = 'WHERE b.user_id = $1 AND b.deleted_at IS NULL';

  if (status) {
    params.push(status);
    where += ` AND b.status = $${params.length}`;
  }

  const { rows } = await db.query(
    `${SELECT_BOOK} ${where} ORDER BY b.updated_at DESC, b.id DESC`,
    params,
  );
  return rows;
}

export async function getBook(db, userId, id) {
  const { rows } = await db.query(`${SELECT_BOOK} WHERE b.user_id = $1 AND b.id = $2 AND b.deleted_at IS NULL`, [userId, id]);
  return rows[0] ?? null;
}

/**
 * Replace a book's tags, creating any that do not exist for this owner.
 *
 * @param {import('pg').PoolClient} client
 * @param {number} userId
 * @param {number} bookId
 * @param {string[]} tags
 */
async function setTags(client, userId, bookId, tags) {
  await client.query('DELETE FROM book_tags WHERE book_id = $1', [bookId]);
  if (tags.length === 0) return;

  const names = [...new Set(tags.map((t) => t.trim()).filter(Boolean))];
  if (names.length === 0) return;

  // ON CONFLICT DO NOTHING then select: two clients adding the same tag at once
  // must not make one of them fail.
  await client.query(
    `INSERT INTO tags (user_id, name)
     SELECT $1, unnest($2::varchar[])
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

/**
 * Every REST write is a user edit, and a user edit has to move
 * `client_updated_at` — not just `updated_at`.
 *
 * The two are not interchangeable. `updated_at` is server time and drives the
 * pull cursor; `client_updated_at` is the edit time and decides last-write-wins
 * on both sides. A write that moves only the first is *sent* to the other
 * clients and then discarded by their merge rule, because it arrives claiming
 * to be as old as the row they already have. Nothing errors. The desktop simply
 * never shows what the phone did.
 */
const CLIENT_CLOCK = 'client_updated_at = NOW()';

export async function createBook(pool, userId, input) {
  const data = normalise(input);
  const { tags = [], ...fields } = data;

  const columns = ['user_id', 'client_updated_at'];
  const values = [userId, new Date()];

  for (const [key, column] of Object.entries(COLUMN_OF)) {
    if (fields[key] !== undefined) {
      columns.push(column);
      values.push(fields[key]);
    }
  }

  const placeholders = values.map((_, i) => `$${i + 1}`);

  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const { rows } = await client.query(
      `INSERT INTO books (${columns.join(', ')}) VALUES (${placeholders.join(', ')}) RETURNING id`,
      values,
    );
    const id = rows[0].id;
    await setTags(client, userId, id, tags);
    await client.query('COMMIT');
    return getBook(pool, userId, id);
  } catch (err) {
    await client.query('ROLLBACK');
    throw err;
  } finally {
    client.release();
  }
}

export async function updateBook(pool, userId, id, input) {
  const data = normalise(input);
  const { tags, ...fields } = data;

  const assignments = [];
  const values = [];

  for (const [key, column] of Object.entries(COLUMN_OF)) {
    if (fields[key] !== undefined) {
      values.push(fields[key]);
      assignments.push(`${column} = $${values.length}`);
    }
  }

  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    // Scope the existence check to the owner, so a book belonging to someone
    // else is indistinguishable from one that does not exist.
    const { rows: owned } = await client.query(
      'SELECT 1 FROM books WHERE id = $1 AND user_id = $2 FOR UPDATE',
      [id, userId],
    );
    if (owned.length === 0) {
      await client.query('ROLLBACK');
      return null;
    }

    if (assignments.length > 0) {
      values.push(id, userId);
      await client.query(
        `UPDATE books SET ${assignments.join(', ')}, updated_at = NOW(), ${CLIENT_CLOCK}
          WHERE id = $${values.length - 1} AND user_id = $${values.length}`,
        values,
      );
    }

    if (tags !== undefined) {
      await setTags(client, userId, id, tags);
      await client.query(`UPDATE books SET updated_at = NOW(), ${CLIENT_CLOCK} WHERE id = $1`, [id]);
    }

    await client.query('COMMIT');
    return getBook(pool, userId, id);
  } catch (err) {
    await client.query('ROLLBACK');
    throw err;
  } finally {
    client.release();
  }
}

/**
 * Soft delete. A hard DELETE cannot propagate: a device that never saw the row
 * cannot tell "deleted" from "never existed", so its next pull resurrects it.
 */
export async function deleteBook(pool, userId, id) {
  const { rowCount } = await pool.query(
    `UPDATE books SET deleted_at = NOW(), updated_at = NOW(), ${CLIENT_CLOCK}
      WHERE id = $1 AND user_id = $2 AND deleted_at IS NULL`,
    [id, userId],
  );
  return rowCount > 0;
}

/**
 * Record progress: move the book's current page and log the reading session, in
 * one transaction.
 *
 * This pairing is the invariant. On the desktop, `addPages()` and
 * `markAsRead()` are the only paths that move progress and both write the book
 * *and* a session, so statistics cannot drift from the library. Exposing a bare
 * "update currentPage" over HTTP would hand every client a way around that —
 * hence progress is its own endpoint rather than a PATCH field.
 *
 * The session merge itself is SQL: ON CONFLICT ... LEAST/GREATEST, which makes
 * a repeated push for the same day idempotent and independent of arrival order.
 * Two clients syncing the same reading day converge without a resolver.
 *
 * @returns {Promise<{ book: object, pagesRead: number } | null>}
 */
export async function recordProgress(pool, userId, id, newCurrentPage) {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    const { rows } = await client.query(
      'SELECT current_page, page_count FROM books WHERE id = $1 AND user_id = $2 FOR UPDATE',
      [id, userId],
    );
    if (rows.length === 0) {
      await client.query('ROLLBACK');
      return null;
    }

    const previousPage = rows[0].current_page ?? 0;
    // Going backwards is a correction, not reading. Record the page move but
    // log no session, or the statistics gain pages nobody read.
    const pagesRead = Math.max(0, newCurrentPage - previousPage);

    await client.query(
      `UPDATE books
          SET current_page = $1,
              status = CASE WHEN status = 'planned' THEN 'reading' ELSE status END,
              updated_at = NOW(),
              ${CLIENT_CLOCK}
        WHERE id = $2 AND user_id = $3`,
      [newCurrentPage, id, userId],
    );

    if (pagesRead > 0) {
      await client.query(
        // The session carries the client clock too, or it is invisible to sync:
        // a NULL there never compares greater than anything, so the row would
        // sit on the server and never reach the desktop's statistics.
        `INSERT INTO reading_sessions (user_id, book_id, session_date, page_start, page_end, source,
                                       client_updated_at)
         VALUES ($1, $2, CURRENT_DATE, $3, $4, 'manual', NOW())
         ON CONFLICT (book_id, session_date, source)
         DO UPDATE SET page_start = LEAST(reading_sessions.page_start, EXCLUDED.page_start),
                       page_end   = GREATEST(reading_sessions.page_end, EXCLUDED.page_end),
                       client_updated_at = NOW()`,
        [userId, id, previousPage, newCurrentPage],
      );
    }

    await client.query('COMMIT');
    return { book: await getBook(pool, userId, id), pagesRead };
  } catch (err) {
    await client.query('ROLLBACK');
    throw err;
  } finally {
    client.release();
  }
}

/**
 * Finish a book: status, end date, reread tally, and the closing session.
 *
 * Mirrors the desktop's `markAsRead()`, including incrementing read_count, so
 * the two paths cannot disagree about what "finished" means.
 */
export async function completeBook(pool, userId, id, { rating, review } = {}) {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    const { rows } = await client.query(
      'SELECT current_page, page_count FROM books WHERE id = $1 AND user_id = $2 FOR UPDATE',
      [id, userId],
    );
    if (rows.length === 0) {
      await client.query('ROLLBACK');
      return null;
    }

    const previousPage = rows[0].current_page ?? 0;
    const pageCount = rows[0].page_count ?? 0;

    await client.query(
      `UPDATE books
          SET status = 'read',
              end_date = COALESCE(end_date, CURRENT_DATE),
              current_page = GREATEST(current_page, page_count),
              read_count = read_count + 1,
              rating = COALESCE($1, rating),
              review = COALESCE($2, review),
              updated_at = NOW(),
              ${CLIENT_CLOCK}
        WHERE id = $3 AND user_id = $4`,
      [rating === 0 ? null : (rating ?? null), review ?? null, id, userId],
    );

    if (pageCount > previousPage) {
      await client.query(
        `INSERT INTO reading_sessions (user_id, book_id, session_date, page_start, page_end, source,
                                       client_updated_at)
         VALUES ($1, $2, CURRENT_DATE, $3, $4, 'completion', NOW())
         ON CONFLICT (book_id, session_date, source)
         DO UPDATE SET page_start = LEAST(reading_sessions.page_start, EXCLUDED.page_start),
                       page_end   = GREATEST(reading_sessions.page_end, EXCLUDED.page_end),
                       client_updated_at = NOW()`,
        [userId, id, previousPage, pageCount],
      );
    }

    await client.query('COMMIT');
    return getBook(pool, userId, id);
  } catch (err) {
    await client.query('ROLLBACK');
    throw err;
  } finally {
    client.release();
  }
}
