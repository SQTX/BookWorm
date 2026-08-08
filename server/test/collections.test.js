/**
 * Tags, quotes, highlights and challenges.
 *
 * The interesting cases are the ones where ownership is indirect: quotes and
 * highlights have no user_id and reach their owner through the book, so a
 * missing join is a cross-account leak rather than a visibly wrong result.
 */
import assert from 'node:assert/strict';
import { after, before, describe, test } from 'node:test';

import pg from 'pg';

import { buildApp } from '../src/app.js';
import { loadConfig } from '../src/config.js';

const DATABASE_URL = process.env.TEST_DATABASE_URL;
const OWNER = 'coll-owner@example.test';
const STRANGER = 'coll-stranger@example.test';

describe('collections', { skip: DATABASE_URL ? false : 'TEST_DATABASE_URL not set' }, () => {
  /** @type {import('pg').Pool} */
  let pool;
  /** @type {import('fastify').FastifyInstance} */
  let app;
  let auth;
  let strangerAuth;
  let bookId;

  before(async () => {
    pool = new pg.Pool({ connectionString: DATABASE_URL });
    const { hash, Algorithm } = await import('@node-rs/argon2');
    const passwordHash = await hash('irrelevant', { algorithm: Algorithm.Argon2id });

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

    auth = { authorization: `Bearer ${app.jwt.sign({ sub: ids[OWNER] })}` };
    strangerAuth = { authorization: `Bearer ${app.jwt.sign({ sub: ids[STRANGER] })}` };

    bookId = (
      await app.inject({
        method: 'POST',
        url: '/v1/books',
        headers: auth,
        payload: { title: 'Host book', author: 'A' },
      })
    ).json().id;
  });

  after(async () => {
    await app.close();
    await pool.query('DELETE FROM users WHERE email = ANY($1)', [[OWNER, STRANGER]]);
    await pool.end();
  });

  const req = (method, url, payload, headers = auth) =>
    app.inject({ method, url: `/v1${url}`, headers, ...(payload ? { payload } : {}) });

  describe('tags', () => {
    test('create, list, update, delete', async () => {
      const created = await req('POST', '/tags', { name: 'sci-fi', color: '#112233' });
      assert.equal(created.statusCode, 201);
      const id = created.json().id;

      const listed = await req('GET', '/tags');
      assert.ok(listed.json().tags.some((t) => t.name === 'sci-fi'));

      const patched = await req('PATCH', `/tags/${id}`, { color: '#445566' });
      assert.equal(patched.json().color, '#445566');

      assert.equal((await req('DELETE', `/tags/${id}`)).statusCode, 204);
      assert.ok(!(await req('GET', '/tags')).json().tags.some((t) => t.name === 'sci-fi'));
    });

    test('re-adding a deleted tag revives it rather than colliding', async () => {
      // The unique key is (user_id, name) regardless of deleted_at, so a plain
      // insert would fail on a name the user can no longer see.
      const first = await req('POST', '/tags', { name: 'revivable' });
      await req('DELETE', `/tags/${first.json().id}`);

      const again = await req('POST', '/tags', { name: 'revivable' });
      assert.equal(again.statusCode, 201);
      assert.ok((await req('GET', '/tags')).json().tags.some((t) => t.name === 'revivable'));
    });

    test('a deleted tag leaves a tombstone so the deletion can propagate', async () => {
      const created = await req('POST', '/tags', { name: 'tombstoned' });
      await req('DELETE', `/tags/${created.json().id}`);

      const { rows } = await pool.query('SELECT deleted_at FROM tags WHERE id = $1', [created.json().id]);
      assert.equal(rows.length, 1);
      assert.ok(rows[0].deleted_at);
    });

    test('tags are per owner: the same name can exist for both', async () => {
      assert.equal((await req('POST', '/tags', { name: 'shared' })).statusCode, 201);
      assert.equal((await req('POST', '/tags', { name: 'shared' }, strangerAuth)).statusCode, 201);

      assert.equal((await req('GET', '/tags', null, strangerAuth)).json().tags.length, 1);
    });

    test('an invalid colour is rejected', async () => {
      assert.equal((await req('POST', '/tags', { name: 'bad', color: 'red' })).statusCode, 400);
    });
  });

  describe('quotes and highlights', () => {
    test('create and list a quote', async () => {
      const created = await req('POST', `/books/${bookId}/quotes`, { quote: 'A line', page: 42 });
      assert.equal(created.statusCode, 201);

      const listed = await req('GET', `/books/${bookId}/quotes`);
      assert.ok(listed.json().quotes.some((q) => q.quote === 'A line'));
    });

    test('create and list a highlight', async () => {
      const created = await req('POST', `/books/${bookId}/highlights`, { title: 'A point', page: 7, note: 'why' });
      assert.equal(created.statusCode, 201);

      const listed = await req('GET', `/books/${bookId}/highlights`);
      assert.ok(listed.json().highlights.some((h) => h.title === 'A point'));
    });

    test('a stranger cannot add a quote to a book that is not theirs', async () => {
      const res = await req('POST', `/books/${bookId}/quotes`, { quote: 'Intruder' }, strangerAuth);
      assert.equal(res.statusCode, 404);

      // And nothing was written — the ownership check is the INSERT ... SELECT
      // itself, so there is no window between checking and writing.
      const { rows } = await pool.query('SELECT 1 FROM favorite_quotes WHERE quote = $1', ['Intruder']);
      assert.equal(rows.length, 0);
    });

    test('a stranger cannot read or delete quotes on a book that is not theirs', async () => {
      const created = await req('POST', `/books/${bookId}/quotes`, { quote: 'Private line' });
      const id = created.json().id;

      const listed = await req('GET', `/books/${bookId}/quotes`, null, strangerAuth);
      assert.deepEqual(listed.json().quotes, []);

      assert.equal((await req('DELETE', `/quotes/${id}`, null, strangerAuth)).statusCode, 404);

      // Still there for the owner: reported-missing is not the same as deleted.
      assert.ok((await req('GET', `/books/${bookId}/quotes`)).json().quotes.some((q) => q.id === id));
    });

    test('a stranger cannot delete a highlight that is not theirs', async () => {
      const created = await req('POST', `/books/${bookId}/highlights`, { title: 'Mine' });
      const id = created.json().id;

      assert.equal((await req('DELETE', `/highlights/${id}`, null, strangerAuth)).statusCode, 404);
      assert.ok((await req('GET', `/books/${bookId}/highlights`)).json().highlights.some((h) => h.id === id));
    });

    test('quotes on a soft-deleted book disappear from reads', async () => {
      const doomed = (await req('POST', '/books', { title: 'Doomed host', author: 'A' })).json().id;
      await req('POST', `/books/${doomed}/quotes`, { quote: 'On a doomed book' });

      await req('DELETE', `/books/${doomed}`);

      assert.deepEqual((await req('GET', `/books/${doomed}/quotes`)).json().quotes, []);
    });
  });

  describe('challenges', () => {
    test('create, list, update, delete', async () => {
      const created = await req('POST', '/challenges', {
        name: 'Summer',
        deadline: '2026-09-01',
        metric: 'pages',
        targetValue: 5000,
      });
      assert.equal(created.statusCode, 201);
      assert.equal(created.json().targetValue, 5000);
      const id = created.json().id;

      assert.ok((await req('GET', '/challenges')).json().challenges.some((c) => c.id === id));

      const patched = await req('PATCH', `/challenges/${id}`, { targetValue: 6000 });
      assert.equal(patched.json().targetValue, 6000);

      assert.equal((await req('DELETE', `/challenges/${id}`)).statusCode, 204);
      assert.ok(!(await req('GET', '/challenges')).json().challenges.some((c) => c.id === id));
    });

    test('the legacy target_books column is kept in step with targetValue', async () => {
      // The desktop still reads target_books. Letting the two drift would make
      // a challenge show a different target depending on which client opened it.
      const created = await req('POST', '/challenges', { name: 'Legacy', deadline: '2026-12-31', targetValue: 12 });
      const id = created.json().id;

      let { rows } = await pool.query('SELECT target_books, target_value FROM challenges WHERE id = $1', [id]);
      assert.equal(rows[0].target_books, rows[0].target_value);

      await req('PATCH', `/challenges/${id}`, { targetValue: 24 });
      ({ rows } = await pool.query('SELECT target_books, target_value FROM challenges WHERE id = $1', [id]));
      assert.equal(rows[0].target_books, 24);
      assert.equal(rows[0].target_value, 24);
    });

    test('a stranger sees none of them and cannot delete one', async () => {
      const created = await req('POST', '/challenges', { name: 'Private goal', deadline: '2026-10-01' });

      assert.deepEqual((await req('GET', '/challenges', null, strangerAuth)).json().challenges, []);
      assert.equal((await req('DELETE', `/challenges/${created.json().id}`, null, strangerAuth)).statusCode, 404);
    });

    test('an unknown metric is rejected', async () => {
      const res = await req('POST', '/challenges', { name: 'X', deadline: '2026-10-01', metric: 'chapters' });
      assert.equal(res.statusCode, 400);
    });
  });

  test('every collection route rejects an anonymous caller', async () => {
    for (const [method, url] of [
      ['GET', '/v1/tags'],
      ['POST', '/v1/tags'],
      ['DELETE', '/v1/tags/1'],
      ['GET', '/v1/books/1/quotes'],
      ['POST', '/v1/books/1/quotes'],
      ['DELETE', '/v1/quotes/1'],
      ['GET', '/v1/books/1/highlights'],
      ['DELETE', '/v1/highlights/1'],
      ['GET', '/v1/challenges'],
      ['POST', '/v1/challenges'],
      ['DELETE', '/v1/challenges/1'],
    ]) {
      const res = await app.inject({ method, url, payload: {} });
      assert.equal(res.statusCode, 401, `${method} ${url} should require a token`);
    }
  });
});
