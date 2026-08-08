import { pingDatabase } from '../db.js';

/**
 * Operational endpoints. Deliberately unversioned — /health is for monitoring,
 * not part of the client-facing API contract, so it is not under /v1.
 *
 * The response says whether the service is usable and nothing else. No version
 * strings, no hostnames, no database details: this endpoint is reachable by
 * whatever can reach the proxy.
 *
 * @param {import('fastify').FastifyInstance} app
 */
export default async function healthRoutes(app) {
  app.get(
    '/health',
    {
      schema: {
        response: {
          200: {
            type: 'object',
            properties: { status: { type: 'string' } },
            required: ['status'],
          },
          503: {
            type: 'object',
            properties: { status: { type: 'string' } },
            required: ['status'],
          },
        },
      },
    },
    async (_request, reply) => {
      const databaseUp = await pingDatabase(app.pg);

      if (!databaseUp) {
        // 503 rather than 200-with-a-flag, so a load balancer or uptime check
        // reacts without having to parse the body.
        return reply.code(503).send({ status: 'degraded' });
      }

      return { status: 'ok' };
    },
  );
}
