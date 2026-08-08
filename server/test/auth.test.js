/**
 * Auth tests against a real PostgreSQL.
 *
 * Rotation and reuse detection are SQL — a transaction, a FOR UPDATE lock and a
 * bulk revoke. A stubbed pool would assert that the code calls the queries it
 * calls, which is not the same as asserting the behaviour is right.
 *
 * Skipped when TEST_DATABASE_URL is unset, so `npm test` still works on a
 * machine with no database. CI always sets it.
 */
import assert from 'node:assert/strict';
import { after, before, describe, test } from 'node:test';

import pg from 'pg';

import { buildApp } from '../src/app.js';
import { loadConfig } from '../src/config.js';
import { hashRefreshToken, pruneExpiredTokens, rotateRefreshToken } from '../src/auth/tokens.js';

const DATABASE_URL = process.env.TEST_DATABASE_URL;

const EMAIL = 'auth-test@example.test';
const PASSWORD = 'a-sufficiently-long-test-password';

describe('auth', { skip: DATABASE_URL ? false : 'TEST_DATABASE_URL not set' }, () => {
  /** @type {import('pg').Pool} */
  let pool;
  /** @type {import('fastify').FastifyInstance} */
  let app;

  before(async () => {
    pool = new pg.Pool({ connectionString: DATABASE_URL });

    // @node-rs/argon2 is imported here rather than at module scope so the file
    // parses on a machine that skips this suite.
    const { hash, Algorithm } = await import('@node-rs/argon2');
    const passwordHash = await hash(PASSWORD, { algorithm: Algorithm.Argon2id });

    await pool.query('DELETE FROM users WHERE email = $1', [EMAIL]);
    await pool.query('INSERT INTO users (email, password_hash) VALUES ($1, $2)', [
      EMAIL,
      passwordHash,
    ]);

    app = await buildApp(
      loadConfig({
        DATABASE_URL,
        JWT_SECRET: 'test-secret-long-enough-to-pass-the-length-check',
        NODE_ENV: 'test',
        LOG_LEVEL: 'silent',
      }),
      { pool },
    );
  });

  after(async () => {
    // The pool is ours, not the app's: buildApp only closes a pool it created,
    // so it survives app.close() here and in the second app instance below.
    await app.close();
    await pool.query('DELETE FROM users WHERE email = $1', [EMAIL]);
    await pool.end();
  });

  // Login is rate-limited per client address (5/minute). Tests would otherwise
  // share one bucket and start failing each other in a confusing way: a
  // throttled login returns no refreshToken, so the NEXT request fails schema
  // validation with a 400 that says nothing about the real cause. Giving each
  // call its own address isolates them; the limit itself is tested explicitly
  // below rather than switched off.
  let addressCounter = 0;
  const login = (password = PASSWORD, email = EMAIL, remoteAddress = null) =>
    app.inject({
      method: 'POST',
      url: '/v1/auth/login',
      payload: { email, password },
      remoteAddress: remoteAddress ?? `10.0.0.${++addressCounter % 250}`,
    });

  test('login returns a usable token pair', async () => {
    const res = await login();

    assert.equal(res.statusCode, 200);
    const body = res.json();
    assert.ok(body.accessToken);
    assert.ok(body.refreshToken);
    assert.equal(body.expiresIn, 900);

    const me = await app.inject({
      method: 'GET',
      url: '/v1/',
      headers: { authorization: `Bearer ${body.accessToken}` },
    });
    assert.equal(me.statusCode, 200);
  });

  test('a wrong password and an unknown email are indistinguishable', async () => {
    const wrongPassword = await login('not-the-password');
    const unknownEmail = await login(PASSWORD, 'nobody@example.test');

    assert.equal(wrongPassword.statusCode, 401);
    assert.equal(unknownEmail.statusCode, 401);
    // Identical bodies: a different message would tell an attacker which half
    // of the credentials was right.
    assert.deepEqual(wrongPassword.json(), unknownEmail.json());
  });

  test('email matching is case-insensitive', async () => {
    const res = await login(PASSWORD, EMAIL.toUpperCase());
    assert.equal(res.statusCode, 200);
  });

  test('the refresh token is never stored in the clear', async () => {
    const { refreshToken } = (await login()).json();

    const { rows } = await pool.query('SELECT token_hash FROM refresh_tokens WHERE token_hash = $1', [
      hashRefreshToken(refreshToken),
    ]);
    assert.equal(rows.length, 1, 'digest should be stored');

    const { rows: plaintext } = await pool.query(
      'SELECT 1 FROM refresh_tokens WHERE token_hash = $1',
      [refreshToken],
    );
    assert.equal(plaintext.length, 0, 'the token itself must not appear in the table');
  });

  test('refresh rotates: the old token stops working', async () => {
    const first = (await login()).json();

    const refreshed = await app.inject({
      method: 'POST',
      url: '/v1/auth/refresh',
      payload: { refreshToken: first.refreshToken },
    });
    assert.equal(refreshed.statusCode, 200);
    const second = refreshed.json();
    assert.notEqual(second.refreshToken, first.refreshToken);

    const replay = await app.inject({
      method: 'POST',
      url: '/v1/auth/refresh',
      payload: { refreshToken: first.refreshToken },
    });
    assert.equal(replay.statusCode, 401);
  });

  test('replaying a rotated token revokes every session for that user', async () => {
    const a = (await login()).json();
    const b = (await login()).json();

    // Rotate a, then replay it. b belongs to a different device and was never
    // touched — it must still die, because from here a replay is
    // indistinguishable from theft.
    await app.inject({ method: 'POST', url: '/v1/auth/refresh', payload: { refreshToken: a.refreshToken } });
    await app.inject({ method: 'POST', url: '/v1/auth/refresh', payload: { refreshToken: a.refreshToken } });

    const other = await app.inject({
      method: 'POST',
      url: '/v1/auth/refresh',
      payload: { refreshToken: b.refreshToken },
    });
    assert.equal(other.statusCode, 401, 'the untouched session must also be revoked');
  });

  test('logout revokes, and repeats stay 204 so tokens cannot be probed', async () => {
    const { refreshToken } = (await login()).json();

    const first = await app.inject({ method: 'POST', url: '/v1/auth/logout', payload: { refreshToken } });
    assert.equal(first.statusCode, 204);

    const again = await app.inject({ method: 'POST', url: '/v1/auth/logout', payload: { refreshToken } });
    assert.equal(again.statusCode, 204);

    const refresh = await app.inject({ method: 'POST', url: '/v1/auth/refresh', payload: { refreshToken } });
    assert.equal(refresh.statusCode, 401);
  });

  test('an expired refresh token is rejected', async () => {
    const { refreshToken } = (await login()).json();

    await pool.query("UPDATE refresh_tokens SET expires_at = NOW() - INTERVAL '1 day' WHERE token_hash = $1", [
      hashRefreshToken(refreshToken),
    ]);

    const result = await rotateRefreshToken(pool, refreshToken);
    assert.deepEqual(result, { ok: false, reason: 'expired' });
  });

  test('an unknown refresh token is rejected without touching anything', async () => {
    const result = await rotateRefreshToken(pool, 'not-a-real-token');
    assert.deepEqual(result, { ok: false, reason: 'invalid' });
  });

  test('pruning removes expired tokens but keeps revoked-and-live ones', async () => {
    const { refreshToken } = (await login()).json();
    const digest = hashRefreshToken(refreshToken);

    // Revoked but not yet expired: kept, so a replay is still *detected*
    // rather than merely unrecognised.
    await pool.query('UPDATE refresh_tokens SET revoked_at = NOW() WHERE token_hash = $1', [digest]);
    await pruneExpiredTokens(pool);

    const { rows } = await pool.query('SELECT 1 FROM refresh_tokens WHERE token_hash = $1', [digest]);
    assert.equal(rows.length, 1);

    await pool.query("UPDATE refresh_tokens SET expires_at = NOW() - INTERVAL '1 day' WHERE token_hash = $1", [
      digest,
    ]);
    await pruneExpiredTokens(pool);

    const { rows: after } = await pool.query('SELECT 1 FROM refresh_tokens WHERE token_hash = $1', [digest]);
    assert.equal(after.length, 0);
  });

  test('login is rate-limited per address', async () => {
    const address = '198.51.100.7';

    // The limit is 5 per minute. Wrong passwords count, which is the point:
    // one account means exactly one password to guess.
    const codes = [];
    for (let i = 0; i < 7; i++) {
      const res = await login('wrong-password', EMAIL, address);
      codes.push(res.statusCode);
    }

    assert.deepEqual(codes.slice(0, 5), [401, 401, 401, 401, 401]);
    assert.deepEqual(codes.slice(5), [429, 429], 'attempts beyond the limit must be throttled');

    // A different address is unaffected — the limit is per client, not global,
    // so one attacker cannot lock the real user out.
    const elsewhere = await login(PASSWORD, EMAIL, '198.51.100.8');
    assert.equal(elsewhere.statusCode, 200);
  });

  test('a token signed with a different secret is rejected', async () => {
    const otherApp = await buildApp(
      loadConfig({
        DATABASE_URL,
        JWT_SECRET: 'a-completely-different-secret-of-sufficient-length',
        NODE_ENV: 'test',
        LOG_LEVEL: 'silent',
      }),
      { pool },
    );
    const foreign = otherApp.jwt.sign({ sub: 1 });
    await otherApp.close();

    const res = await app.inject({
      method: 'GET',
      url: '/v1/',
      headers: { authorization: `Bearer ${foreign}` },
    });
    assert.equal(res.statusCode, 401);
  });
});
