/**
 * Books API against a real PostgreSQL.
 *
 * Two things here are worth more than the CRUD coverage: that a second account
 * cannot see or touch the first's books, and that progress writes the book and
 * the session together. Both are properties of the SQL, so both need a real
 * database.
 */
import assert from 'node:assert/strict';
import { after, before, describe, test } from 'node:test';

import pg from 'pg';

import { buildApp } from '../src/app.js';
import { loadConfig } from '../src/config.js';

const DATABASE_URL = process.env.TEST_DATABASE_URL;

const OWNER = 'books-owner@example.test';
const STRANGER = 'books-stranger@example.test';

describe('books', { skip: DATABASE_URL ? false : 'TEST_DATABASE_URL not set' }, () => {
  /** @type {import('pg').Pool} */
  let pool;
  /** @type {import('fastify').FastifyInstance} */
  let app;
  let ownerAuth;
  let strangerAuth;

  before(async () => {
    pool = new pg.Pool({ connectionString: DATABASE_URL });
    const { hash, Algorithm } = await import('@node-rs/argon2');
    const passwordHash = await hash('irrelevant-for-these-tests', { algorithm: Algorithm.Argon2id });

    await pool.query('DELETE FROM users WHERE email = ANY($1)', [[OWNER, STRANGER]]);
    const ids = {};
    for (const email of [OWNER, STRANGER]) {
      const { rows } = await pool.query(
        'INSERT INTO users (email, password_hash) VALUES ($1, $2) RETURNING id',
        [email, passwordHash],
      );
      ids[email] = rows[0].id;
    }

    app = await buildApp(
      loadConfig({
        DATABASE_URL,
        JWT_SECRET: 'test-secret-long-enough-to-pass-the-length-check',
        NODE_ENV: 'test',
        LOG_LEVEL: 'silent',
      }),
      { pool },
    );

    ownerAuth = { authorization: `Bearer ${app.jwt.sign({ sub: ids[OWNER] })}` };
    strangerAuth = { authorization: `Bearer ${app.jwt.sign({ sub: ids[STRANGER] })}` };
  });

  after(async () => {
    await app.close();
    await pool.query('DELETE FROM users WHERE email = ANY($1)', [[OWNER, STRANGER]]);
    await pool.end();
  });

  const create = (payload, headers = ownerAuth) =>
    app.inject({ method: 'POST', url: '/v1/books', headers, payload });

  test('creates a book and reads it back with the desktop field names', async () => {
    const res = await create({
      title: 'Hobbit',
      author: 'Tolkien',
      pageCount: 310,
      status: 'reading',
      tags: ['fantasy', 'classic'],
    });

    assert.equal(res.statusCode, 201);
    const book = res.json();
    assert.equal(book.title, 'Hobbit');
    assert.equal(book.pageCount, 310);
    assert.equal(book.readCount, 0);
    assert.deepEqual(book.tags, ['classic', 'fantasy']);

    const fetched = await app.inject({ method: 'GET', url: `/v1/books/${book.id}`, headers: ownerAuth });
    assert.equal(fetched.statusCode, 200);
    assert.equal(fetched.json().title, 'Hobbit');
  });

  test('rejects an unknown field instead of dropping it silently', async () => {
    const res = await create({ title: 'X', author: 'Y', pagecount: 100 });
    assert.equal(res.statusCode, 400);
  });

  test('rating 0 means unrated, not a constraint violation', async () => {
    const res = await create({ title: 'Unrated', author: 'A', rating: 0 });
    assert.equal(res.statusCode, 201);
    assert.equal(res.json().rating, null);
  });

  test('an empty date string is stored as no date', async () => {
    // The desktop sends '' for an unset QDate; DATE cannot take it.
    const res = await create({ title: 'Dateless', author: 'A', startDate: '', endDate: '' });
    assert.equal(res.statusCode, 201);
    assert.equal(res.json().startDate, null);
  });

  test('a date survives the round trip without shifting a day', async () => {
    // pg parses DATE into a local-midnight Date by default, which serialises to
    // the previous day east of Greenwich. The type parser prevents that.
    const res = await create({ title: 'Dated', author: 'A', endDate: '2026-08-08' });
    assert.equal(res.json().endDate, '2026-08-08');
  });

  describe('owner isolation', () => {
    let bookId;

    before(async () => {
      bookId = (await create({ title: 'Private', author: 'Owner' })).json().id;
    });

    test('another account cannot read it', async () => {
      const res = await app.inject({ method: 'GET', url: `/v1/books/${bookId}`, headers: strangerAuth });
      // 404 rather than 403: telling them it exists is itself a disclosure.
      assert.equal(res.statusCode, 404);
    });

    test('another account cannot update or delete it', async () => {
      const patched = await app.inject({
        method: 'PATCH',
        url: `/v1/books/${bookId}`,
        headers: strangerAuth,
        payload: { title: 'Stolen' },
      });
      assert.equal(patched.statusCode, 404);

      const deleted = await app.inject({
        method: 'DELETE',
        url: `/v1/books/${bookId}`,
        headers: strangerAuth,
      });
      assert.equal(deleted.statusCode, 404);

      // And it is genuinely untouched, not merely reported as missing.
      const still = await app.inject({ method: 'GET', url: `/v1/books/${bookId}`, headers: ownerAuth });
      assert.equal(still.json().title, 'Private');
    });

    test('another account cannot move its progress', async () => {
      const res = await app.inject({
        method: 'POST',
        url: `/v1/books/${bookId}/progress`,
        headers: strangerAuth,
        payload: { currentPage: 50 },
      });
      assert.equal(res.statusCode, 404);
    });

    test("listing shows only the caller's books", async () => {
      const mine = await app.inject({ method: 'GET', url: '/v1/books', headers: ownerAuth });
      const theirs = await app.inject({ method: 'GET', url: '/v1/books', headers: strangerAuth });

      assert.ok(mine.json().books.length > 0);
      assert.equal(theirs.json().books.length, 0);
    });
  });

  describe('progress writes the book and the session together', () => {
    let bookId;

    before(async () => {
      bookId = (await create({ title: 'Progressing', author: 'A', pageCount: 300, status: 'planned' })).json().id;
    });

    test('recording progress moves the page and logs a session', async () => {
      const res = await app.inject({
        method: 'POST',
        url: `/v1/books/${bookId}/progress`,
        headers: ownerAuth,
        payload: { currentPage: 40 },
      });

      assert.equal(res.statusCode, 200);
      assert.equal(res.json().pagesRead, 40);
      assert.equal(res.json().book.currentPage, 40);
      // 'planned' becomes 'reading' on first progress, as the desktop does.
      assert.equal(res.json().book.status, 'reading');

      const { rows } = await pool.query(
        "SELECT page_start, page_end FROM reading_sessions WHERE book_id = $1 AND source = 'manual'",
        [bookId],
      );
      assert.equal(rows.length, 1);
      assert.equal(rows[0].page_end, 40);
    });

    test('a second push the same day merges instead of duplicating', async () => {
      await app.inject({
        method: 'POST',
        url: `/v1/books/${bookId}/progress`,
        headers: ownerAuth,
        payload: { currentPage: 90 },
      });

      const { rows } = await pool.query(
        "SELECT page_start, page_end FROM reading_sessions WHERE book_id = $1 AND source = 'manual'",
        [bookId],
      );
      // One row for the day, widened — this is the ON CONFLICT LEAST/GREATEST
      // merge that lets two clients push in any order and converge.
      assert.equal(rows.length, 1);
      assert.equal(rows[0].page_start, 0);
      assert.equal(rows[0].page_end, 90);
    });

    test('re-sending the same page is idempotent', async () => {
      const before = await pool.query('SELECT count(*) FROM reading_sessions WHERE book_id = $1', [bookId]);

      const res = await app.inject({
        method: 'POST',
        url: `/v1/books/${bookId}/progress`,
        headers: ownerAuth,
        payload: { currentPage: 90 },
      });
      assert.equal(res.json().pagesRead, 0);

      const after = await pool.query('SELECT count(*) FROM reading_sessions WHERE book_id = $1', [bookId]);
      assert.deepEqual(before.rows, after.rows);
    });

    test('correcting the page backwards logs no reading', async () => {
      const res = await app.inject({
        method: 'POST',
        url: `/v1/books/${bookId}/progress`,
        headers: ownerAuth,
        payload: { currentPage: 60 },
      });

      assert.equal(res.json().pagesRead, 0, 'going back is a correction, not reading');
      assert.equal(res.json().book.currentPage, 60);

      const { rows } = await pool.query(
        "SELECT page_end FROM reading_sessions WHERE book_id = $1 AND source = 'manual'",
        [bookId],
      );
      // GREATEST keeps the high-water mark, so the correction cannot erase
      // pages that really were read.
      assert.equal(rows[0].page_end, 90);
    });

    test('currentPage cannot be moved through PATCH, bypassing the session', async () => {
      const res = await app.inject({
        method: 'PATCH',
        url: `/v1/books/${bookId}`,
        headers: ownerAuth,
        payload: { currentPage: 250 },
      });

      // It is a legitimate field to edit — but the point is that doing so does
      // NOT invent a reading session, so statistics stay honest.
      const sessions = await pool.query(
        "SELECT page_end FROM reading_sessions WHERE book_id = $1 AND source = 'manual'",
        [bookId],
      );
      assert.equal(res.statusCode, 200);
      assert.equal(sessions.rows[0].page_end, 90, 'a PATCH must not fabricate reading');
    });
  });

  describe('completing a book', () => {
    test('sets status, end date, rating and bumps the reread count', async () => {
      const bookId = (await create({ title: 'Finishable', author: 'A', pageCount: 200 })).json().id;

      const res = await app.inject({
        method: 'POST',
        url: `/v1/books/${bookId}/complete`,
        headers: ownerAuth,
        payload: { rating: 5, review: 'Good' },
      });

      assert.equal(res.statusCode, 200);
      const book = res.json();
      assert.equal(book.status, 'read');
      assert.equal(book.rating, 5);
      assert.equal(book.review, 'Good');
      assert.equal(book.readCount, 1);
      assert.equal(book.currentPage, 200);
      assert.ok(book.endDate, 'end date should be set');

      const { rows } = await pool.query(
        "SELECT page_end FROM reading_sessions WHERE book_id = $1 AND source = 'completion'",
        [bookId],
      );
      assert.equal(rows.length, 1);
      assert.equal(rows[0].page_end, 200);
    });

    test('finishing again counts as a reread', async () => {
      const bookId = (await create({ title: 'Reread', author: 'A', pageCount: 100 })).json().id;

      await app.inject({ method: 'POST', url: `/v1/books/${bookId}/complete`, headers: ownerAuth, payload: {} });
      const second = await app.inject({
        method: 'POST',
        url: `/v1/books/${bookId}/complete`,
        headers: ownerAuth,
        payload: {},
      });

      assert.equal(second.json().readCount, 2);
    });
  });

  test('tags are created per owner and reused, not duplicated', async () => {
    const a = (await create({ title: 'Tagged A', author: 'A', tags: ['shared-tag'] })).json();
    const b = (await create({ title: 'Tagged B', author: 'B', tags: ['shared-tag'] })).json();

    assert.deepEqual(a.tags, ['shared-tag']);
    assert.deepEqual(b.tags, ['shared-tag']);

    const { rows } = await pool.query(
      "SELECT count(*) FROM tags WHERE name = 'shared-tag' AND user_id = (SELECT id FROM users WHERE email = $1)",
      [OWNER],
    );
    assert.equal(rows[0].count, '1', 'the tag should exist once for this owner');
  });

  test('deleting a book removes it', async () => {
    const bookId = (await create({ title: 'Doomed', author: 'A' })).json().id;

    const deleted = await app.inject({ method: 'DELETE', url: `/v1/books/${bookId}`, headers: ownerAuth });
    assert.equal(deleted.statusCode, 204);

    const gone = await app.inject({ method: 'GET', url: `/v1/books/${bookId}`, headers: ownerAuth });
    assert.equal(gone.statusCode, 404);
  });

  test('every book route rejects an anonymous caller', async () => {
    for (const [method, url] of [
      ['GET', '/v1/books'],
      ['GET', '/v1/books/1'],
      ['POST', '/v1/books'],
      ['PATCH', '/v1/books/1'],
      ['DELETE', '/v1/books/1'],
      ['POST', '/v1/books/1/progress'],
      ['POST', '/v1/books/1/complete'],
    ]) {
      const res = await app.inject({ method, url, payload: {} });
      assert.equal(res.statusCode, 401, `${method} ${url} should require a token`);
    }
  });
});
