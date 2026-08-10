import { MAX_UPLOAD_BYTES, read, store } from './storage.js';

const HASH_PARAM = {
  type: 'object',
  required: ['hash'],
  properties: { hash: { type: 'string', pattern: '^[0-9a-f]{64}$' } },
};

/**
 * @param {import('fastify').FastifyInstance} app
 */
export default async function coverRoutes(app) {
  app.post(
    '/covers',
    {
      config: {
        // Encoding is CPU-bound and this box has 2 vCPU. Unbounded concurrent
        // uploads would starve every other request; the limit is the cap.
        rateLimit: { max: 30, timeWindow: '1 minute' },
      },
    },
    async (request, reply) => {
      const file = await request.file({ limits: { fileSize: MAX_UPLOAD_BYTES } });

      if (!file) return reply.code(400).send({ error: 'No file uploaded' });

      const buffer = await file.toBuffer();

      // fastify-multipart truncates rather than throwing when the limit is hit,
      // so a silently half-received image would otherwise be stored as a valid
      // one. Check the flag, not just the bytes.
      if (file.file.truncated) {
        return reply.code(413).send({ error: 'File too large' });
      }

      const result = await store(app.pg, app.coverDir, buffer);

      if (!result.ok) {
        // The reason is safe to return: it describes the caller's own upload,
        // not anything about the server.
        return reply.code(400).send({ error: `Invalid image: ${result.reason}` });
      }

      return reply.code(201).send({ hash: result.hash, deduplicated: result.deduplicated });
    },
  );

  /**
   * Covers are served by content hash, which makes them immutable: a given hash
   * is always the same bytes. That is what allows an unconditional long cache,
   * and why the route needs no owner check — the hash is unguessable and
   * reveals nothing about who holds it.
   */
  const serve = (variant) => async (request, reply) => {
    const buffer = await read(app.coverDir, request.params.hash, variant);
    if (!buffer) return reply.code(404).send({ error: 'Not found' });

    return reply
      .header('content-type', 'image/webp')
      .header('cache-control', 'public, max-age=31536000, immutable')
      .send(buffer);
  };

  app.get('/covers/:hash', { schema: { params: HASH_PARAM } }, serve('full'));
  app.get('/covers/:hash/thumb', { schema: { params: HASH_PARAM } }, serve('thumb'));
}
