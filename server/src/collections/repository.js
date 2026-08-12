/**
 * Tags, quotes, highlights and challenges.
 *
 * Mechanically similar to books and following the same rules: every query
 * filters on the owner, every value is a bound parameter, and deletes are soft
 * so they can propagate.
 *
 * Quotes and highlights have no `user_id` of their own — they hang off a book
 * and inherit its owner. Their scope therefore comes from a join, never from a
 * column, and a query that forgets the join is a leak rather than a bug that
 * shows up as wrong output.
 */

// ─── Tags ────────────────────────────────────────────────────────────────────

export async function listTags(pool, userId) {
  const { rows } = await pool.query(
    `SELECT id, uuid, name, color FROM tags
      WHERE user_id = $1 AND deleted_at IS NULL ORDER BY name`,
    [userId],
  );
  return rows;
}

export async function createTag(pool, userId, { name, color }) {
  // A tag deleted earlier and re-added should come back rather than collide
  // with its own tombstone — the unique key is (user_id, name) regardless of
  // deleted_at, so an insert would otherwise fail on a name the user cannot see.
  const { rows } = await pool.query(
    `INSERT INTO tags (user_id, name, color) VALUES ($1, $2, $3)
     ON CONFLICT (user_id, name) DO UPDATE
        SET color = EXCLUDED.color, deleted_at = NULL,
            client_updated_at = NOW()
     RETURNING id, uuid, name, color`,
    [userId, name, color ?? '#808080'],
  );
  return rows[0];
}

export async function updateTag(pool, userId, id, { name, color }) {
  const { rows } = await pool.query(
    `UPDATE tags SET name = COALESCE($1, name), color = COALESCE($2, color),
                     client_updated_at = NOW()
      WHERE id = $3 AND user_id = $4 AND deleted_at IS NULL
      RETURNING id, uuid, name, color`,
    [name ?? null, color ?? null, id, userId],
  );
  return rows[0] ?? null;
}

export async function deleteTag(pool, userId, id) {
  const { rowCount } = await pool.query(
    `UPDATE tags SET deleted_at = NOW(), client_updated_at = NOW()
      WHERE id = $1 AND user_id = $2 AND deleted_at IS NULL`,
    [id, userId],
  );
  return rowCount > 0;
}

// ─── Quotes and highlights ───────────────────────────────────────────────────

export async function listQuotes(pool, userId, bookId) {
  const { rows } = await pool.query(
    `SELECT q.id, q.uuid, q.quote, q.page
       FROM favorite_quotes q JOIN books b ON b.id = q.book_id
      WHERE q.book_id = $1 AND b.user_id = $2
        AND q.deleted_at IS NULL AND b.deleted_at IS NULL
      ORDER BY q.page NULLS LAST, q.id`,
    [bookId, userId],
  );
  return rows;
}

export async function createQuote(pool, userId, bookId, { quote, page }) {
  // The INSERT ... SELECT is the ownership check: no row is produced unless the
  // book belongs to the caller, so there is no window between checking and
  // writing.
  const { rows } = await pool.query(
    `INSERT INTO favorite_quotes (book_id, quote, page, client_updated_at)
     SELECT b.id, $1, $2, NOW() FROM books b
      WHERE b.id = $3 AND b.user_id = $4 AND b.deleted_at IS NULL
     RETURNING id, uuid, quote, page`,
    [quote, page ?? null, bookId, userId],
  );
  return rows[0] ?? null;
}

export async function deleteQuote(pool, userId, id) {
  const { rowCount } = await pool.query(
    `UPDATE favorite_quotes q SET deleted_at = NOW(), client_updated_at = NOW()
       FROM books b
      WHERE q.id = $1 AND b.id = q.book_id AND b.user_id = $2 AND q.deleted_at IS NULL`,
    [id, userId],
  );
  return rowCount > 0;
}

export async function listHighlights(pool, userId, bookId) {
  const { rows } = await pool.query(
    `SELECT h.id, h.uuid, h.title, h.page, h.note
       FROM highlights h JOIN books b ON b.id = h.book_id
      WHERE h.book_id = $1 AND b.user_id = $2
        AND h.deleted_at IS NULL AND b.deleted_at IS NULL
      ORDER BY h.page NULLS LAST, h.id`,
    [bookId, userId],
  );
  return rows;
}

export async function createHighlight(pool, userId, bookId, { title, page, note }) {
  const { rows } = await pool.query(
    `INSERT INTO highlights (book_id, title, page, note, client_updated_at)
     SELECT b.id, $1, $2, $3, NOW() FROM books b
      WHERE b.id = $4 AND b.user_id = $5 AND b.deleted_at IS NULL
     RETURNING id, uuid, title, page, note`,
    [title, page ?? null, note ?? null, bookId, userId],
  );
  return rows[0] ?? null;
}

export async function deleteHighlight(pool, userId, id) {
  const { rowCount } = await pool.query(
    `UPDATE highlights h SET deleted_at = NOW(), client_updated_at = NOW()
       FROM books b
      WHERE h.id = $1 AND b.id = h.book_id AND b.user_id = $2 AND h.deleted_at IS NULL`,
    [id, userId],
  );
  return rowCount > 0;
}

// ─── Challenges ──────────────────────────────────────────────────────────────

const CHALLENGE_COLUMNS = `id, uuid, name, deadline, metric,
                           target_value AS "targetValue",
                           period_unit AS "periodUnit",
                           period_count AS "periodCount"`;

export async function listChallenges(pool, userId) {
  const { rows } = await pool.query(
    `SELECT ${CHALLENGE_COLUMNS} FROM challenges
      WHERE user_id = $1 AND deleted_at IS NULL ORDER BY deadline`,
    [userId],
  );
  return rows;
}

export async function createChallenge(pool, userId, input) {
  const { name, deadline, metric = 'books', targetValue = 1, periodUnit = 'custom', periodCount = 0 } = input;

  const { rows } = await pool.query(
    `INSERT INTO challenges (user_id, name, deadline, metric, target_value,
                             period_unit, period_count, target_books, client_updated_at)
     VALUES ($1, $2, $3, $4, $5, $6, $7, $5, NOW())
     RETURNING ${CHALLENGE_COLUMNS}`,
    // target_books repeats $5 deliberately: it is the legacy column the desktop
    // still reads, kept in step so the two cannot disagree.
    [userId, name, deadline, metric, targetValue, periodUnit, periodCount],
  );
  return rows[0];
}

export async function updateChallenge(pool, userId, id, input) {
  const { name, deadline, metric, targetValue, periodUnit, periodCount } = input;

  const { rows } = await pool.query(
    `UPDATE challenges
        SET name = COALESCE($1, name),
            deadline = COALESCE($2, deadline),
            metric = COALESCE($3, metric),
            target_value = COALESCE($4, target_value),
            target_books = COALESCE($4, target_books),
            period_unit = COALESCE($5, period_unit),
            period_count = COALESCE($6, period_count),
            client_updated_at = NOW()
      WHERE id = $7 AND user_id = $8 AND deleted_at IS NULL
      RETURNING ${CHALLENGE_COLUMNS}`,
    [name ?? null, deadline ?? null, metric ?? null, targetValue ?? null,
     periodUnit ?? null, periodCount ?? null, id, userId],
  );
  return rows[0] ?? null;
}

export async function deleteChallenge(pool, userId, id) {
  const { rowCount } = await pool.query(
    `UPDATE challenges SET deleted_at = NOW(), client_updated_at = NOW()
      WHERE id = $1 AND user_id = $2 AND deleted_at IS NULL`,
    [id, userId],
  );
  return rowCount > 0;
}
