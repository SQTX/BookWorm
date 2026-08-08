/**
 * Field names match `Book::toVariantMap()` in the desktop app exactly, so
 * Phase 4 is a direct mapping rather than a translation layer. Renaming
 * anything here means editing C++ too.
 */

export const STATUSES = ['reading', 'read', 'planned', 'abandoned'];
export const AUDIO_MODES = ['none', 'audiobook', 'audiobook_support'];

/** API camelCase → database snake_case. The only place the two vocabularies meet. */
export const COLUMN_OF = {
  title: 'title',
  author: 'author',
  genre: 'genre',
  pageCount: 'page_count',
  startDate: 'start_date',
  endDate: 'end_date',
  rating: 'rating',
  status: 'status',
  notes: 'notes',
  isbn: 'isbn',
  publisher: 'publisher',
  publicationYear: 'publication_year',
  publicationDate: 'publication_date',
  language: 'language',
  coverImagePath: 'cover_image_path',
  itemType: 'item_type',
  isNonFiction: 'is_non_fiction',
  isPriority: 'is_priority',
  audioMode: 'audio_mode',
  currentPage: 'current_page',
  series: 'series',
  summary: 'summary',
  review: 'review',
};

/** Server-owned. A client sending these is confused, not authoritative. */
export const READ_ONLY_FIELDS = ['id', 'readCount', 'createdAt', 'updatedAt'];

const nullableString = (maxLength) => ({
  type: ['string', 'null'],
  maxLength,
});

/** `''` is what the desktop sends for an unset date; treat it as null. */
const nullableDate = {
  type: ['string', 'null'],
  pattern: '^(\\d{4}-\\d{2}-\\d{2})?$',
};

export const BOOK_INPUT_PROPERTIES = {
  title: { type: 'string', minLength: 1, maxLength: 512 },
  author: { type: 'string', minLength: 1, maxLength: 512 },
  genre: nullableString(128),
  pageCount: { type: 'integer', minimum: 0, maximum: 100000 },
  startDate: nullableDate,
  endDate: nullableDate,
  // 0 means unrated. The column's CHECK allows 1-6 or NULL, so 0 is mapped to
  // NULL on the way in rather than rejected — the desktop sends 0 freely.
  rating: { type: ['integer', 'null'], minimum: 0, maximum: 6 },
  status: { type: 'string', enum: STATUSES },
  notes: nullableString(100000),
  isbn: nullableString(20),
  publisher: nullableString(256),
  publicationYear: { type: ['integer', 'null'], minimum: 0, maximum: 3000 },
  publicationDate: nullableDate,
  language: nullableString(64),
  coverImagePath: nullableString(1024),
  itemType: nullableString(32),
  isNonFiction: { type: 'boolean' },
  isPriority: { type: 'boolean' },
  audioMode: { type: 'string', enum: AUDIO_MODES },
  currentPage: { type: 'integer', minimum: 0, maximum: 100000 },
  series: nullableString(256),
  summary: nullableString(100000),
  review: nullableString(100000),
  tags: {
    type: 'array',
    maxItems: 64,
    items: { type: 'string', minLength: 1, maxLength: 128 },
  },
};

export const CREATE_BOOK_SCHEMA = {
  type: 'object',
  required: ['title', 'author'],
  // Rejecting unknown fields is what turns a client-side typo into a 400 at the
  // edge instead of a value that silently never persists.
  additionalProperties: false,
  properties: BOOK_INPUT_PROPERTIES,
};

export const UPDATE_BOOK_SCHEMA = {
  type: 'object',
  minProperties: 1,
  additionalProperties: false,
  properties: BOOK_INPUT_PROPERTIES,
};

export const BOOK_SCHEMA = {
  type: 'object',
  properties: {
    id: { type: 'integer' },
    title: { type: 'string' },
    author: { type: 'string' },
    genre: { type: ['string', 'null'] },
    pageCount: { type: ['integer', 'null'] },
    startDate: { type: ['string', 'null'] },
    endDate: { type: ['string', 'null'] },
    rating: { type: ['integer', 'null'] },
    status: { type: 'string' },
    notes: { type: ['string', 'null'] },
    isbn: { type: ['string', 'null'] },
    publisher: { type: ['string', 'null'] },
    publicationYear: { type: ['integer', 'null'] },
    publicationDate: { type: ['string', 'null'] },
    language: { type: ['string', 'null'] },
    coverImagePath: { type: ['string', 'null'] },
    itemType: { type: ['string', 'null'] },
    isNonFiction: { type: ['boolean', 'null'] },
    isPriority: { type: ['boolean', 'null'] },
    audioMode: { type: ['string', 'null'] },
    currentPage: { type: ['integer', 'null'] },
    series: { type: ['string', 'null'] },
    summary: { type: ['string', 'null'] },
    review: { type: ['string', 'null'] },
    readCount: { type: 'integer' },
    tags: { type: 'array', items: { type: 'string' } },
    updatedAt: { type: 'string' },
  },
};
