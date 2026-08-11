# BookWorm for iOS

Nothing is built yet. This directory exists so that the decisions which have to
be made *before* code are written down somewhere other than a chat log.

**The first thing to build is scoped in [`BRIEF.md`](BRIEF.md)** — a
single-purpose progress tracker, not the library. This file is the longer view
around it.

The server is finished and running, so this phase is a client against a contract
that already exists rather than two moving targets at once. Read
[`docs/API.md`](../docs/API.md) first — it is the contract, written so nothing
here needs the server's source.

## What it has to do

The desktop application is where a library is curated: adding books, editing
metadata, writing reviews. A phone is where reading is *recorded* — a few taps
while putting a book down. Those are different jobs, and the phone should do its
one well rather than the desktop's badly.

The first cut is narrower still than that, and deliberately: the books currently
being read, and a slider to move the page count. One screen. See
[`BRIEF.md`](BRIEF.md).

Everything else — adding books, editing metadata, tags, quotes, statistics,
challenges — is the desktop's, until using this proves otherwise. Each of them is
also a reason the app stops being a five-second interaction, which is the only
thing it is for.

## What has to be decided first

**Distribution gates everything.** Without a paid Apple Developer account an app
can be installed on a personal device but the signature expires in seven days and
it has to be rebuilt. That is tolerable for one person and not for anything else,
and it changes what is worth building. Nothing else in this phase should start
before it is settled.

**Language and UI framework** — Swift and SwiftUI is the obvious answer and
should be taken unless something argues against it.

**Offline behaviour.** The phone will be offline. Two honest options: a read-only
cache that refuses writes when unreachable, or a local store with queued writes
that syncs like the desktop does. The second is the same protocol already
implemented once, so it is understood rather than novel — but it is also most of
the work in this phase, and it should be a choice rather than a drift.

## What is already true, and must stay true

Every one of these was broken once during the desktop work. `docs/API.md` gives
the detail; this is the short list.

- `updatedAt` is the user's edit time and decides conflicts. `serverTime` is the
  pull cursor. They are not interchangeable.
- Rows are matched by `uuid`, assigned by the client that created the row.
- Two libraries that both hold data cannot be merged automatically. Ask.
- A cover's hash is of the bytes that were *uploaded*; a downloaded file never
  hashes to its own name. Never decide "changed?" by hashing something you
  downloaded.
- `null` is not `0`. Writing a zero where the user has nothing is a silent edit.
- Deletions must stay queued until the push succeeds.

## Ground rules

Same as the rest of the repository: one branch per change, a PR into `dev`,
`main` only at release time. CI has path filters, so this directory will need its
own workflow before it has anything to test.
