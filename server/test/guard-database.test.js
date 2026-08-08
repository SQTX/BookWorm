/**
 * The guard is the last thing standing between a mistyped DATABASE_URL and the
 * desktop app's live library, so its behaviour is pinned by tests rather than
 * left to inspection.
 */
import assert from 'node:assert/strict';
import { test } from 'node:test';

import { checkDatabase, databaseNameFrom } from '../scripts/guard-database.js';

test('extracts the database name from a connection URL', () => {
  assert.equal(databaseNameFrom('postgres://u:p@localhost:5432/bookworm_dev'), 'bookworm_dev');
  assert.equal(databaseNameFrom('postgres://localhost/wormbook'), 'wormbook');
  assert.equal(databaseNameFrom('not a url'), '');
});

test('refuses to run against the live desktop database', () => {
  const result = checkDatabase({ DATABASE_URL: 'postgres://sqtx@localhost:5432/wormbook' });

  assert.equal(result.ok, false);
  assert.match(result.message, /live library/);
  // The message must say what to do, not merely that something is wrong.
  assert.match(result.message, /\.env\.example/);
});

test('refuses when the query string dresses it up', () => {
  const result = checkDatabase({
    DATABASE_URL: 'postgres://sqtx@localhost:5432/wormbook?sslmode=disable',
  });

  assert.equal(result.ok, false);
});

test('allows the live database only with the explicit override', () => {
  const env = {
    DATABASE_URL: 'postgres://sqtx@localhost:5432/wormbook',
    ALLOW_LIVE_DATABASE: 'i-understand',
  };

  assert.deepEqual(checkDatabase(env), { ok: true });
});

test('a truthy-but-wrong override does not unlock it', () => {
  // Guards that accept any non-empty value get bypassed by accident.
  for (const value of ['1', 'true', 'yes', 'I-UNDERSTAND']) {
    const result = checkDatabase({
      DATABASE_URL: 'postgres://sqtx@localhost:5432/wormbook',
      ALLOW_LIVE_DATABASE: value,
    });
    assert.equal(result.ok, false, `override "${value}" must not unlock the guard`);
  }
});

test('allows the server database', () => {
  assert.deepEqual(
    checkDatabase({ DATABASE_URL: 'postgres://sqtx@localhost:5432/bookworm_dev' }),
    { ok: true },
  );
});

test('refuses when DATABASE_URL is missing or malformed', () => {
  assert.equal(checkDatabase({}).ok, false);
  assert.match(checkDatabase({}).message, /not set/);
  assert.equal(checkDatabase({ DATABASE_URL: 'garbage' }).ok, false);
});
