import { verify } from '@node-rs/argon2';

import {
  ACCESS_TOKEN_TTL_SECONDS,
  issueRefreshToken,
  revokeRefreshToken,
  rotateRefreshToken,
} from './tokens.js';

const CREDENTIALS_SCHEMA = {
  type: 'object',
  required: ['email', 'password'],
  additionalProperties: false,
  properties: {
    email: { type: 'string', minLength: 3, maxLength: 320 },
    password: { type: 'string', minLength: 1, maxLength: 1024 },
  },
};

const TOKEN_PAIR_SCHEMA = {
  type: 'object',
  required: ['accessToken', 'refreshToken', 'expiresIn'],
  properties: {
    accessToken: { type: 'string' },
    refreshToken: { type: 'string' },
    expiresIn: { type: 'integer' },
  },
};

/**
 * A password hash to verify against when the email does not exist.
 *
 * Without it, a request for an unknown email returns in microseconds while a
 * known one takes the ~100ms Argon2id costs — which tells an attacker which
 * emails are real. Verifying against a fixed hash makes both paths do the same
 * work. Generated once at module load with a value nothing can match.
 */
const DUMMY_HASH =
  '$argon2id$v=19$m=19456,t=2,p=1$c29tZXNhbHRzb21lc2FsdA$' +
  'YXJiaXRyYXJ5LWRpZ2VzdC1uZXZlci1tYXRjaGVzLWFueXRoaW5n';

/**
 * @param {import('fastify').FastifyInstance} app
 */
export default async function authRoutes(app) {
  app.post(
    '/auth/login',
    {
      config: {
        // One account means exactly one password to guess, which makes the
        // limit more useful here, not less.
        rateLimit: { max: 5, timeWindow: '1 minute' },
      },
      schema: {
        body: CREDENTIALS_SCHEMA,
        response: { 200: TOKEN_PAIR_SCHEMA },
      },
    },
    async (request, reply) => {
      const { email, password } = request.body;

      const { rows } = await app.pg.query(
        'SELECT id, password_hash FROM users WHERE email = $1',
        [email],
      );

      const user = rows[0];

      // Always verify something, so an unknown email costs the same as a wrong
      // password.
      const ok = await verify(user?.password_hash ?? DUMMY_HASH, password).catch(() => false);

      if (!user || !ok) {
        // One message for both cases. Saying "no such account" would confirm
        // which half was right.
        request.log.warn({ email }, 'failed login');
        return reply.code(401).send({ error: 'Invalid credentials' });
      }

      const accessToken = app.jwt.sign({ sub: user.id }, { expiresIn: ACCESS_TOKEN_TTL_SECONDS });
      const { token: refreshToken } = await issueRefreshToken(app.pg, user.id);

      return { accessToken, refreshToken, expiresIn: ACCESS_TOKEN_TTL_SECONDS };
    },
  );

  app.post(
    '/auth/refresh',
    {
      config: { rateLimit: { max: 20, timeWindow: '1 minute' } },
      schema: {
        body: {
          type: 'object',
          required: ['refreshToken'],
          additionalProperties: false,
          properties: { refreshToken: { type: 'string', minLength: 1, maxLength: 512 } },
        },
        response: { 200: TOKEN_PAIR_SCHEMA },
      },
    },
    async (request, reply) => {
      const result = await rotateRefreshToken(app.pg, request.body.refreshToken);

      if (!result.ok) {
        if (result.reason === 'reused') {
          // Every session for that user has just been cut. Worth a loud line:
          // it means a token was used twice, which should not happen.
          request.log.error('refresh token reuse detected — all sessions revoked');
        }
        return reply.code(401).send({ error: 'Invalid refresh token' });
      }

      const accessToken = app.jwt.sign(
        { sub: result.userId },
        { expiresIn: ACCESS_TOKEN_TTL_SECONDS },
      );

      return {
        accessToken,
        refreshToken: result.token,
        expiresIn: ACCESS_TOKEN_TTL_SECONDS,
      };
    },
  );

  app.post(
    '/auth/logout',
    {
      schema: {
        body: {
          type: 'object',
          required: ['refreshToken'],
          additionalProperties: false,
          properties: { refreshToken: { type: 'string', minLength: 1, maxLength: 512 } },
        },
        response: {
          204: { type: 'null' },
        },
      },
    },
    async (request, reply) => {
      await revokeRefreshToken(app.pg, request.body.refreshToken);
      // 204 whether or not the token existed: a different answer would let
      // someone probe which tokens are live.
      return reply.code(204).send();
    },
  );
}
