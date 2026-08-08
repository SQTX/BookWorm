/**
 * PostgreSQL access.
 *
 * D4 in the roadmap: the `pg` driver with hand-written SQL, no ORM. The schema
 * leans on ON CONFLICT ... LEAST/GREATEST, CHECK constraints and (from Phase 1)
 * row-level security — exactly what ORMs abstract worst.
 *
 * The cost of that choice is that SQL injection is no longer prevented by
 * construction. Every value reaching a query MUST arrive as a parameter
 * ($1, $2, ...). String-concatenated SQL is a bug, not a shortcut.
 */
import pg from 'pg';

const { Pool } = pg;

/**
 * @param {{ databaseUrl: string }} config
 */
export function createPool(config) {
  const pool = new Pool({
    connectionString: config.databaseUrl,
    // Small box (2 vCPU, shared with PostgreSQL). More connections than the
    // database can usefully serve just moves the queue into Postgres.
    max: 10,
    idleTimeoutMillis: 30_000,
    connectionTimeoutMillis: 5_000,
  });

  // An idle client erroring out (server restart, network drop) emits on the
  // pool. Without a listener this reaches the process as an uncaught exception.
  pool.on('error', (err) => {
    // eslint-disable-next-line no-console
    console.error('Unexpected error on idle PostgreSQL client:', err.message);
  });

  return pool;
}

/**
 * Cheap liveness probe. Deliberately returns nothing about the connection
 * itself — a health endpoint should not describe the infrastructure behind it.
 *
 * @param {import('pg').Pool} pool
 * @returns {Promise<boolean>}
 */
export async function pingDatabase(pool) {
  try {
    await pool.query('SELECT 1');
    return true;
  } catch {
    return false;
  }
}
