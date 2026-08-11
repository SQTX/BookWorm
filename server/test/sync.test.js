/**
 * Sync tests against a real PostgreSQL.
 *
 * These assert the properties the protocol is built on, not the plumbing:
 * tombstones stay dead, sessions converge whatever order they arrive in, and
 * last-write-wins is decided by timestamp rather than by request order.
 */
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { after, before, describe, test } from 'node:test';

import pg from 'pg';

import { buildApp } from '../src/app.js';
import { loadConfig } from '../src/config.js';

const DATABASE_URL = process.env.TEST_DATABASE_URL;
const EMAIL = 'sync-test@example.test';

describe('sync', { skip: DATABASE_URL ? false : 'TEST_DATABASE_URL not set' }, () => {
  /** @type {import('pg').Pool} */
  let pool;
  /** @type {import('fastify').FastifyInstance} */
  let app;
  let auth;

  before(async () => {
    pool = new pg.Pool({ connectionString: DATABASE_URL });
    const { hash, Algorithm } = await import('@node-rs/argon2');
    const passwordHash = await hash('irrelevant', { algorithm: Algorithm.Argon2id });

    await pool.query('DELETE FROM users WHERE email = $1', [EMAIL]);
    const { rows } = await pool.query(
      'INSERT INTO users (email, password_hash) VALUES ($1, $2) RETURNING id',
      [EMAIL, passwordHash],
    );

    app = await buildApp(
      loadConfig({
        DATABASE_URL,
        JWT_SECRET: 'test-secret-long-enough-to-pass-the-length-check',
        NODE_ENV: 'test',
        LOG_LEVEL: 'silent',
      }),
      { pool },
    );
    auth = { authorization: `Bearer ${app.jwt.sign({ sub: rows[0].id })}` };
  });

  after(async () => {
    await app.close();
    await pool.query('DELETE FROM users WHERE email = $1', [EMAIL]);
    await pool.end();
  });

  const push = (body) => app.inject({ method: 'POST', url: '/v1/sync', headers: auth, payload: body });
  const pull = (since) =>
    app.inject({ method: 'GET', url: since ? `/v1/sync?since=${encodeURIComponent(since)}` : '/v1/sync', headers: auth });

  const bookRow = (overrides = {}) => ({
    uuid: randomUUID(),
    title: 'Synced',
    author: 'A',
    pageCount: 200,
    status: 'reading',
    updatedAt: new Date().toISOString(),
    ...overrides,
  });

  test('a pushed book comes back in the pull with the same uuid', async () => {
    const book = bookRow();
    const res = await push({ books: [book] });

    assert.equal(res.statusCode, 200);
    const returned = res.json().changes.books.find((b) => b.uuid === book.uuid);
    assert.ok(returned, 'the pushed book should return in the same exchange');
    assert.equal(returned.title, 'Synced');
  });

  test('a first sync with no cursor returns the whole library', async () => {
    const res = await pull();
    assert.equal(res.statusCode, 200);
    assert.ok(res.json().changes.books.length > 0);
    assert.ok(res.json().serverTime, 'the client needs a server cursor, not its own clock');
  });

  test('an incremental pull returns only what changed after the cursor', async () => {
    const cursor = (await pull()).json().serverTime;

    const fresh = bookRow({ title: 'After the cursor' });
    await push({ books: [fresh] });

    const res = await pull(cursor);
    const titles = res.json().changes.books.map((b) => b.title);
    assert.deepEqual(titles, ['After the cursor']);
  });

  describe('tombstones', () => {
    test('a deleted book is returned as a tombstone, not omitted', async () => {
      const book = bookRow({ title: 'To delete' });
      await push({ books: [book] });

      const cursor = (await pull()).json().serverTime;
      await push({ books: [{ ...book, updatedAt: new Date().toISOString(), deletedAt: new Date().toISOString() }] });

      const res = await pull(cursor);
      const row = res.json().changes.books.find((b) => b.uuid === book.uuid);
      // Omitting it would leave the other device unable to tell "deleted" from
      // "never existed", so it would keep the row forever.
      assert.ok(row, 'the deletion must be reported');
      assert.ok(row.deletedAt, 'as a tombstone');
    });

    test('a tombstoned book stays deleted through the REST API', async () => {
      const book = bookRow({ title: 'Gone' });
      await push({ books: [book] });
      await push({ books: [{ ...book, updatedAt: new Date().toISOString(), deletedAt: new Date().toISOString() }] });

      const list = await app.inject({ method: 'GET', url: '/v1/books', headers: auth });
      assert.ok(
        !list.json().books.some((b) => b.title === 'Gone'),
        'a soft-deleted book must not appear in normal reads',
      );
    });

    test('deleting through the REST API creates a tombstone, not a hard delete', async () => {
      const created = await app.inject({
        method: 'POST',
        url: '/v1/books',
        headers: auth,
        payload: { title: 'Rest deleted', author: 'A' },
      });
      const id = created.json().id;

      await app.inject({ method: 'DELETE', url: `/v1/books/${id}`, headers: auth });

      const { rows } = await pool.query('SELECT deleted_at FROM books WHERE id = $1', [id]);
      assert.equal(rows.length, 1, 'the row must survive so the deletion can propagate');
      assert.ok(rows[0].deleted_at);
    });
  });

  describe('conflict resolution', () => {
    test('a newer update wins', async () => {
      const book = bookRow({ title: 'Original' });
      await push({ books: [book] });

      const later = new Date(Date.parse(book.updatedAt) + 5).toISOString();
      await push({ books: [{ ...book, title: 'Newer', updatedAt: later }] });

      const { rows } = await pool.query('SELECT title FROM books WHERE uuid = $1', [book.uuid]);
      assert.equal(rows[0].title, 'Newer');
    });

    test('repeated edits milliseconds apart all apply', async () => {
      // The case an earlier version got wrong. LWW compared against updated_at,
      // which a trigger stamps with SERVER time, so after the first update
      // every realistic client edit was older than the stored value and was
      // dropped — silently, with a 200. Using a timestamp a minute in the
      // future hid it; this is what a real client does.
      const book = bookRow({ title: 'Edit 0' });
      await push({ books: [book] });

      for (let i = 1; i <= 3; i++) {
        await push({
          books: [
            {
              ...book,
              title: `Edit ${i}`,
              updatedAt: new Date(Date.parse(book.updatedAt) + i * 5).toISOString(),
            },
          ],
        });
      }

      const { rows } = await pool.query('SELECT title FROM books WHERE uuid = $1', [book.uuid]);
      assert.equal(rows[0].title, 'Edit 3', 'every successive client edit must apply');
    });

    test('the pull cursor advances on server time, not the client clock', async () => {
      // A client whose clock is behind must not write rows that sort before a
      // cursor already issued — they would never be pulled again.
      const book = bookRow({ title: 'Skewed', updatedAt: new Date(Date.now() - 86_400_000).toISOString() });
      const cursor = (await pull()).json().serverTime;

      await push({ books: [book] });

      const res = await pull(cursor);
      const found = res.json().changes.books.find((b) => b.uuid === book.uuid);
      assert.ok(found, 'a row written by a lagging clock must still appear after the cursor');
    });

    test('an older update is rejected even though it arrived later', async () => {
      const book = bookRow({ title: 'Current' });
      const now = new Date().toISOString();
      await push({ books: [{ ...book, updatedAt: now }] });

      const stale = new Date(Date.now() - 60_000).toISOString();
      await push({ books: [{ ...book, title: 'Stale', updatedAt: stale }] });

      const { rows } = await pool.query('SELECT title FROM books WHERE uuid = $1', [book.uuid]);
      // Arrival order must not decide the outcome — otherwise a device coming
      // back online overwrites newer work with whatever it had queued.
      assert.equal(rows[0].title, 'Current');
    });
  });

  describe('reading sessions do not use last-write-wins', () => {
    test('the same day pushed from two devices merges to the widest range', async () => {
      const book = bookRow({ title: 'Session book' });
      await push({ books: [book] });

      const day = '2026-08-01';
      // Deliberately out of order and with different UUIDs: two devices
      // recording the same reading day generate different ids for what is one
      // session, which is why the conflict target is the day, not the uuid.
      await push({
        readingSessions: [
          { uuid: randomUUID(), bookUuid: book.uuid, sessionDate: day, pageStart: 50, pageEnd: 90, source: 'manual', updatedAt: new Date().toISOString() },
        ],
      });
      await push({
        readingSessions: [
          { uuid: randomUUID(), bookUuid: book.uuid, sessionDate: day, pageStart: 10, pageEnd: 60, source: 'manual', updatedAt: new Date(Date.now() - 60_000).toISOString() },
        ],
      });

      const { rows } = await pool.query(
        `SELECT page_start, page_end FROM reading_sessions s JOIN books b ON b.id = s.book_id
          WHERE b.uuid = $1 AND s.session_date = $2`,
        [book.uuid, day],
      );

      assert.equal(rows.length, 1, 'one session per book per day per source');
      // LEAST/GREATEST, not LWW: the older push still widens the range, because
      // pages that were read cannot be un-read by a timestamp.
      assert.equal(rows[0].page_start, 10);
      assert.equal(rows[0].page_end, 90);
    });

    test('pushing the same session twice changes nothing', async () => {
      const book = bookRow({ title: 'Idempotent' });
      await push({ books: [book] });

      const session = {
        uuid: randomUUID(),
        bookUuid: book.uuid,
        sessionDate: '2026-08-02',
        pageStart: 0,
        pageEnd: 30,
        source: 'manual',
        updatedAt: new Date().toISOString(),
      };

      await push({ readingSessions: [session] });
      await push({ readingSessions: [session] });

      const { rows } = await pool.query(
        `SELECT count(*) FROM reading_sessions s JOIN books b ON b.id = s.book_id WHERE b.uuid = $1`,
        [book.uuid],
      );
      assert.equal(rows[0].count, '1');
    });
  });

  test('books and their tags in one batch do not collide', async () => {
    // The desktop client's first upload sends both. Pushing a book creates its
    // tags by name, so with books handled first the tags array then tried to
    // insert the same names under the client's own UUIDs and violated
    // UNIQUE (user_id, name) — failing the whole batch, not just the tag.
    const tagUuid = randomUUID();
    const book = bookRow({ title: 'Tagged in batch', tags: ['batch-collision-tag'] });

    const res = await push({
      books: [book],
      tags: [{ uuid: tagUuid, name: 'batch-collision-tag', updatedAt: new Date().toISOString() }],
    });

    assert.equal(res.statusCode, 200);

    const { rows } = await pool.query(
      "SELECT count(*) FROM tags WHERE name = 'batch-collision-tag' AND user_id = (SELECT id FROM users WHERE email = $1)",
      [EMAIL],
    );
    assert.equal(rows[0].count, '1', 'one tag, whichever identity won');

    const returned = res.json().changes.books.find((b) => b.uuid === book.uuid);
    assert.deepEqual(returned.tags, ['batch-collision-tag'], 'the book keeps its tag');
  });

  test('the same tag name from a second device does not fail the push', async () => {
    // Two machines minting different UUIDs for "fantasy" is ordinary; it must
    // resolve to one tag rather than an error.
    const name = 'two-device-tag';
    const first = await push({ tags: [{ uuid: randomUUID(), name, updatedAt: new Date().toISOString() }] });
    const second = await push({ tags: [{ uuid: randomUUID(), name, updatedAt: new Date().toISOString() }] });

    assert.equal(first.statusCode, 200);
    assert.equal(second.statusCode, 200);

    const { rows } = await pool.query(
      'SELECT count(*) FROM tags WHERE name = $1 AND user_id = (SELECT id FROM users WHERE email = $2)',
      [name, EMAIL],
    );
    assert.equal(rows[0].count, '1');
  });

  test('a tombstone carrying only a uuid deletes rather than failing', async () => {
    // What a real client sends: the row is already gone locally, so there are
    // no fields left to include. Upserting it tried to INSERT a book with no
    // title and violated NOT NULL, failing the entire batch — including the
    // unrelated rows travelling with it.
    const book = bookRow({ title: 'To be tombstoned' });
    await push({ books: [book] });

    const res = await push({
      books: [{ uuid: book.uuid, updatedAt: new Date().toISOString(), deletedAt: new Date().toISOString() }],
    });

    assert.equal(res.statusCode, 200);

    const { rows } = await pool.query('SELECT deleted_at FROM books WHERE uuid = $1', [book.uuid]);
    assert.ok(rows[0].deleted_at, 'the row is marked deleted');
  });

  test('a tombstone for a row the server never had is a no-op', async () => {
    const res = await push({
      books: [{ uuid: randomUUID(), updatedAt: new Date().toISOString(), deletedAt: new Date().toISOString() }],
    });
    assert.equal(res.statusCode, 200, 'nothing to delete is not an error');
  });

  test('a child whose book has not arrived yet is skipped, not fatal', async () => {
    // Out-of-order arrival must not fail the batch: the next sync carries the
    // child once its parent exists.
    const res = await push({
      highlights: [
        { uuid: randomUUID(), bookUuid: randomUUID(), title: 'Orphan', updatedAt: new Date().toISOString() },
      ],
    });
    assert.equal(res.statusCode, 200);
  });

  test('books push before their children within one batch', async () => {
    const book = bookRow({ title: 'Parent' });
    const res = await push({
      // Deliberately listed after the child to prove ordering is by handler,
      // not by the order of keys in the request.
      highlights: [
        { uuid: randomUUID(), bookUuid: book.uuid, title: 'Child', page: 10, updatedAt: new Date().toISOString() },
      ],
      books: [book],
    });

    assert.equal(res.statusCode, 200);
    const highlights = res.json().changes.highlights.filter((h) => h.bookUuid === book.uuid);
    assert.equal(highlights.length, 1, 'the child should land in the same batch as its parent');
  });

  test('sync rejects an anonymous caller', async () => {
    assert.equal((await app.inject({ method: 'GET', url: '/v1/sync' })).statusCode, 401);
    assert.equal((await app.inject({ method: 'POST', url: '/v1/sync', payload: {} })).statusCode, 401);
  });

  test('a row without a uuid or updatedAt is rejected', async () => {
    const noUuid = await push({ books: [{ title: 'X', author: 'Y', updatedAt: new Date().toISOString() }] });
    assert.equal(noUuid.statusCode, 400);

    const noTimestamp = await push({ books: [{ uuid: randomUUID(), title: 'X', author: 'Y' }] });
    assert.equal(noTimestamp.statusCode, 400);
  });
});
