import {
  completeBook,
  createBook,
  deleteBook,
  getBook,
  listBooks,
  recordProgress,
  updateBook,
} from './repository.js';
import { BOOK_SCHEMA, CREATE_BOOK_SCHEMA, STATUSES, UPDATE_BOOK_SCHEMA } from './schemas.js';

const ID_PARAM = {
  type: 'object',
  required: ['id'],
  properties: { id: { type: 'integer', minimum: 1 } },
};

/**
 * @param {import('fastify').FastifyInstance} app
 */
export default async function bookRoutes(app) {
  /** The authenticated owner. Every query below is scoped to it. */
  const ownerOf = (request) => Number(request.user.sub);

  app.get(
    '/books',
    {
      schema: {
        querystring: {
          type: 'object',
          additionalProperties: false,
          properties: { status: { type: 'string', enum: STATUSES } },
        },
        response: {
          200: { type: 'object', properties: { books: { type: 'array', items: BOOK_SCHEMA } } },
        },
      },
    },
    async (request) => ({
      books: await listBooks(app.pg, ownerOf(request), { status: request.query.status }),
    }),
  );

  app.get(
    '/books/:id',
    { schema: { params: ID_PARAM, response: { 200: BOOK_SCHEMA } } },
    async (request, reply) => {
      const book = await getBook(app.pg, ownerOf(request), request.params.id);
      // 404, not 403, for a book owned by someone else: distinguishing them
      // would confirm that a given id exists.
      if (!book) return reply.code(404).send({ error: 'Not found' });
      return book;
    },
  );

  app.post(
    '/books',
    { schema: { body: CREATE_BOOK_SCHEMA, response: { 201: BOOK_SCHEMA } } },
    async (request, reply) => {
      const book = await createBook(app.pg, ownerOf(request), request.body);
      return reply.code(201).send(book);
    },
  );

  app.patch(
    '/books/:id',
    { schema: { params: ID_PARAM, body: UPDATE_BOOK_SCHEMA, response: { 200: BOOK_SCHEMA } } },
    async (request, reply) => {
      const book = await updateBook(app.pg, ownerOf(request), request.params.id, request.body);
      if (!book) return reply.code(404).send({ error: 'Not found' });
      return book;
    },
  );

  app.delete(
    '/books/:id',
    { schema: { params: ID_PARAM, response: { 204: { type: 'null' } } } },
    async (request, reply) => {
      const deleted = await deleteBook(app.pg, ownerOf(request), request.params.id);
      if (!deleted) return reply.code(404).send({ error: 'Not found' });
      return reply.code(204).send();
    },
  );

  /**
   * Progress is its own endpoint rather than a PATCH field, deliberately.
   *
   * Moving the page and recording the reading session must happen together, or
   * the statistics drift away from the library. Exposing `currentPage` as an
   * ordinary editable field would give every client a way to move progress
   * without logging it — the invariant the desktop enforces in C++ has to be
   * enforced here instead, because the clients are no longer trusted with it.
   */
  app.post(
    '/books/:id/progress',
    {
      schema: {
        params: ID_PARAM,
        body: {
          type: 'object',
          required: ['currentPage'],
          additionalProperties: false,
          properties: { currentPage: { type: 'integer', minimum: 0, maximum: 100000 } },
        },
        response: {
          200: {
            type: 'object',
            properties: { book: BOOK_SCHEMA, pagesRead: { type: 'integer' } },
          },
        },
      },
    },
    async (request, reply) => {
      const result = await recordProgress(
        app.pg,
        ownerOf(request),
        request.params.id,
        request.body.currentPage,
      );
      if (!result) return reply.code(404).send({ error: 'Not found' });
      return result;
    },
  );

  app.post(
    '/books/:id/complete',
    {
      schema: {
        params: ID_PARAM,
        body: {
          type: 'object',
          additionalProperties: false,
          properties: {
            rating: { type: ['integer', 'null'], minimum: 0, maximum: 6 },
            review: { type: ['string', 'null'], maxLength: 100000 },
          },
        },
        response: { 200: BOOK_SCHEMA },
      },
    },
    async (request, reply) => {
      const book = await completeBook(app.pg, ownerOf(request), request.params.id, request.body);
      if (!book) return reply.code(404).send({ error: 'Not found' });
      return book;
    },
  );
}
