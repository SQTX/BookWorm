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
 * The successor of a revoked token, when its existence means the rotation was
 * lost rather than replayed.
 *
 * Returns null — meaning "treat this as reuse" — unless all three hold: the
 * revocation was recent, a successor was recorded, and that successor has never
 * been presented and has not expired. The middle condition also covers a logout,
 * which revokes without replacing and must stay final.
 *
 * @param {import('pg').PoolClient} client
 * @param {{ id: number, revoked_at: Date, replaced_by: number | null }} row
 */
async function liveSuccessor(client, row) {
  if (row.replaced_by === null) return null;

  const ageSeconds = (Date.now() - new Date(row.revoked_at).getTime()) / 1000;
  if (ageSeconds > REFRESH_REUSE_GRACE_SECONDS) return null;

  // Locked as well: two retries of the same lost reply arriving together must
  // not both recover, or the chain would fork and every later refresh would
  // look like a replay.
  const { rows } = await client.query(
    'SELECT id, revoked_at, expires_at FROM refresh_tokens WHERE id = $1 FOR UPDATE',
    [row.replaced_by],
  );

  const successor = rows[0];
  if (!successor) return null;
  if (successor.revoked_at !== null) return null;
  if (new Date(successor.expires_at) <= new Date()) return null;

  return successor;
}

/**
 * Revoke `predecessorId`, mint its replacement, and record the link between
 * them. The link is what later tells a lost reply from a replay.
 *
 * @param {import('pg').PoolClient} client
 * @param {number} predecessorId
 * @param {number} userId
 * @returns {Promise<{ token: string, expiresAt: Date }>}
 */
async function issueSuccessorTo(client, predecessorId, userId) {
  const token = generateRefreshToken();
  const expiresAt = new Date(Date.now() + REFRESH_TOKEN_TTL_DAYS * 24 * 60 * 60 * 1000);

  const { rows } = await client.query(
    'INSERT INTO refresh_tokens (user_id, token_hash, expires_at) VALUES ($1, $2, $3) RETURNING id',
    [userId, hashRefreshToken(token), expiresAt],
  );

  await client.query(
    'UPDATE refresh_tokens SET revoked_at = NOW(), replaced_by = $2 WHERE id = $1',
    [predecessorId, rows[0].id],
  );

  return { token, expiresAt };
}

/**
 * How long after a rotation the previous token may be presented again without
 * being read as theft.
 *
 * A rotation is only complete once the client has the new pair, and the new
 * pair travels in an HTTP response. When that response is lost — the process
 * was quitting on a deadline, the machine slept, the connection dropped — the
 * server has rotated and the client has not, so the next thing it presents is
 * the token the server just revoked. Without a window that is indistinguishable
 * from a replay, and the user is logged out of every device for a network
 * hiccup.
 *
 * Sixty seconds: long enough to cover a lost reply and a retry, short enough
 * that a token lifted from a machine is worth nothing by the time it is used.
 */
export const REFRESH_REUSE_GRACE_SECONDS = 60;

/**
 * Exchange a refresh token for a new pair, rotating it.
 *
 * Rotation is what makes theft detectable. Each token is single-use: presenting
 * one that has already been rotated away means either a replay or a stolen
 * copy, and every token for that user is revoked. The legitimate device is
 * logged out too — an inconvenience that beats leaving an attacker with a live
 * session.
 *
 * The one case that is *not* theft is a rotation whose reply never arrived, and
 * the successor link is what makes it visible. A revoked token whose successor
 * has itself been used means somebody is holding a token from further back in
 * the chain than the live client: a replay, and every session goes. A revoked
 * token whose successor has never been presented, revoked seconds ago, means
 * nobody ever received it — so the client retrying is the client that owns the
 * chain. It is given a fresh pair and the stillborn successor is revoked, which
 * keeps the chain single-use and allows exactly one recovery per lost reply.
 *
 * @param {import('pg').Pool} pool
 * @param {string} presentedToken
 * @returns {Promise<{ ok: true, userId: number, token: string, expiresAt: Date,
 *                     recovered: boolean }
 *                  | { ok: false, reason: 'invalid' | 'expired' | 'reused' }>}
 */
export async function rotateRefreshToken(pool, presentedToken) {
  const digest = hashRefreshToken(presentedToken);

  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    const { rows } = await client.query(
      `SELECT id, user_id, expires_at, revoked_at, replaced_by
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
      const successor = await liveSuccessor(client, row);

      if (successor === null) {
        // Either the successor has been used, or the window has closed, or
        // there is no successor at all (a logout). Assume compromise and cut
        // every session.
        await client.query(
          'UPDATE refresh_tokens SET revoked_at = NOW() WHERE user_id = $1 AND revoked_at IS NULL',
          [row.user_id],
        );
        await client.query('COMMIT');
        return { ok: false, reason: 'reused' };
      }

      // The rotation that produced `successor` never reached anyone. Retire it
      // — nothing is holding it — and continue the chain from there, so this
      // stays a single-use sequence and a second lost reply is recovered the
      // same way rather than accumulating live tokens.
      const replacement = await issueSuccessorTo(client, successor.id, row.user_id);
      await client.query('COMMIT');
      return { ok: true, userId: row.user_id, ...replacement, recovered: true };
    }

    if (new Date(row.expires_at) <= new Date()) {
      await client.query('ROLLBACK');
      return { ok: false, reason: 'expired' };
    }

    const issued = await issueSuccessorTo(client, row.id, row.user_id);

    await client.query('COMMIT');
    return { ok: true, userId: row.user_id, ...issued, recovered: false };
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
