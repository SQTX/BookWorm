/**
 * Uses node:test and Fastify's inject(), so nothing here binds a port or needs
 * a running PostgreSQL. The pool is a stub.
 */
import assert from 'node:assert/strict';
import { test } from 'node:test';

import { buildApp } from '../src/app.js';
import { loadConfig } from '../src/config.js';

const TEST_ENV = {
  DATABASE_URL: 'postgres://test:test@localhost:5432/test',
  NODE_ENV: 'test',
  LOG_LEVEL: 'silent',
};

/** @param {{ ok: boolean }} opts */
function stubPool({ ok }) {
  return {
    query: async () => {
      if (!ok) throw new Error('connection refused');
      return { rows: [{ '?column?': 1 }] };
    },
    end: async () => {},
    on: () => {},
  };
}

test('GET /health returns ok when the database answers', async (t) => {
  const app = await buildApp(loadConfig(TEST_ENV), { pool: stubPool({ ok: true }) });
  t.after(() => app.close());

  const res = await app.inject({ method: 'GET', url: '/health' });

  assert.equal(res.statusCode, 200);
  assert.deepEqual(res.json(), { status: 'ok' });
});

test('GET /health returns 503 when the database is unreachable', async (t) => {
  const app = await buildApp(loadConfig(TEST_ENV), { pool: stubPool({ ok: false }) });
  t.after(() => app.close());

  const res = await app.inject({ method: 'GET', url: '/health' });

  // 503, not 200-with-a-flag: an uptime check must not have to parse the body.
  assert.equal(res.statusCode, 503);
  assert.deepEqual(res.json(), { status: 'degraded' });
});

test('health response exposes nothing beyond status', async (t) => {
  const app = await buildApp(loadConfig(TEST_ENV), { pool: stubPool({ ok: true }) });
  t.after(() => app.close());

  const res = await app.inject({ method: 'GET', url: '/health' });

  // The schema strips unknown keys; this asserts the intent, so adding a
  // hostname or version later fails here instead of leaking quietly.
  assert.deepEqual(Object.keys(res.json()), ['status']);
});

test('API routes live under the version prefix', async (t) => {
  const app = await buildApp(loadConfig(TEST_ENV), { pool: stubPool({ ok: true }) });
  t.after(() => app.close());

  const versioned = await app.inject({ method: 'GET', url: '/v1/' });
  assert.equal(versioned.statusCode, 200);
  assert.deepEqual(versioned.json(), { api: 'bookworm', version: 1 });

  // Nothing client-facing is served unversioned.
  const unversioned = await app.inject({ method: 'GET', url: '/' });
  assert.equal(unversioned.statusCode, 404);
});

test('loadConfig refuses to start without DATABASE_URL', () => {
  assert.throws(() => loadConfig({ NODE_ENV: 'test' }), /DATABASE_URL/);
});

test('loadConfig rejects a malformed PORT', () => {
  assert.throws(() => loadConfig({ ...TEST_ENV, PORT: '99999' }), /between 1 and 65535/);
  assert.throws(() => loadConfig({ ...TEST_ENV, PORT: 'http' }), /between 1 and 65535/);
});

test('loadConfig defaults to loopback rather than every interface', () => {
  assert.equal(loadConfig(TEST_ENV).host, '127.0.0.1');
});
