import { pullChanges, pushChanges, serverTime } from './repository.js';

const ISO_TIMESTAMP = { type: 'string', format: 'date-time' };

/**
 * Row schemas are intentionally loose on the fields and strict on identity:
 * every row must carry a `uuid` and an `updatedAt`, because those two are what
 * the merge is decided on. A row missing either cannot be placed in time or
 * matched to an existing one.
 */
const syncedRow = (properties) => ({
  type: 'array',
  maxItems: 1000,
  items: {
    type: 'object',
    required: ['uuid', 'updatedAt'],
    properties: {
      uuid: { type: 'string', format: 'uuid' },
      updatedAt: ISO_TIMESTAMP,
      deletedAt: { type: ['string', 'null'] },
      ...properties,
    },
  },
});

const PUSH_BODY = {
  type: 'object',
  additionalProperties: false,
  properties: {
    books: syncedRow({ tags: { type: 'array', items: { type: 'string' } } }),
    tags: syncedRow({ name: { type: 'string' } }),
    challenges: syncedRow({ name: { type: 'string' } }),
    favoriteQuotes: syncedRow({ bookUuid: { type: 'string', format: 'uuid' } }),
    highlights: syncedRow({ bookUuid: { type: 'string', format: 'uuid' } }),
    readingSessions: syncedRow({ bookUuid: { type: 'string', format: 'uuid' } }),
  },
};

/**
 * @param {import('fastify').FastifyInstance} app
 */
export default async function syncRoutes(app) {
  const ownerOf = (request) => Number(request.user.sub);

  app.get(
    '/sync',
    {
      schema: {
        querystring: {
          type: 'object',
          additionalProperties: false,
          properties: { since: ISO_TIMESTAMP },
        },
      },
    },
    async (request) => {
      // Read the clock before the query, never after: a row written while the
      // pull runs would otherwise fall between the two and be skipped forever,
      // since the next cursor is already past it.
      const now = await serverTime(app.pg);
      const changes = await pullChanges(app.pg, ownerOf(request), request.query.since);

      return { serverTime: now, changes };
    },
  );

  app.post(
    '/sync',
    { schema: { body: PUSH_BODY } },
    async (request) => {
      const userId = ownerOf(request);

      await pushChanges(app.pg, userId, request.body);

      // Push then pull in one exchange. The client's own writes come back as
      // the server's canonical version, so it settles on what actually landed
      // rather than assuming its version won — which matters precisely when
      // last-write-wins rejected it.
      const now = await serverTime(app.pg);
      const changes = await pullChanges(app.pg, userId, request.query?.since);

      return { serverTime: now, changes };
    },
  );
}
