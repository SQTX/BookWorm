/**
 * Covers.
 *
 * The cases that matter are the ones where a plausible-looking file is not an
 * image, and the ones where the same bytes must not be stored twice — covers
 * are ~98% of this application's storage volume, so deduplication is the
 * difference between 22 MB and 40 MB per 500 books.
 */
import assert from 'node:assert/strict';
import { mkdtemp, rm, stat } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { after, before, describe, test } from 'node:test';

import pg from 'pg';
import sharp from 'sharp';

import { buildApp } from '../src/app.js';
import { loadConfig } from '../src/config.js';
import { collectGarbage, hashBytes, pathFor } from '../src/covers/storage.js';

const DATABASE_URL = process.env.TEST_DATABASE_URL;
const EMAIL = 'covers-test@example.test';

/** @param {{ width?: number, height?: number, tint?: string }} opts */
const makeImage = ({ width = 600, height = 900, tint = '#336699' } = {}) =>
  sharp({ create: { width, height, channels: 3, background: tint } }).jpeg().toBuffer();

describe('covers', { skip: DATABASE_URL ? false : 'TEST_DATABASE_URL not set' }, () => {
  /** @type {import('pg').Pool} */
  let pool;
  /** @type {import('fastify').FastifyInstance} */
  let app;
  let auth;
  let coverDir;

  before(async () => {
    coverDir = await mkdtemp(join(tmpdir(), 'bookworm-covers-'));
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
        COVER_DIR: coverDir,
      }),
      { pool },
    );
    auth = { authorization: `Bearer ${app.jwt.sign({ sub: rows[0].id })}` };
  });

  after(async () => {
    await app.close();
    await pool.query('DELETE FROM users WHERE email = $1', [EMAIL]);
    await pool.query("DELETE FROM covers WHERE hash IN (SELECT hash FROM covers)");
    await pool.end();
    await rm(coverDir, { recursive: true, force: true });
  });

  /** Build a multipart body by hand — inject() has no multipart helper. */
  const upload = (buffer, filename = 'cover.jpg', contentType = 'image/jpeg') => {
    const boundary = '----bookworm-test-boundary';
    const head = Buffer.from(
      `--${boundary}\r\nContent-Disposition: form-data; name="file"; filename="${filename}"\r\n` +
        `Content-Type: ${contentType}\r\n\r\n`,
    );
    const tail = Buffer.from(`\r\n--${boundary}--\r\n`);

    return app.inject({
      method: 'POST',
      url: '/v1/covers',
      headers: { ...auth, 'content-type': `multipart/form-data; boundary=${boundary}` },
      payload: Buffer.concat([head, buffer, tail]),
    });
  };

  test('an upload returns a content hash and writes both variants', async () => {
    const image = await makeImage();
    const res = await upload(image);

    assert.equal(res.statusCode, 201);
    const { hash, deduplicated } = res.json();
    assert.equal(hash, hashBytes(image), 'the hash is of the original bytes');
    assert.equal(deduplicated, false);

    // Both sizes exist on disk, and the thumbnail is genuinely smaller.
    const full = await stat(pathFor(coverDir, hash, 'full'));
    const thumb = await stat(pathFor(coverDir, hash, 'thumb'));
    assert.ok(full.size > 0);
    assert.ok(thumb.size < full.size);
  });

  test('the same bytes are stored once', async () => {
    const image = await makeImage({ tint: '#aa3344' });

    const first = await upload(image);
    const second = await upload(image);

    assert.equal(first.json().hash, second.json().hash);
    assert.equal(second.json().deduplicated, true, 'the second upload must not re-encode or re-store');

    const { rows } = await pool.query('SELECT count(*) FROM covers WHERE hash = $1', [first.json().hash]);
    assert.equal(rows[0].count, '1');
  });

  test('re-encoding shrinks a large original', async () => {
    const image = await makeImage({ width: 2000, height: 3000, tint: '#207020' });
    const res = await upload(image);

    const stored = await stat(pathFor(coverDir, res.json().hash, 'full'));
    assert.ok(
      stored.size < image.length,
      `stored ${stored.size} should be smaller than the ${image.length}-byte original`,
    );
  });

  describe('validation is by decoding, not by what the upload claims', () => {
    test('a text file named .jpg with an image content-type is rejected', async () => {
      const res = await upload(Buffer.from('this is definitely not an image'), 'cover.jpg', 'image/jpeg');

      assert.equal(res.statusCode, 400);
      assert.match(res.json().error, /not a decodable image/);
    });

    test('an empty file is rejected', async () => {
      const res = await upload(Buffer.alloc(0));
      assert.equal(res.statusCode, 400);
    });

    test('a decompression bomb is rejected on pixel count, not byte size', async () => {
      // A huge single-colour PNG compresses to almost nothing and decodes to
      // gigabytes, so a byte-size limit alone does not catch it.
      const bomb = await sharp({
        create: { width: 12000, height: 12000, channels: 3, background: '#000000' },
      })
        .png({ compressionLevel: 9 })
        .toBuffer();

      const res = await upload(bomb, 'bomb.png', 'image/png');

      assert.equal(res.statusCode, 400);
      assert.match(res.json().error, /implausibly large/);
    });
  });

  test('a cover is served in both sizes with an immutable cache header', async () => {
    const image = await makeImage({ tint: '#993399' });
    const { hash } = (await upload(image)).json();

    for (const url of [`/v1/covers/${hash}`, `/v1/covers/${hash}/thumb`]) {
      const res = await app.inject({ method: 'GET', url, headers: auth });
      assert.equal(res.statusCode, 200, url);
      assert.equal(res.headers['content-type'], 'image/webp');
      // Content-addressed, therefore immutable, therefore cacheable forever.
      assert.match(res.headers['cache-control'], /immutable/);
    }
  });

  test('an unknown hash is a 404, and a malformed one a 400', async () => {
    const missing = await app.inject({ method: 'GET', url: `/v1/covers/${'a'.repeat(64)}`, headers: auth });
    assert.equal(missing.statusCode, 404);

    const malformed = await app.inject({ method: 'GET', url: '/v1/covers/not-a-hash', headers: auth });
    assert.equal(malformed.statusCode, 400);
  });

  test('cover routes reject an anonymous caller', async () => {
    assert.equal((await app.inject({ method: 'POST', url: '/v1/covers' })).statusCode, 401);
    assert.equal(
      (await app.inject({ method: 'GET', url: `/v1/covers/${'b'.repeat(64)}` })).statusCode,
      401,
    );
  });

  test('a book carries its cover hash through create and read', async () => {
    const image = await makeImage({ tint: '#123456' });
    const { hash } = (await upload(image)).json();

    const created = await app.inject({
      method: 'POST',
      url: '/v1/books',
      headers: auth,
      payload: { title: 'With cover', author: 'A', coverHash: hash },
    });

    assert.equal(created.statusCode, 201);
    assert.equal(created.json().coverHash, hash);
  });

  test('sync carries the cover hash and not the local file path', async () => {
    const image = await makeImage({ tint: '#654321' });
    const { hash } = (await upload(image)).json();

    await app.inject({
      method: 'POST',
      url: '/v1/books',
      headers: auth,
      payload: {
        title: 'Synced cover',
        author: 'A',
        coverHash: hash,
        coverImagePath: '/Users/someone/Pictures/local-only.jpg',
      },
    });

    const res = await app.inject({ method: 'GET', url: '/v1/sync', headers: auth });
    const book = res.json().changes.books.find((b) => b.title === 'Synced cover');

    assert.equal(book.coverHash, hash);
    // The local path is meaningless on another machine, so it must not travel.
    assert.equal(book.coverImagePath, undefined);
  });

  test('garbage collection removes only unreferenced covers', async () => {
    const orphan = (await upload(await makeImage({ tint: '#ff8800' }))).json().hash;
    const inUse = (await upload(await makeImage({ tint: '#0088ff' }))).json().hash;

    await app.inject({
      method: 'POST',
      url: '/v1/books',
      headers: auth,
      payload: { title: 'Holds a cover', author: 'A', coverHash: inUse },
    });

    const removed = await collectGarbage(pool, coverDir);
    assert.ok(removed > 0);

    const { rows: orphanRows } = await pool.query('SELECT 1 FROM covers WHERE hash = $1', [orphan]);
    assert.equal(orphanRows.length, 0, 'the unreferenced cover should be gone');

    const { rows: usedRows } = await pool.query('SELECT 1 FROM covers WHERE hash = $1', [inUse]);
    assert.equal(usedRows.length, 1, 'a referenced cover must survive');

    await assert.rejects(stat(pathFor(coverDir, orphan, 'full')), 'its file should be gone too');
    await stat(pathFor(coverDir, inUse, 'full'));
  });
});
