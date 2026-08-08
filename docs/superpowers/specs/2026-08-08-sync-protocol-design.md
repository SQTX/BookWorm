# Sync Protocol — Design

**Status:** Design. Not started.

**Decision (2026-08-08):** the desktop keeps its local database as a mirror of the server. Reads stay local, writes queue when offline and flush on reconnect. The alternative — a thin client where every read hits the server — was rejected.

---

## Why the mirror is less work, not more

The intuition says a thin client is simpler. Here it is the opposite, because of what already exists:

| | Mirror | Thin client |
| --- | --- | --- |
| `StatisticsProvider` (~20 properties, all SQL) | Unchanged — still queries a local database | Every statistic becomes a server endpoint |
| `BookController`, `BookModel`, all QML | Unchanged | Data layer rewritten |
| `DatabaseManager` | Unchanged; a sync layer is added beside it | Replaced by an HTTP client |
| Offline | Works | Dead, including a phone underground |

The mirror is additive. The thin client is a rewrite of the parts that already work, plus a reimplementation of every statistic on the server.

---

## What has to change in the schema

### Soft deletes

A hard `DELETE` cannot propagate. A second device that never saw the row has no way to learn it is gone — its absence is indistinguishable from never having existed, so the next pull re-creates it.

Every synced table gains:

```
deleted_at  TIMESTAMPTZ            -- NULL means live
```

Reads filter `WHERE deleted_at IS NULL`. Sync sends tombstones. A row is hard-deleted only by a sweep, once every device has plausibly seen it — and never before, because that is exactly what resurrects it.

This also fixes something the desktop already gets wrong: `undoDelete()` restores from an in-memory snapshot that dies with the process. With tombstones, undo is a column update.

### Change tracking

Every synced table gains, or already has:

```
updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()   -- touched on every write
```

`books` has it. `tags`, `challenges`, `favorite_quotes`, `highlights` and `reading_sessions` do not, and need it.

### Stable identity across devices

Server `SERIAL` ids cannot identify a row created offline: two devices would both mint id 96 for different books. Each synced row gains

```
uuid  UUID NOT NULL UNIQUE DEFAULT gen_random_uuid()
```

The client generates the UUID when it creates the row offline; the server accepts it. Integer ids stay as the local primary key so nothing existing breaks, but **the UUID is the identity that crosses machines**.

---

## The protocol

### Pull

```
GET /v1/sync?since=<ISO timestamp>
```

Returns every row of every synced table with `updated_at > since`, tombstones included, plus a `serverTime` to use as the next `since`.

`serverTime` comes from the server, never the client: clock skew on the client would otherwise silently skip rows written in the gap.

### Push

```
POST /v1/sync
{ "books": [...], "readingSessions": [...], ... }
```

Each row carries its `uuid` and the client's `updatedAt`. The server upserts on `uuid`.

The response returns the server's canonical version of everything it accepted, so the client can settle rather than assume its write won.

### Ordering

Push before pull, in one exchange. Pushing first means the client's own changes come back in the pull as canonical, and there is no window where a local edit is overwritten by a pull that has not seen it yet.

---

## Conflict policy

This is the open question the roadmap has been carrying. Three different answers, because the data has three different shapes.

### Reading sessions — already solved, do not touch

`ON CONFLICT (book_id, session_date, source) DO UPDATE SET page_start = LEAST(...), page_end = GREATEST(...)`

Idempotent and order-independent. Two devices pushing the same reading day converge with no resolver, and pages read can never be lost — only widened. **This is why the constraint must not be widened to include `user_id`**, and why CI pins it.

The thing a user cares most about — reading progress — therefore never has a conflict.

### Book fields — last-write-wins per row, on `updated_at`

Not per field. Per-field resolution needs a timestamp per column, which is a large schema and a large amount of code for a single user with two devices.

**The cost, stated plainly:** set a rating on the desktop and toggle the priority flag on the phone, both offline, and the later write wins the whole row — the earlier edit is lost. For one person with two devices, that window is minutes and the loss is one field of one book.

Ties (identical `updated_at`) break toward the server, so the outcome is deterministic rather than dependent on request order.

### Creates and deletes — the tombstone wins

Delete on one device, edit on another: the delete wins. `undoDelete()` exists and is now durable, so the recovery path is real rather than theoretical. The reverse rule — edit resurrects — would make deleting anything on a second device unreliable, which is worse.

---

## What syncs, and what does not

**Syncs:** `books`, `tags`, `book_tags`, `favorite_quotes`, `highlights`, `challenges`, `reading_sessions`.

**Does not sync:**

- **Cover images.** Their own phase: upload, re-encode, content-addressed storage. Until then `cover_image_path` syncs as a string and points at a path that only exists on one machine — a known gap, not an oversight.
- **Statistics.** Derived; the mirror recomputes them locally. Nothing to sync.
- **Settings** — theme, language, cards per row. `QSettings`, per-machine on purpose.
- **CSV and Markdown export.** Local file operations that never involved the server.

---

## Failure behaviour

- **Offline** is the normal state, not an error. Writes queue; the UI shows a quiet indicator, not a dialog.
- **A failed push does not clear the queue.** Retry with backoff, and the queue survives a restart — it is a table, not an array in memory.
- **A partial push must not half-apply.** One transaction per push.
- **Nothing blocks the UI on the network.** The app is fully usable with the server unreachable; that is the point of the mirror.

---

## Open questions

1. **Where does the queue live?** A table in the local database is the obvious answer, and makes it survive a crash.
2. **How often does a background pull run?** On launch, on reconnect, and on a timer. The timer's interval is a guess until there is a second device to observe.
3. **When is a tombstone hard-deleted?** Needs a window longer than the longest plausible offline period. 90 days is a starting point, not a considered answer.

---

## Success criteria

- [ ] A book created on the desktop while offline appears on the server after reconnect, with the same UUID
- [ ] A book deleted on one device disappears on the other and **stays** deleted through a subsequent pull
- [ ] The same reading day pushed from two devices in either order produces one session with the widest range
- [ ] Killing the app mid-push loses nothing: the queue is intact on restart
- [ ] The library fingerprint after a full round trip matches the pre-sync baseline
- [ ] Every statistic still renders with the network unplugged
