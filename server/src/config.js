/**
 * Environment configuration, validated once at startup.
 *
 * Fails loudly and immediately on anything missing or malformed. A server that
 * boots with half its configuration and only discovers the gap on the first
 * request is far harder to diagnose than one that refuses to start.
 */

/**
 * @param {string} name
 * @param {NodeJS.ProcessEnv} env
 * @returns {string}
 */
function required(name, env) {
  const value = env[name];
  if (value === undefined || value.trim() === '') {
    throw new Error(
      `Missing required environment variable ${name}. ` +
        'Copy server/.env.example to server/.env and fill it in.',
    );
  }
  return value;
}

/**
 * @param {string} name
 * @param {NodeJS.ProcessEnv} env
 * @param {number} fallback
 * @returns {number}
 */
function optionalPort(name, env, fallback) {
  const raw = env[name];
  if (raw === undefined || raw.trim() === '') return fallback;

  const port = Number(raw);
  if (!Number.isInteger(port) || port < 1 || port > 65535) {
    throw new Error(`${name} must be an integer between 1 and 65535, got "${raw}".`);
  }
  return port;
}

const LOG_LEVELS = ['fatal', 'error', 'warn', 'info', 'debug', 'trace', 'silent'];

/**
 * @param {NodeJS.ProcessEnv} [env]
 */
export function loadConfig(env = process.env) {
  const nodeEnv = env.NODE_ENV ?? 'development';
  const logLevel = env.LOG_LEVEL ?? 'info';

  if (!LOG_LEVELS.includes(logLevel)) {
    throw new Error(`LOG_LEVEL must be one of ${LOG_LEVELS.join(', ')}, got "${logLevel}".`);
  }

  return {
    nodeEnv,
    isProduction: nodeEnv === 'production',
    logLevel,
    databaseUrl: required('DATABASE_URL', env),
    // Loopback by default: the reverse proxy is the only thing that should
    // reach this port. Binding 0.0.0.0 has to be a deliberate choice.
    host: env.HOST ?? '127.0.0.1',
    port: optionalPort('PORT', env, 3000),
  };
}
