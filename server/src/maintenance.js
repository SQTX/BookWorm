/**
 * Background housekeeping.
 *
 * Runs in-process rather than as a cron entry. With one server that is fewer
 * moving parts, and a job that cannot be forgotten during a redeploy — a cron
 * line lives outside the repository and reliably gets lost.
 */
import { pruneExpiredTokens } from './auth/tokens.js';

/** Hourly is far more often than needed; the sweep is a single indexed DELETE. */
const PRUNE_INTERVAL_MS = 60 * 60 * 1000;

/**
 * Delete refresh tokens that can no longer authenticate anything.
 *
 * Without this the table grows for the lifetime of the install: every login and
 * every rotation appends a row, and nothing ever removes one. It is slow-motion
 * — a single user generates a handful a day — which is exactly why it would go
 * unnoticed until the table was large.
 *
 * Revoked-but-unexpired tokens are deliberately kept: they are what makes a
 * replay *detected* rather than merely unrecognised.
 *
 * @param {import('fastify').FastifyInstance} app
 */
export function startMaintenance(app) {
  const sweep = async () => {
    try {
      const removed = await pruneExpiredTokens(app.pg);
      if (removed > 0) app.log.info({ removed }, 'pruned expired refresh tokens');
    } catch (err) {
      // Housekeeping must never take the server down. Log and try again next
      // hour.
      app.log.error({ err }, 'token prune failed');
    }
  };

  const timer = setInterval(sweep, PRUNE_INTERVAL_MS);
  // Do not hold the event loop open: without this the process refuses to exit
  // on SIGTERM until the timer fires.
  timer.unref();

  // Once at startup, so a server that is restarted more often than the interval
  // still sweeps.
  sweep();

  app.addHook('onClose', async () => clearInterval(timer));

  return timer;
}
