# Optional Sync — Design

**Status:** Design. Not started.

**Requirement (2026-08-11):** synchronisation is opt-in. BookWorm stays a complete desktop application for someone who never sets up a server. Someone who does gets a Sync section in Settings, enters an address and credentials, and on first connection their existing library is uploaded so the server starts with everything already there.

Builds on [the sync protocol](2026-08-08-sync-protocol-design.md), which assumed sync was always on. This corrects that assumption.

---

## The default is off

The application must be indistinguishable from `v1.1.0` for a user who never touches the Sync settings. No login prompt, no error banner, no network call, no mention of a server outside the one Settings panel they chose not to open.

That is a stronger requirement than it sounds. It rules out:

- Any startup path that waits on the network
- Any UI element that appears "greyed out pending connection"
- Any error state for "not configured" — not configured is the normal state, not a fault

## One schema, always

The synced columns — `uuid`, `updated_at`, `client_updated_at`, `deleted_at` — are added to the local database for **every** user, whether or not they ever enable sync.

The alternative is to add them only when sync is switched on, which produces two schema variants and a conditional in every query that reads or writes a row. The columns are inert when unused: a `uuid` nobody sends costs 16 bytes, and `deleted_at IS NULL` is already how the reads will be written.

One schema, one code path, and enabling sync becomes a settings change rather than a migration.

### Deletions: a queue, not a column *(revised during implementation)*

The first draft copied the server and put a `deleted_at` column on every table,
filtering it out of reads. Implementing it showed the cost: **fifty-six read
queries** in `DatabaseManager` would each need `AND deleted_at IS NULL`, and
missing one means a deleted book reappearing in a single view — a bug that would
be found by a user, not by a compiler.

The server needs that column because it must serve tombstones to any client that
pulls, for an indefinite window. **The client's requirement is much smaller:**
remember its own deletions until they are pushed. That is a queue.

```
sync_tombstones (entity, uuid, deleted_at)
```

`deleteBook()` records the row's UUID, then deletes the row exactly as before.
Reads are untouched — the row is gone, so nothing can accidentally show it. Sync
pushes the queue and clears it.

Two consequences worth being explicit about:

- **Desktop-only behaviour is now genuinely identical**, not merely
  "indistinguishable in practice". Deletion is still a `DELETE`.
- **`undoDelete()` does not become durable**, which the first draft claimed it
  would. Undo needs the whole row back, and the row is gone; the in-memory
  snapshot stays. That is a real thing given up for not touching fifty-six
  queries, and it can be revisited on its own terms rather than as a side effect.

A full reset clears the queue rather than filling it: "reset this computer" is
not a request to wipe the server.

## Settings

A new **Sync** category, matching the existing four:

| Field | Stored in | Notes |
| --- | --- | --- |
| Enabled | `QSettings` | Default off |
| Server URL | `QSettings` | e.g. `https://57.128.199.27.nip.io` |
| Email | `QSettings` | The login, not an address anything is sent to |
| Password | **nowhere** | Exchanged for tokens once, then discarded |
| Access + refresh token | **macOS Keychain** | Never `QSettings`, which is a plaintext plist |

Plus a status line that says what is true: *Not configured* / *Connected, last synced 14:32* / *Offline — 3 changes waiting*.

## First connection: which way does the data go?

This is the part that needs deciding rather than assuming, because "upload everything" is only correct in one of three cases.

On first successful login the client pulls with no cursor, which returns the server's entire library, and compares:

| Local | Server | Action |
| --- | --- | --- |
| Has books | **Empty** | **Upload everything.** The case the requirement describes |
| Empty | Has books | **Download everything.** A second device joining |
| Empty | Empty | Nothing to do |
| Has books | Has books | **Ask.** See below |

### Why the fourth case cannot be decided automatically

Local rows are assigned UUIDs by the migration, on this machine, at that moment. They are not derived from the content. So the same book on two machines that each migrated independently has two different UUIDs, and the server cannot tell it is the same book — uploading produces a duplicate library rather than a merge.

This is not hypothetical. It happens whenever a second installation is populated from a CSV export rather than from a database copy: same books, new UUIDs.

So when both sides hold data, the client stops and asks, naming the counts:

> The server already has 95 books, and this computer has 95. They cannot be matched automatically — books added on different machines get different identities.
>
> **Download from server** (replace what is here) · **Upload from here** (may create duplicates) · **Cancel**

Cancel is the default. A wrong answer here silently doubles a library, and the user is better placed than the program to know which side is authoritative.

### After the first sync

Once a machine has synced, its UUIDs match the server's, and every subsequent sync is the ordinary incremental exchange. A local database backup preserves them; a CSV re-import does not.

## Upload is not a special path

The initial upload uses `POST /v1/sync` with the whole library, in batches, and nothing else. It is the same endpoint, the same conflict rules, the same code as an incremental push.

A separate "bootstrap" path would be exercised once per installation and therefore never debugged. Batching exists only because the request has a 1000-row limit per table, not because the operation is different.

## Turning it off

Disabling sync stops the client and forgets the tokens. It does **not** delete the local library, and does not touch the server.

Re-enabling later re-authenticates and resumes from the stored cursor — or, if the cursor is gone, performs a full pull, which is idempotent by construction.

## What sync being off changes elsewhere

- **Covers** stay exactly as they are today: a local absolute path in `cover_image_path`. With sync on, the client additionally uploads the file and stores the returned `cover_hash`. The local path is never sent.
- **Statistics** are unaffected either way. They are computed locally from the local database, which is the whole point of the mirror.
- **CSV and Markdown export** are local file operations and are unchanged.

## Open questions

1. **What happens to `cover_image_path` on a downloading device?** It receives `cover_hash` but no local file. Fetch on demand and cache, or fetch everything at sync time? Leaning on-demand — a phone should not pull 40 MB of images to show a list.
2. **How often does a background sync run?** On launch, on reconnect, after a local write settles, and on a timer. The interval is a guess until there are two devices to observe.

## Success criteria

- [ ] With sync never enabled, the app behaves exactly as `v1.1.0` — verified by the library fingerprint being unchanged and no network call being made
- [ ] Enabling sync on a machine with 95 books and an empty server results in 95 books on the server and an unchanged fingerprint locally
- [ ] A second client with an empty library downloads all 95
- [ ] Both sides populated produces a prompt, and Cancel leaves both untouched
- [ ] Disabling sync leaves the local library intact and the server untouched
- [ ] Pulling the network cable mid-sync loses nothing; the queue survives a restart
