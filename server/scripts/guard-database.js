#!/usr/bin/env node
/**
 * Refuses to let a destructive command run against a protected database.
 *
 * `wormbook` is the desktop app's live library — 95 books, reading sessions and
 * ratings accumulated over years, with no copy other than backups. The server's
 * migrations must never touch it: the ownership migration adds a NOT NULL
 * user_id column, and the desktop app knows nothing about that column, so the
 * moment it lands the app can no longer insert a book.
 *
 * That failure would be silent until the next time a book was added. This guard
 * turns it into a refusal at the point of the mistake instead.
 *
 * Runs before every migrate script. Set ALLOW_LIVE_DATABASE=i-understand to
 * override, which is only correct during Phase 4, once the desktop app talks to
 * the API rather than to PostgreSQL directly.
 */

const PROTECTED_DATABASES = ['wormbook'];
const OVERRIDE = 'i-understand';

/**
 * @param {string} connectionString
 * @returns {string} database name, or '' when it cannot be determined
 */
export function databaseNameFrom(connectionString) {
  try {
    // The pathname is "/dbname"; strip the leading slash. Falls through to ''
    // for a malformed URL rather than throwing, so the caller decides.
    return new URL(connectionString).pathname.replace(/^\//, '');
  } catch {
    return '';
  }
}

/**
 * @param {NodeJS.ProcessEnv} env
 * @returns {{ ok: true } | { ok: false, message: string }}
 */
export function checkDatabase(env) {
  const url = env.DATABASE_URL;

  if (!url) {
    return {
      ok: false,
      message:
        'DATABASE_URL is not set.\n' +
        'Copy server/.env.example to server/.env and point it at the server\'s own database.',
    };
  }

  const name = databaseNameFrom(url);

  if (!name) {
    return { ok: false, message: `DATABASE_URL is not a valid connection URL: "${url}"` };
  }

  if (PROTECTED_DATABASES.includes(name) && env.ALLOW_LIVE_DATABASE !== OVERRIDE) {
    return {
      ok: false,
      message:
        `Refusing to run against "${name}" — that is the desktop app's live library.\n\n` +
        'The ownership migration adds a NOT NULL user_id column. The desktop app does\n' +
        'not know about it and would fail on the next book it tries to insert.\n\n' +
        'Point DATABASE_URL at the server\'s own database instead (see .env.example).\n' +
        `If you are in Phase 4 and this is deliberate, set ALLOW_LIVE_DATABASE=${OVERRIDE}.`,
    };
  }

  return { ok: true };
}

// Only act when executed directly, so the tests can import the logic without
// the process exiting underneath them.
if (import.meta.url === `file://${process.argv[1]}`) {
  const result = checkDatabase(process.env);
  if (!result.ok) {
    process.stderr.write(`\n${result.message}\n\n`);
    process.exit(1);
  }
}
