/**
 * Token issuing, rotation and reuse detection.
 *
 * Two kinds, on purpose:
 *
 * - **Access token** — a short-lived signed JWT, never stored. Verification is
 *   a signature check, so it costs no database round trip on every request.
 *   The trade is that it cannot be revoked before it expires, which is why the
 *   lifetime is minutes.
 * - **Refresh token** — 256 bits of CSPRNG output, stored as a SHA-256 digest.
 *   Long-lived, therefore revocable, therefore stateful.
 */
import { createHash, randomBytes, timingSafeEqual } from 'node:crypto';

export const ACCESS_TOKEN_TTL_SECONDS = 15 * 60;
export const REFRESH_TOKEN_TTL_DAYS = 30;

/**
 * The stored form of a refresh token.
 *
 * SHA-256, not Argon2id: the input is already 256 bits of randomness, so there
 * is no low-entropy guess for a slow hash to protect. Using Argon2id here would
 * add latency to every refresh and buy nothing.
 *
 * @param {string} token
 */
export function hashRefreshToken(token) {
  return createHash('sha256').update(token).digest('hex');
}

export function generateRefreshToken() {
  return randomBytes(32).toString('base64url');
}

/**
 * Compare two digests without leaking their difference through timing.
 *
 * @param {string} a
 * @param {string} b
 */
export function safeEqual(a, b) {
  const bufA = Buffer.from(a, 'utf8');
  const bufB = Buffer.from(b, 'utf8');
  // timingSafeEqual throws on a length mismatch, which would itself be a
  // signal — compare lengths first and always return rather than throw.
  if (bufA.length !== bufB.length) return false;
  return timingSafeEqual(bufA, bufB);
}

/**
 * Issue a refresh token and record its digest.
 *
 * @param {import('pg').Pool} pool
 * @param {number} userId
 * @returns {Promise<{ token: string, expiresAt: Date }>}
 */
export async function issueRefreshToken(pool, userId) {
  const token = generateRefreshToken();
  const expiresAt = new Date(Date.now() + REFRESH_TOKEN_TTL_DAYS * 24 * 60 * 60 * 1000);

  await pool.query(
    'INSERT INTO refresh_tokens (user_id, token_hash, expires_at) VALUES ($1, $2, $3)',
    [userId, hashRefreshToken(token), expiresAt],
  );

  return { token, expiresAt };
}

/**
 * Exchange a refresh token for a new pair, rotating it.
 *
 * Rotation is what makes theft detectable. Each token is single-use: presenting
 * one that has already been rotated away means either a replay or a stolen
 * copy, and since the two are indistinguishable from here, every token for that
 * user is revoked. The legitimate device is logged out too — an inconvenience
 * that beats leaving an attacker with a live session.
 *
 * @param {import('pg').Pool} pool
 * @param {string} presentedToken
 * @returns {Promise<{ ok: true, userId: number, token: string, expiresAt: Date }
 *                  | { ok: false, reason: 'invalid' | 'expired' | 'reused' }>}
 */
export async function rotateRefreshToken(pool, presentedToken) {
  const digest = hashRefreshToken(presentedToken);

  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    const { rows } = await client.query(
      `SELECT id, user_id, expires_at, revoked_at
         FROM refresh_tokens
        WHERE token_hash = $1
        FOR UPDATE`,
      [digest],
    );

    if (rows.length === 0) {
      await client.query('ROLLBACK');
      return { ok: false, reason: 'invalid' };
    }

    const row = rows[0];

    if (row.revoked_at !== null) {
      // Reuse of a rotated token. Assume compromise and cut every session.
      await client.query(
        'UPDATE refresh_tokens SET revoked_at = NOW() WHERE user_id = $1 AND revoked_at IS NULL',
        [row.user_id],
      );
      await client.query('COMMIT');
      return { ok: false, reason: 'reused' };
    }

    if (new Date(row.expires_at) <= new Date()) {
      await client.query('ROLLBACK');
      return { ok: false, reason: 'expired' };
    }

    await client.query('UPDATE refresh_tokens SET revoked_at = NOW() WHERE id = $1', [row.id]);

    const token = generateRefreshToken();
    const expiresAt = new Date(Date.now() + REFRESH_TOKEN_TTL_DAYS * 24 * 60 * 60 * 1000);
    await client.query(
      'INSERT INTO refresh_tokens (user_id, token_hash, expires_at) VALUES ($1, $2, $3)',
      [row.user_id, hashRefreshToken(token), expiresAt],
    );

    await client.query('COMMIT');
    return { ok: true, userId: row.user_id, token, expiresAt };
  } catch (err) {
    await client.query('ROLLBACK');
    throw err;
  } finally {
    client.release();
  }
}

/**
 * @param {import('pg').Pool} pool
 * @param {string} presentedToken
 */
export async function revokeRefreshToken(pool, presentedToken) {
  await pool.query(
    'UPDATE refresh_tokens SET revoked_at = NOW() WHERE token_hash = $1 AND revoked_at IS NULL',
    [hashRefreshToken(presentedToken)],
  );
}

/**
 * Drop rows that can no longer authenticate anything. Revoked tokens are kept
 * until they expire so that a replay is still detectable rather than merely
 * unrecognised.
 *
 * @param {import('pg').Pool} pool
 */
export async function pruneExpiredTokens(pool) {
  const { rowCount } = await pool.query('DELETE FROM refresh_tokens WHERE expires_at < NOW()');
  return rowCount;
}
