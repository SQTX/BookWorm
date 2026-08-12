/**
 * Retention, against a real directory of real files.
 *
 * This is the one piece of the backup that deletes things, so "it looked right"
 * is not a standard it can be held to. Every case below is run by executing the
 * actual script — not a reimplementation of its rules in JavaScript, which
 * would pass happily while the shell did something else.
 *
 * `--prune-only` exists for exactly this: the retention half of the script,
 * runnable without a database.
 */
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { after, before, describe, test } from 'node:test';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const SCRIPT = path.join(here, '..', 'scripts', 'backup-db.sh');

/** A dump plus its cover archive, named the way a real run names them. */
function writePair(dir, stamp, { covers = true } = {}) {
  fs.writeFileSync(path.join(dir, `bookworm_${stamp}.dump`), `dump ${stamp}`);
  if (covers) fs.writeFileSync(path.join(dir, `covers_${stamp}.tar.zst`), `covers ${stamp}`);
}

function prune(dir, env = {}) {
  return execFileSync('bash', [SCRIPT, '--prune-only'], {
    encoding: 'utf8',
    env: {
      PATH: process.env.PATH,
      BACKUP_DIR: dir,
      // Point the config lookup at nothing, or a machine that happens to have
      // /etc/bookworm/backup.env would fail the suite depending on its contents.
      BACKUP_CONFIG: path.join(dir, 'absent.env'),
      ...env,
    },
  });
}

const listing = (dir) => fs.readdirSync(dir).sort();

