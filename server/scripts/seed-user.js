#!/usr/bin/env node
/**
 * Creates or updates the single account.
 *
 * There is no registration endpoint (D7), so this is the only way an account
 * comes into existence — which also means there is no signup path to attack.
 *
 *   SEED_EMAIL=me@example.com SEED_PASSWORD='...' npm run seed:user
 *
 * Credentials come from the environment, never from a file in this repository.
 * Refuses to overwrite an existing account unless SEED_FORCE=yes, so it cannot
 * silently reset the password of a working install.
 */
import { hash, Algorithm } from '@node-rs/argon2';
import pg from 'pg';

import { checkDatabase } from './guard-database.js';

const MIN_PASSWORD_LENGTH = 12;

async function main() {
  const guard = checkDatabase(process.env);
  if (!guard.ok) {
    process.stderr.write(`\n${guard.message}\n\n`);
    process.exit(1);
  }

  const email = process.env.SEED_EMAIL?.trim();
  const password = process.env.SEED_PASSWORD;

  if (!email || !password) {
    process.stderr.write(
      '\nSEED_EMAIL and SEED_PASSWORD must both be set.\n' +
        "Pass them on the command line so they do not persist in a file:\n" +
        "  SEED_EMAIL=me@example.com SEED_PASSWORD='...' npm run seed:user\n\n",
    );
    process.exit(1);
  }

  // One account means exactly one password protecting everything. A short one
  // here is not a small problem.
  if (password.length < MIN_PASSWORD_LENGTH) {
    process.stderr.write(
      `\nSEED_PASSWORD must be at least ${MIN_PASSWORD_LENGTH} characters.\n\n`,
    );
    process.exit(1);
  }

  const pool = new pg.Pool({ connectionString: process.env.DATABASE_URL });

  try {
    const { rows: existing } = await pool.query('SELECT id, email FROM users');

    if (existing.length > 0 && process.env.SEED_FORCE !== 'yes') {
      process.stderr.write(
        `\nAn account already exists (${existing[0].email}).\n` +
          'Re-run with SEED_FORCE=yes to replace its credentials.\n\n',
      );
      process.exit(1);
    }

    // Defaults are the library's own, which track the current OWASP guidance
    // more reliably than numbers hardcoded here and forgotten.
    const passwordHash = await hash(password, { algorithm: Algorithm.Argon2id });

    if (existing.length > 0) {
      await pool.query('UPDATE users SET email = $1, password_hash = $2 WHERE id = $3', [
        email,
        passwordHash,
        existing[0].id,
      ]);
      process.stdout.write(`Updated account ${email}\n`);
    } else {
      const { rows } = await pool.query(
        'INSERT INTO users (email, password_hash) VALUES ($1, $2) RETURNING id',
        [email, passwordHash],
      );
      process.stdout.write(`Created account ${email} (id ${rows[0].id})\n`);
    }
  } finally {
    await pool.end();
  }
}

await main();
