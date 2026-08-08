import * as repo from './repository.js';

const ID_PARAM = {
  type: 'object',
  required: ['id'],
  properties: { id: { type: 'integer', minimum: 1 } },
};

const BOOK_ID_PARAM = {
  type: 'object',
  required: ['bookId'],
  properties: { bookId: { type: 'integer', minimum: 1 } },
};

const COLOUR = { type: 'string', pattern: '^#[0-9A-Fa-f]{6,8}$' };

/**
 * @param {import('fastify').FastifyInstance} app
 */
export default async function collectionRoutes(app) {
  const ownerOf = (request) => Number(request.user.sub);

  /** Uniform 404 for "not yours" and "not there" — see the books routes. */
  const notFound = (reply) => reply.code(404).send({ error: 'Not found' });

  // ─── Tags ──────────────────────────────────────────────────────────────────

  app.get('/tags', async (request) => ({ tags: await repo.listTags(app.pg, ownerOf(request)) }));

  app.post(
    '/tags',
    {
      schema: {
        body: {
          type: 'object',
          required: ['name'],
          additionalProperties: false,
          properties: { name: { type: 'string', minLength: 1, maxLength: 128 }, color: COLOUR },
        },
      },
    },
    async (request, reply) => reply.code(201).send(await repo.createTag(app.pg, ownerOf(request), request.body)),
  );

  app.patch(
    '/tags/:id',
    {
      schema: {
        params: ID_PARAM,
        body: {
          type: 'object',
          minProperties: 1,
          additionalProperties: false,
          properties: { name: { type: 'string', minLength: 1, maxLength: 128 }, color: COLOUR },
        },
      },
    },
    async (request, reply) => {
      const tag = await repo.updateTag(app.pg, ownerOf(request), request.params.id, request.body);
      return tag ?? notFound(reply);
    },
  );

  app.delete('/tags/:id', { schema: { params: ID_PARAM } }, async (request, reply) => {
    const deleted = await repo.deleteTag(app.pg, ownerOf(request), request.params.id);
    return deleted ? reply.code(204).send() : notFound(reply);
  });

  // ─── Quotes ────────────────────────────────────────────────────────────────

  app.get('/books/:bookId/quotes', { schema: { params: BOOK_ID_PARAM } }, async (request) => ({
    quotes: await repo.listQuotes(app.pg, ownerOf(request), request.params.bookId),
  }));

  app.post(
    '/books/:bookId/quotes',
    {
      schema: {
        params: BOOK_ID_PARAM,
        body: {
          type: 'object',
          required: ['quote'],
          additionalProperties: false,
          properties: {
            quote: { type: 'string', minLength: 1, maxLength: 10000 },
            page: { type: ['integer', 'null'], minimum: 0, maximum: 100000 },
          },
        },
      },
    },
    async (request, reply) => {
      const quote = await repo.createQuote(app.pg, ownerOf(request), request.params.bookId, request.body);
      // Null means the book is not the caller's, or does not exist. The
      // ownership check lives in the INSERT ... SELECT, so there is no window
      // between checking and writing.
      return quote ? reply.code(201).send(quote) : notFound(reply);
    },
  );

  app.delete('/quotes/:id', { schema: { params: ID_PARAM } }, async (request, reply) => {
    const deleted = await repo.deleteQuote(app.pg, ownerOf(request), request.params.id);
    return deleted ? reply.code(204).send() : notFound(reply);
  });

  // ─── Highlights ────────────────────────────────────────────────────────────

  app.get('/books/:bookId/highlights', { schema: { params: BOOK_ID_PARAM } }, async (request) => ({
    highlights: await repo.listHighlights(app.pg, ownerOf(request), request.params.bookId),
  }));

  app.post(
    '/books/:bookId/highlights',
    {
      schema: {
        params: BOOK_ID_PARAM,
        body: {
          type: 'object',
          required: ['title'],
          additionalProperties: false,
          properties: {
            title: { type: 'string', minLength: 1, maxLength: 256 },
            page: { type: ['integer', 'null'], minimum: 0, maximum: 100000 },
            note: { type: ['string', 'null'], maxLength: 10000 },
          },
        },
      },
    },
    async (request, reply) => {
      const highlight = await repo.createHighlight(app.pg, ownerOf(request), request.params.bookId, request.body);
      return highlight ? reply.code(201).send(highlight) : notFound(reply);
    },
  );

  app.delete('/highlights/:id', { schema: { params: ID_PARAM } }, async (request, reply) => {
    const deleted = await repo.deleteHighlight(app.pg, ownerOf(request), request.params.id);
    return deleted ? reply.code(204).send() : notFound(reply);
  });

  // ─── Challenges ────────────────────────────────────────────────────────────

  const CHALLENGE_FIELDS = {
    name: { type: 'string', minLength: 1, maxLength: 256 },
    deadline: { type: 'string', pattern: '^\\d{4}-\\d{2}-\\d{2}$' },
    metric: { type: 'string', enum: ['books', 'pages', 'pages_per_day'] },
    targetValue: { type: 'integer', minimum: 1, maximum: 1000000 },
    periodUnit: { type: 'string', enum: ['day', 'month', 'year', 'custom'] },
    periodCount: { type: 'integer', minimum: 0, maximum: 1000 },
  };

  app.get('/challenges', async (request) => ({
    challenges: await repo.listChallenges(app.pg, ownerOf(request)),
  }));

  app.post(
    '/challenges',
    {
      schema: {
        body: {
          type: 'object',
          required: ['name', 'deadline'],
          additionalProperties: false,
          properties: CHALLENGE_FIELDS,
        },
      },
    },
    async (request, reply) =>
      reply.code(201).send(await repo.createChallenge(app.pg, ownerOf(request), request.body)),
  );

  app.patch(
    '/challenges/:id',
    {
      schema: {
        params: ID_PARAM,
        body: {
          type: 'object',
          minProperties: 1,
          additionalProperties: false,
          properties: CHALLENGE_FIELDS,
        },
      },
    },
    async (request, reply) => {
      const challenge = await repo.updateChallenge(app.pg, ownerOf(request), request.params.id, request.body);
      return challenge ?? notFound(reply);
    },
  );

  app.delete('/challenges/:id', { schema: { params: ID_PARAM } }, async (request, reply) => {
    const deleted = await repo.deleteChallenge(app.pg, ownerOf(request), request.params.id);
    return deleted ? reply.code(204).send() : notFound(reply);
  });
}
