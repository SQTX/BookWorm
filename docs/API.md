# BookWorm API

The contract between the server and any client. Written so a client can be built
against it without reading the server's source — if the two ever disagree, the
source in `server/src/` is right and this file is a bug.

**Base:** `https://<host>/v1` — the version is in the path, not a header. A client
in someone's pocket running a three-month-old build is the normal case, not the
exceptional one, and a path prefix lets both versions be served at once.

**Health** is the one endpoint outside the prefix: `GET /health` → `{"status":"ok"}`.
Unauthenticated, and the right thing for a monitor to poll.

---

## Authentication

Three public endpoints; everything else requires `Authorization: Bearer <accessToken>`.

| Method | Path | Body | Returns |
| --- | --- | --- | --- |
| POST | `/auth/login` | `{email, password}` | `{accessToken, refreshToken, expiresIn}` |
| POST | `/auth/refresh` | `{refreshToken}` | `{accessToken, refreshToken, expiresIn}` |
| POST | `/auth/logout` | `{refreshToken}` | `204` |

`expiresIn` is seconds. The access token is short-lived by design — assume it
expires mid-request and handle a `401` by refreshing once and retrying, rather
than by asking the user to log in again. The desktop client does this inside its
HTTP layer so no call site has to.

**Refresh tokens rotate.** Every refresh returns a new one and invalidates the
old. Presenting a refresh token that has already been used is treated as theft,
not as a mistake: every session for that account is revoked. A client that
retries a failed refresh with the same token will therefore log itself out — the
retry must use whatever the last successful call returned, or nothing.

`GET /` returns `{api, version, userId}` and is a cheap way to confirm a token
still works.

---

## Books

| Method | Path | Purpose |
| --- | --- | --- |
| GET | `/books` | Every book |
| GET | `/books/:id` | One book |
| POST | `/books` | Create |
| PATCH | `/books/:id` | Partial update |
| DELETE | `/books/:id` | Soft delete — see below |
| POST | `/books/:id/progress` | Record pages read |
| POST | `/books/:id/complete` | Mark as read |

### Fields

`title` and `author` are required; everything else is optional and nullable.

```
id            integer, server-assigned — this is what REST endpoints take
title         string, 1–512
author        string, 1–512
genre         string | null
pageCount     integer | null, 0–100000
currentPage   integer | null
startDate     "YYYY-MM-DD" | null
endDate       "YYYY-MM-DD" | null
rating        integer | null, 1–6
status        "reading" | "read" | "planned" | "abandoned"
notes         string | null
isbn          string | null
publisher     string | null
publicationYear  integer | null
publicationDate  "YYYY-MM-DD" | null
language      string | null
itemType      "book" | "article" | "newspaper" | "magazine" | "comic"
              | "manga" | "thesis" | "workbook" | "other"
isNonFiction  boolean
isPriority    boolean
audioMode     "none" | "audiobook" | "audiobook_support"
series        string | null
summary       string | null
review        string | null
readCount     integer
coverHash     string | null — 64 hex characters, see Covers
coverImagePath  string | null — local to whichever machine wrote it; never
                sync this field, it means nothing anywhere else
tags          string[]
updatedAt     ISO timestamp
```

**`uuid` is not in this list, deliberately.** Rows carry one in the database and
it is what the sync protocol matches on, but the REST book endpoints neither
accept nor return it: they identify a book by `id`. A client using only REST
never sees a uuid and never needs one.

**`null` and `0` are different.** A book with no recorded page count is not a
book of zero pages, and writing `0` where the user has `null` is a silent edit of
their data. The desktop client got this wrong once for 38 books.

**Unknown fields are rejected, not ignored.** A misspelled property returns `400`
rather than being dropped, so a client bug surfaces at the first request instead
of as missing data months later.

### Progress and completion

`POST /books/:id/progress` with `{currentPage}` and `POST /books/:id/complete`
with `{rating, review}` exist because both do two things atomically: they write
the book *and* record a reading session. A client that instead PATCHes
`currentPage` gets a book whose statistics are wrong and no error to tell it so.
Use these.

`complete` also increments `readCount`, which is how rereads are tracked.

### Deletion

`DELETE` is a soft delete: the row is tombstoned so the deletion can propagate to
other clients, and so it can be undone. A client must treat a tombstoned row as
gone — see Sync.

---

## Tags, quotes, highlights, challenges

| Method | Path |
| --- | --- |
| GET / POST | `/tags` |
| DELETE | `/tags/:id` |
| GET / POST | `/books/:bookId/quotes` |
| DELETE | `/quotes/:id` |
| GET / POST | `/books/:bookId/highlights` |
| DELETE | `/highlights/:id` |
| GET / POST | `/challenges` |
| DELETE | `/challenges/:id` |

