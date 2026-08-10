/**
 * Process entry point. Everything testable lives in app.js; this file owns only
 * the things a test must not do — reading the real environment, binding a port,
 * and handling process signals.
 *
 * Run with `node --env-file=.env src/server.js`, or with the environment
 * supplied by the process supervisor in production.
 */
import { buildApp } from './app.js';
import { loadConfig } from './config.js';

const config = loadConfig();
const app = await buildApp(config);

// Without this, an unhandled rejection anywhere in a handler kills the process
// on a modern Node with no usable log line. Log it, then let the supervisor
// restart us — continuing in an unknown state is worse than a restart.
process.on('unhandledRejection', (reason) => {
  app.log.fatal({ err: reason }, 'Unhandled promise rejection');
  process.exit(1);
});

for (const signal of ['SIGINT', 'SIGTERM']) {
  process.on(signal, async () => {
    app.log.info(`${signal} received, shutting down`);
    // Closes the pool via the onClose hook, so in-flight queries finish
    // instead of being severed mid-transaction.
    await app.close();
    process.exit(0);
  });
}

// Say plainly what is running. A server accidentally left in development mode,
// or accidentally bound to every interface, should be obvious in the first log
// line rather than discovered later.
app.log.info(
  { env: config.nodeEnv, host: config.host, port: config.port },
  `starting in ${config.nodeEnv} mode`,
);

if (config.bindsPublicly) {
  app.log.warn(
    { host: config.host },
    'binding a non-loopback interface — this must be behind a firewall and a TLS proxy',
  );
}

if (!config.isProduction && config.bindsPublicly) {
  app.log.error('refusing to expose a non-production server on a public interface');
  process.exit(1);
}

try {
  await app.listen({ host: config.host, port: config.port });
} catch (err) {
  app.log.fatal({ err }, 'Failed to start');
  process.exit(1);
}