describe('backup retention', () => {
  let root;

  before(() => {
    root = fs.mkdtempSync(path.join(os.tmpdir(), 'bookworm-retention-'));
  });

  after(() => {
    fs.rmSync(root, { recursive: true, force: true });
  });

  const freshDir = (name) => {
    const dir = path.join(root, name);
    fs.mkdirSync(dir);
    return dir;
  };

  test('keeps the newest N and deletes the rest', () => {
    const dir = freshDir('newest-n');
    for (const stamp of ['2026-01-01_0300', '2026-01-02_0300', '2026-01-03_0300', '2026-01-04_0300']) {
      writePair(dir, stamp);
    }

    prune(dir, { KEEP_COUNT: '2' });

    assert.deepEqual(listing(dir), [
      'bookworm_2026-01-03_0300.dump',
      'bookworm_2026-01-04_0300.dump',
      'covers_2026-01-03_0300.tar.zst',
      'covers_2026-01-04_0300.tar.zst',
    ]);
  });

  test('a dump and its covers are deleted together', () => {
    // A database restored into a library where every image is missing is the
    // failure this pairing exists to prevent, and the loss is silent: the book
    // rows still carry their hashes.
    const dir = freshDir('pairs');
    writePair(dir, '2026-02-01_0300');
    writePair(dir, '2026-02-02_0300');

    prune(dir, { KEEP_COUNT: '1' });

    assert.deepEqual(listing(dir), [
      'bookworm_2026-02-02_0300.dump',
      'covers_2026-02-02_0300.tar.zst',
    ]);
  });

  test('does nothing when there are fewer backups than the limit', () => {
    const dir = freshDir('under-limit');
    writePair(dir, '2026-03-01_0300');

    const output = prune(dir, { KEEP_COUNT: '14' });

    assert.deepEqual(listing(dir), [
      'bookworm_2026-03-01_0300.dump',
      'covers_2026-03-01_0300.tar.zst',
    ]);
    assert.doesNotMatch(output, /rotated/);
  });

  test('an empty directory is not an error', () => {
    const dir = freshDir('empty');
    prune(dir, { KEEP_COUNT: '3' });
    assert.deepEqual(listing(dir), []);
  });

  test('refuses to keep zero backups', () => {
    // "Keep none" is never what an operator means, and acting on it would empty
    // the directory on the next successful run.
    const dir = freshDir('zero');
    writePair(dir, '2026-04-01_0300');

    assert.throws(() => prune(dir, { KEEP_COUNT: '0' }), /KEEP_COUNT/);
    assert.equal(listing(dir).length, 2, 'nothing may be deleted when the setting is refused');
  });

  test('refuses a limit that is not a number', () => {
    const dir = freshDir('nonsense');
    writePair(dir, '2026-05-01_0300');

    assert.throws(() => prune(dir, { KEEP_COUNT: 'lots' }), /KEEP_COUNT/);
    assert.equal(listing(dir).length, 2);
  });

  test('a dump with no cover archive is still rotated', () => {
    const dir = freshDir('orphan');
    writePair(dir, '2026-06-01_0300', { covers: false });
    writePair(dir, '2026-06-02_0300');

    prune(dir, { KEEP_COUNT: '1' });

    assert.deepEqual(listing(dir), [
      'bookworm_2026-06-02_0300.dump',
      'covers_2026-06-02_0300.tar.zst',
    ]);
  });

  test('the age rule is off unless it is asked for', () => {
    const dir = freshDir('age-off');
    writePair(dir, '2020-01-01_0300');
    const old = new Date('2020-01-01T03:00:00Z');
    fs.utimesSync(path.join(dir, 'bookworm_2020-01-01_0300.dump'), old, old);
    fs.utimesSync(path.join(dir, 'covers_2020-01-01_0300.tar.zst'), old, old);

    prune(dir, { KEEP_COUNT: '14' });

    assert.equal(listing(dir).length, 2, 'years old, but within the count — kept');
  });

  test('the age rule drops what the count would have kept', () => {
    const dir = freshDir('age-on');
    writePair(dir, '2020-01-01_0300');
    writePair(dir, '2026-07-01_0300');
    const old = new Date('2020-01-01T03:00:00Z');
    fs.utimesSync(path.join(dir, 'bookworm_2020-01-01_0300.dump'), old, old);
    fs.utimesSync(path.join(dir, 'covers_2020-01-01_0300.tar.zst'), old, old);

    prune(dir, { KEEP_COUNT: '14', KEEP_DAYS: '30' });

    assert.deepEqual(listing(dir), [
      'bookworm_2026-07-01_0300.dump',
      'covers_2026-07-01_0300.tar.zst',
    ]);
  });

  test('settings come from the config file when the environment is silent', () => {
    const dir = freshDir('config-file');
    for (const stamp of ['2026-08-01_0300', '2026-08-02_0300', '2026-08-03_0300']) {
      writePair(dir, stamp);
    }
    const config = path.join(dir, 'backup.env');
    fs.writeFileSync(config, `BACKUP_DIR=${dir}\nKEEP_COUNT=1\nKEEP_DAYS=0\n`);

    execFileSync('bash', [SCRIPT, '--prune-only'], {
      encoding: 'utf8',
      env: { PATH: process.env.PATH, BACKUP_CONFIG: config },
    });

    assert.deepEqual(listing(dir).filter((f) => f.startsWith('bookworm_')), [
      'bookworm_2026-08-03_0300.dump',
    ]);
  });

  test('the environment overrides the config file', () => {
    // A one-off run against another directory must not require editing the
    // file and remembering to put it back.
    const dir = freshDir('env-wins');
    for (const stamp of ['2026-09-01_0300', '2026-09-02_0300', '2026-09-03_0300']) {
      writePair(dir, stamp);
    }
    const config = path.join(dir, 'backup.env');
    fs.writeFileSync(config, `BACKUP_DIR=${dir}\nKEEP_COUNT=1\nKEEP_DAYS=0\n`);

    execFileSync('bash', [SCRIPT, '--prune-only'], {
      encoding: 'utf8',
      env: { PATH: process.env.PATH, BACKUP_CONFIG: config, BACKUP_DIR: dir, KEEP_COUNT: '2' },
    });

    assert.equal(listing(dir).filter((f) => f.startsWith('bookworm_')).length, 2);
  });
});