Tags carry a `color`. Challenges carry a `metric` (`books`, `pages`,
`pages_per_day`), a `targetValue`, and either a period (`periodCount` +
`periodUnit`) or an explicit end date.

---

## Covers

Stored and served by the SHA-256 of the **original uploaded bytes**, in hex.

| Method | Path | Notes |
| --- | --- | --- |
| POST | `/covers` | `multipart/form-data`, field name `file`. Returns `{hash, deduplicated}` |
| GET | `/covers/:hash` | Full size, `image/webp` |
| GET | `/covers/:hash/thumb` | Thumbnail, `image/webp` |

Rate limited to 120 uploads a minute. A `429` means slow down, not fail — upload
sequentially and stop cleanly when you get one, leaving the rest for later.

**The hash you get back is not the hash of the bytes you receive later.** The
server hashes the original and stores a re-encoded WebP, so a downloaded file
never hashes to its own name. Any client that decides "has this cover changed?"
by hashing a file it downloaded will upload it again, receive a third hash, and
loop forever. The desktop client avoids this by never uploading a file that
lives in its download directory — a rule about *where the file came from*, not
what it is called, because a failed download leaves a correct file with a stale
name.

Covers deduplicate, so two books with the same edition share one stored image.
Both the server and any client must treat "this file already exists" as the
normal case.

Responses are `immutable` with a one-year cache: a hash is always the same bytes,
so a client may cache them permanently.

---

## Sync

Two endpoints. Both take and return the same envelope.

```
GET  /sync?since=<ISO timestamp>   → { serverTime, changes }
POST /sync   { books: [...], tags: [...], ... }   → { serverTime, changes }
```

`POST` pushes and pulls in one exchange: it applies what you send, then returns
everything that changed since your cursor. `GET` pulls only.

`changes` contains six arrays: `books`, `tags`, `challenges`, `favoriteQuotes`,
`highlights`, `readingSessions`. At most 1000 rows each per request.

### The two timestamps, which are not interchangeable

Every synced row carries both, and confusing them is the single most expensive
mistake available here.

- **`updatedAt`** — when the *user* made the edit. This decides conflicts: the
  later edit wins, on both sides, using the same comparison. Clients send it and
  must set it from their own clock at the moment of the edit.
- **`serverTime`** — returned by the server, and the only thing a client should
  store as its pull cursor. Pass it back as `since` next time.

Do not use `serverTime` as an edit time, and do not use your own clock as a
cursor. An earlier version of the server compared against its own write time; the
result was that every client edit after the first was discarded and answered
`200`, which is the worst possible combination.

### Deletions

A deletion travels as an ordinary row carrying `deletedAt`. It needs nothing else
— a tombstone may legitimately arrive with only a `uuid` and the two timestamps.
On receiving one, delete locally; do not create a tombstone of your own for a
deletion you did not make.

A client must keep unsent deletions queued until the push succeeds. Clearing the
queue on a failed push loses them permanently.

### Ordering

Push `tags` before `books`. Books create tags by name as a side effect, so
sending books first makes the tag rows collide with the ones their own books just
created.

### Identity

Rows are matched by `uuid`, assigned by whichever client created the row — never
by `id`, which is per-database. This is also why two libraries that both already
hold data cannot be merged automatically: the same book added on two machines has
two uuids, and nothing can tell that from two different books. A client facing
that situation must ask the user which side wins rather than guess.

### Reading sessions

One row per book per day per source, merged by the server with
`LEAST`/`GREATEST` on the page range. Sending the same day twice is safe and
order-independent; a client never needs to check for an existing row first.

---

## Errors

| Status | Meaning |
| --- | --- |
| 400 | Malformed body, or a field the schema does not know |
| 401 | Missing, expired or rejected token — refresh once, then re-authenticate |
| 404 | Not found, or not yours |
| 413 | Upload too large |
| 429 | Rate limited |
| 500 | Server fault |

The body is `{error}` and, for validation failures, `{message}` with the specific
complaint. Read `message` first: on a schema failure Fastify puts the useful part
there and leaves `error` as the generic status name.

---

## Notes for a new client

Things the desktop client learned the hard way, which are cheaper to read than to
rediscover:

- **Sync is opt-in.** A client that works without a server is a better client. Do
  not require an account to open the app.
- **Push before you pull** on startup. A pull alone strands anything edited while
  the last session was offline. Pushing first cannot corrupt the server: an older
  row is rejected by the merge rule, not applied.
- **Never block the interface on the network or on a keychain.** Both can take
  arbitrarily long, and one of them can put a system dialog in front of the user
  at launch.
- **Log what sync did**, somewhere the user can read. "Nothing happened" and
  "nothing was attempted" are indistinguishable from outside, and telling them
  apart is most of the work when something goes wrong.
