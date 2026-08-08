import Fastify from 'fastify';

import { createPool } from './db.js';
import healthRoutes from './routes/health.js';

/**
 * The API is versioned in the URL and a released version never changes meaning
 * (D6). The monorepo keeps source in step; it does nothing about a phone in
 * someone's pocket running a three-month-old build, which is what this prefix
 * is for.
 */
export const API_PREFIX = '/v1';

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
  });

  const pool = overrides.pool ?? createPool(config);
  app.decorate('pg', pool);

  app.addHook('onClose', async () => {
    await pool.end();
  });

  await app.register(healthRoutes);

  // Client-facing routes land here from Phase 2 onward.
  await app.register(
    async (v1) => {
      v1.get('/', async () => ({ api: 'bookworm', version: 1 }));
    },
    { prefix: API_PREFIX },
  );

  return app;
}
