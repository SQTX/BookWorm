import fastifyJwt from '@fastify/jwt';
import fastifyRateLimit from '@fastify/rate-limit';
import Fastify from 'fastify';

import authRoutes from './auth/routes.js';
import bookRoutes from './books/routes.js';
import collectionRoutes from './collections/routes.js';
import syncRoutes from './sync/routes.js';
import { createPool } from './db.js';
import healthRoutes from './routes/health.js';

/**
 * The API is versioned in the URL and a released version never changes meaning
 * (D6). The monorepo keeps source in step; it does nothing about a phone in
 * someone's pocket running a three-month-old build, which is what this prefix
 * is for.
 */
export const API_PREFIX = '/v1';

/** Routes under /v1 that must stay reachable without a token. */
const PUBLIC_ROUTES = new Set([
  `${API_PREFIX}/auth/login`,
  `${API_PREFIX}/auth/refresh`,
  `${API_PREFIX}/auth/logout`,
]);

/**
 * Builds the Fastify instance without starting it, so tests can drive it
 * through `app.inject()` and never bind a port.
 *
 * @param {ReturnType<typeof import('./config.js').loadConfig>} config
 * @param {{ pool?: import('pg').Pool }} [overrides] injection point for tests
 */
export async function buildApp(config, overrides = {}) {
  const app = Fastify({
    logger: {
      level: config.logLevel,
      // Do not log the query string: it is the easiest place for a token or an
      // email to end up in plain text on disk.
      serializers: {
        req: (req) => ({ method: req.method, url: req.url.split('?')[0] }),
      },
    },
    // Fastify's default is 1 MB. Cover uploads get their own, larger limit on
    // their own route in Phase 2 — the global default stays small.
    bodyLimit: 1024 * 1024,
    // Trust the reverse proxy's forwarding headers for client IPs, which rate
    // limiting depends on. Only correct because Node sits behind a proxy.
    trustProxy: true,
    ajv: {
      customOptions: {
        // Fastify defaults to removeAdditional: true, which strips unknown
        // properties silently — so `additionalProperties: false` documents an
        // intent it does not enforce. For a sync client that is the worst
        // outcome available: a mistyped field name looks like a successful
        // write and the value is simply gone. Reject instead.
        removeAdditional: false,
      },
    },
  });

  // Ownership follows creation: the app closes the pool only when it made it.
  // An injected pool belongs to the caller, who may share it across several app
  // instances — closing it here would pull it out from under them.
  const ownsPool = overrides.pool === undefined;
  const pool = overrides.pool ?? createPool(config);
  app.decorate('pg', pool);

  if (ownsPool) {
    app.addHook('onClose', async () => {
      await pool.end();
    });
  }

  await app.register(fastifyJwt, { secret: config.jwtSecret });
  await app.register(fastifyRateLimit, {
    global: false,
    // statusCode is required here. Without it the plugin cannot build a proper
    // error and the client gets a 500 — which reads as a server fault and
    // invites an aggressive retry, the opposite of what throttling wants.
    // The body stays terse: the default reports the configured limit, which is
    // information an attacker can use to pace themselves under it.
    errorResponseBuilder: () => ({
      statusCode: 429,
      error: 'Too Many Requests',
      message: 'Too many requests',
    }),
  });

  await app.register(healthRoutes);

  await app.register(
    async (v1) => {
      // Authentication is enforced for the whole prefix rather than per route,
      // so an endpoint added later is protected by default. Opting out has to
      // be a deliberate edit to PUBLIC_ROUTES, which is visible in review — the
      // opposite of remembering to add a guard to each new handler.
      v1.addHook('onRequest', async (request, reply) => {
        if (PUBLIC_ROUTES.has(request.routeOptions?.url ?? request.url)) return;

        try {
          await request.jwtVerify();
        } catch {
          return reply.code(401).send({ error: 'Unauthorized' });
        }
      });

      await v1.register(authRoutes);
      await v1.register(bookRoutes);
      await v1.register(collectionRoutes);
      await v1.register(syncRoutes);

      v1.get('/', async (request) => ({
        api: 'bookworm',
        version: 1,
        userId: request.user.sub,
      }));
    },
    { prefix: API_PREFIX },
  );

  return app;
}
