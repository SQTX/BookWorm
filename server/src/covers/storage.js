/**
 * Cover storage: validate, re-encode, deduplicate, serve.
 *
 * Covers are ~98% of this application's storage volume, so the two decisions
 * that matter are made here rather than deferred: every upload is re-encoded to
 * the size the UI actually renders, and identical bytes are stored once.
 */
import { createHash } from 'node:crypto';
import { mkdir, readFile, rm, writeFile } from 'node:fs/promises';
import { dirname, join } from 'node:path';

import sharp from 'sharp';

/** The grid card renders 180×300; the detail view is larger but not by much. */
export const FULL_WIDTH = 400;
export const FULL_HEIGHT = 600;
export const THUMB_WIDTH = 120;
export const THUMB_HEIGHT = 180;

/** Refuse anything implausible as a book cover before decoding it. */
export const MAX_UPLOAD_BYTES = 10 * 1024 * 1024;

/** Decoded dimensions beyond this are a decompression bomb, not a cover. */
const MAX_PIXELS = 50_000_000;

/**
 * Two levels of fan-out from the hash.
 *
 * A single flat directory with tens of thousands of files is slow to list and
 * unpleasant to work with on most filesystems. `ab/cd/abcd…` keeps any one
 * directory small without needing a database to find a file.
 *
 * @param {string} hash
 * @param {'full' | 'thumb'} variant
 */
export function pathFor(baseDir, hash, variant) {
  return join(baseDir, hash.slice(0, 2), hash.slice(2, 4), `${hash}.${variant}.webp`);
}

export function hashBytes(buffer) {
  return createHash('sha256').update(buffer).digest('hex');
}

/**
 * Decode the upload to find out what it really is.
 *
 * Validation is by decoding, never by file extension or the declared
 * Content-Type: both are attacker-controlled strings. If sharp cannot read it,
 * it is not an image, whatever it claims to be.
 *
 * @param {Buffer} buffer
 * @returns {Promise<{ ok: true, width: number, height: number, format: string }
 *                  | { ok: false, reason: string }>}
 */
export async function inspect(buffer) {
  if (buffer.length === 0) return { ok: false, reason: 'empty file' };
  if (buffer.length > MAX_UPLOAD_BYTES) {
    return { ok: false, reason: `larger than ${MAX_UPLOAD_BYTES} bytes` };
  }

  let metadata;
  try {
    metadata = await sharp(buffer).metadata();
  } catch {
    return { ok: false, reason: 'not a decodable image' };
  }

  if (!metadata.width || !metadata.height) {
    return { ok: false, reason: 'no readable dimensions' };
  }

  // A 30000×30000 PNG is a few hundred kilobytes compressed and several
  // gigabytes decoded. The byte-size limit alone does not catch it.
  if (metadata.width * metadata.height > MAX_PIXELS) {
    return { ok: false, reason: 'implausibly large image' };
  }

  return { ok: true, width: metadata.width, height: metadata.height, format: metadata.format };
}

/**
 * Re-encode to the two sizes the UI uses.
 *
 * `fit: 'inside'` rather than `'cover'`: book covers are not a uniform aspect
 * ratio, and cropping to fit would quietly cut the title off a tall paperback.
 * The UI already letterboxes.
 *
 * @param {Buffer} buffer
 */
export async function encodeVariants(buffer) {
  const [full, thumb] = await Promise.all([
    sharp(buffer)
      .rotate() // honour EXIF orientation before resizing, or portraits land sideways
      .resize(FULL_WIDTH, FULL_HEIGHT, { fit: 'inside', withoutEnlargement: true })
      .webp({ quality: 82 })
      .toBuffer(),
    sharp(buffer)
      .rotate()
      .resize(THUMB_WIDTH, THUMB_HEIGHT, { fit: 'inside', withoutEnlargement: true })
      .webp({ quality: 75 })
      .toBuffer(),
  ]);

  return { full, thumb };
}

/**
 * Write both variants. Idempotent: the same hash overwrites identical content.
 *
 * @param {string} baseDir
 * @param {string} hash
 * @param {{ full: Buffer, thumb: Buffer }} variants
 */
export async function write(baseDir, hash, variants) {
  const fullPath = pathFor(baseDir, hash, 'full');
  await mkdir(dirname(fullPath), { recursive: true });

  await Promise.all([
    writeFile(fullPath, variants.full),
    writeFile(pathFor(baseDir, hash, 'thumb'), variants.thumb),
  ]);
}

/**
 * @param {string} baseDir
 * @param {string} hash
 * @param {'full' | 'thumb'} variant
 * @returns {Promise<Buffer | null>}
 */
export async function read(baseDir, hash, variant) {
  try {
    return await readFile(pathFor(baseDir, hash, variant));
  } catch {
    // Missing on disk but present in the database is possible after a restore
    // that brought the dump but not the files. The caller answers 404 rather
    // than 500 — it is a gap, not a fault.
    return null;
  }
}

/**
 * @param {string} baseDir
 * @param {string} hash
 */
export async function remove(baseDir, hash) {
  await Promise.all([
    rm(pathFor(baseDir, hash, 'full'), { force: true }),
    rm(pathFor(baseDir, hash, 'thumb'), { force: true }),
  ]);
}

/**
 * Store an upload, reusing an existing copy when the bytes already exist.
 *
 * Hashing before encoding is deliberate: a re-upload of an unchanged file costs
 * one hash and a SELECT rather than two image encodes. On 2 vCPU that is the
 * difference between a fast no-op and a visible stall.
 *
 * @param {import('pg').Pool} pool
 * @param {string} baseDir
 * @param {Buffer} buffer
 */
export async function store(pool, baseDir, buffer) {
  const check = await inspect(buffer);
  if (!check.ok) return { ok: false, reason: check.reason };

  const hash = hashBytes(buffer);

  const { rows } = await pool.query('SELECT hash FROM covers WHERE hash = $1', [hash]);
  if (rows.length > 0) {
    // Already stored, by this user or any other. Nothing to encode, nothing to
    // write, no extra byte on disk.
    return { ok: true, hash, deduplicated: true };
  }

  const variants = await encodeVariants(buffer);
  await write(baseDir, hash, variants);

  await pool.query(
    `INSERT INTO covers (hash, byte_size, width, height) VALUES ($1, $2, $3, $4)
     ON CONFLICT (hash) DO NOTHING`,
    [hash, variants.full.length, check.width, check.height],
  );

  return { ok: true, hash, deduplicated: false };
}

/**
 * Delete covers no book references any more.
 *
 * Deliberately not called on book delete: books are soft-deleted so the
 * deletion can propagate, and a tombstoned book may still be restored by
 * `undoDelete()`. Reclaiming its cover immediately would make that undo produce
 * a book with a missing image.
 *
 * @param {import('pg').Pool} pool
 * @param {string} baseDir
 */
export async function collectGarbage(pool, baseDir) {
  const { rows } = await pool.query(
    `SELECT c.hash FROM covers c
      WHERE NOT EXISTS (SELECT 1 FROM books b WHERE b.cover_hash = c.hash)`,
  );

  for (const { hash } of rows) {
    await remove(baseDir, hash);
    await pool.query('DELETE FROM covers WHERE hash = $1', [hash]);
  }

  return rows.length;
}
