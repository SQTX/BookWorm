# Brief — BookWorm Progress (iOS)

Hand this to a fresh session. It is the whole assignment, and it is self-contained:
everything needed to build the app is here. [`docs/API.md`](../docs/API.md) is the
fuller contract if a question arises that this file does not answer.

---

## 1. Context

BookWorm is a book tracker. Three parts in one repository:

- **`desktop/`** — a Qt6 C++/QML macOS app. Where a library is curated: books
  added, metadata edited, reviews written. Finished and in daily use.
- **`server/`** — a Node.js/Fastify API on a VPS, backed by PostgreSQL. Finished,
  deployed, and already exercised by the desktop client, which syncs to it.
- **`ios/`** — this. Nothing built yet.

The user's library is real: ~95 books with covers, reading sessions, ratings and
notes accumulated over years. The server holds the only networked copy. This app
writes to it.

**The server needs no changes.** Every endpoint this app uses exists and is live.
If you conclude you need a server change, re-read this brief and `docs/API.md`
first — that conclusion has been wrong every time it has come up.

---

## 2. The assignment

A one-purpose iPhone app: **update how far I am in the books I am currently
reading.** Open it, drag a slider, done.

Not a library app. Not a smaller desktop. Someone puts a book down, picks up the
phone, moves a slider from 180 to 212, and puts the phone down. If that takes
more than five seconds or more than two taps, the app has failed at the only
thing it does.

### The screen

One screen. A list of books whose status is `reading` — realistically one to five
of them. Each is a card:

- cover thumbnail, title, author
- current page against total, and the percentage
- **a slider**, which is the entire interaction

While dragging, show the page it would land on and the change from where the book
is now — `212 · +32 pages`. Releasing sends the update. The card confirms it
saved, briefly and inline. No dialog, no toast to dismiss, no navigation.

A second screen should be treated as a design failure until proven otherwise.

### Interaction details that decide whether it is pleasant

- The slider range is `0…pageCount`, **not** `currentPage…pageCount`. People
  misremember and correct themselves downwards.
- Dragging must feel precise on a 400-page book. A bare `Slider` gives roughly
  three pages per point of travel; consider a fine-adjust affordance — drag
  vertically to slow the rate, or `−`/`+` buttons for single pages — rather than
  making the user fight for an exact number.
- Send on release, not continuously. One request per gesture.
- Optimistic: the card shows the new value immediately and reconciles when the
  server answers. Never make the user watch a spinner to learn what they just did.

### Cases that will happen and must not break it

- **`pageCount` is `null`.** A slider needs a range and there is none. Fall back
  to a plain number field for those books. Do not invent a page count.
- **`currentPage` is `null`.** This means *unrecorded*, not page zero. Show the
  book as unstarted. The stored value stays `null` until the user sets one — and
  writing `0` where the user has `null` is a silent edit of their data, which has
  already happened once on the desktop, to 38 books.
- **No books currently being read.** A plain empty state, not a spinner that
  never resolves.
- **Audiobooks** (`audioMode == "audiobook"`) still carry pages in this data
  model. Treat them identically; do not special-case them yet.
- **A very long title, or no cover.** Both are normal. Neither should reflow the
  card into something unrecognisable.

---

## 3. Distribution — decided, D9 *(2026-08-12)*

A free Apple ID and Xcode's **Personal Team**. No paid Developer Program, and
therefore **no TestFlight** — the app runs on the one phone it is built for and
nowhere else.

**The provisioning profile expires after seven days.** The app then stops
launching until it is re-deployed from Xcode with the phone connected. That is
the entire cost, and at this size it is the right trade: the paid account buys
convenience, not capability.

Three consequences that shape the build:

- **Re-deployment is routine, not an error.** If a rebuild reinstalls rather than
  re-signs, Keychain items go with it. "No stored session — sign in again" must
  therefore be an ordinary, well-worded path, not an error state. The desktop hit
  the same identity-changed-underneath failure from the other direction, and it
  cost a whole debugging session.
- **Only entitlements a Personal Team can sign.** No push notifications, no App
  Groups, no CloudKit. This app needs none of them. A feature that starts wanting
  one has outgrown the brief — that is the signal, not an argument for the
  subscription.
- **The build must work from a clean checkout.** It will be repeated for as long
  as the app is used, sometimes months apart. Remembered manual Xcode steps are
  how that stops being true. Write the setup into `ios/README.md` as you go.

Reversible at any time by paying, and nothing about the app would have to change.
Which is exactly why it must not be designed around a subscription the user has
declined.

---

## 4. Technology

**Swift and SwiftUI**, unless something concrete argues otherwise. Say which you
chose and move on; this is not a decision worth a discussion.

`URLSession` and `Codable` are sufficient — no networking dependency. Keep
third-party packages at zero if you can: a weekly rebuild is a bad place for
dependency drift.

---

## 5. The API

Base URL is the server's — for this user, `https://57.128.199.27.nip.io`. **Ask
for it on first launch rather than hardcoding it**, alongside the email and
password. Store the URL in `UserDefaults`; store tokens in the **Keychain**,
never in `UserDefaults`.

The API version is in the path: everything below sits under `/v1`.

### Authentication

```http
POST /v1/auth/login
Content-Type: application/json

{ "email": "...", "password": "..." }
```
```json
{ "accessToken": "...", "refreshToken": "...", "expiresIn": 900 }
```

```http
POST /v1/auth/refresh
{ "refreshToken": "..." }
```
Same response shape.

`expiresIn` is seconds. The access token is short-lived, and expiring mid-session
is routine rather than exceptional.

**Handle `401` inside the HTTP layer**: refresh once, retry the original request,
and surface a failure only if the refresh itself fails. No call site should know
this happens.

**Refresh tokens rotate.** Every refresh returns a new one and invalidates the
old. The server treats a replayed refresh token as theft and revokes *every*
session for the account — so never retry a failed refresh with the same token,
and always send the newest one received. Getting this wrong signs the user out
everywhere.

Every other request carries `Authorization: Bearer <accessToken>`.

### Reading the library

```http
GET /v1/books?status=reading
```
```json
{ "books": [ { … }, { … } ] }
```

The filter is applied server-side. Do not fetch everything and filter locally.

A book object — these are the exact field names; decode only what you need:

```json
{
  "id": 42,
  "title": "Ubik",
  "author": "Philip K. Dick",
  "status": "reading",
  "pageCount": 224,
  "currentPage": 180,
  "coverHash": "1a0fdd9e…64 hex chars",
  "audioMode": "none",
  "readCount": 0,
  "updatedAt": "2026-08-12T00:21:32.000Z",

  "genre": null, "startDate": null, "endDate": null, "rating": null,
  "notes": null, "isbn": null, "publisher": null, "publicationYear": null,
  "publicationDate": null, "language": null, "coverImagePath": null,
  "itemType": "book", "isNonFiction": false, "isPriority": false,
  "series": null, "summary": null, "review": null, "tags": []
}
```

Two traps in that payload:

- **`id`, not `uuid`.** The REST endpoints identify books by the integer `id`.
  `uuid` exists in the database and travels in the sync protocol, but is **not**
  returned here. Use `id` for `/books/:id/progress`.
- **`coverImagePath` is meaningless to you.** It names a file on whichever
  machine wrote it. Ignore it entirely; covers come from `coverHash`.

### Writing progress

```http
POST /v1/books/42/progress
{ "currentPage": 212 }
```
```json
{ "book": { … }, "pagesRead": 32 }
```

**Use this. Never PATCH `currentPage`.** The progress endpoint writes the book
*and* records a reading session in one operation — and that session is what the
desktop's streaks, pages-per-day chart and heatmap are built from. A PATCH
updates the number, leaves the statistics quietly wrong, and returns `200` while
doing it.

`currentPage` must be an integer between 0 and 100000.

### Covers

```http
GET /v1/covers/<coverHash>/thumb      → image/webp
GET /v1/covers/<coverHash>            → image/webp, full size
```

Use `thumb` on a list. Responses are `immutable` with a one-year cache, and a
hash always denotes the same bytes, so cache them on disk keyed by hash and never
re-fetch. `URLSession`'s default cache honours those headers, so this may need no
code beyond not fighting it. A book with `coverHash: null` has no cover; show a
placeholder.

### Errors

| Status | Meaning |
| --- | --- |
| 400 | Malformed body, or a field the schema does not know — unknown fields are rejected, not ignored |
| 401 | Token missing, expired or rejected — refresh once, then re-authenticate |
| 404 | Not found, or not yours |
| 429 | Rate limited — back off, do not hammer |
| 500 | Server fault |

The body is `{ "error": "..." }`, and for validation failures also
`{ "message": "..." }` with the specific complaint. **Read `message` first** — on
a schema failure Fastify puts the useful text there and leaves `error` as the
generic status name.

---

## 6. Offline

The phone will be offline, and a train is exactly where someone finishes a
chapter.

**Do this:** a small local write queue. Persist pending updates as
`{ bookId, currentPage, editedAt }`, apply them optimistically to the interface,
and flush on next launch and on foreground. If two updates for the same book are
queued, keep the last — a page count is a state, not an increment. Show queued
books as pending, so the user is never misled about what the server knows.

**Do not** implement the `/v1/sync` protocol. It is most of the work of the whole
iOS phase and this app needs none of it: it writes one field through an endpoint
built for exactly that. Sync exists for clients that own a full library offline,
which this one deliberately does not.

For reading: cache the last successful `GET /books?status=reading` so the app
opens to something rather than to a spinner.

---

## 7. What not to build

Adding books. Editing metadata. Tags, quotes, highlights, summaries, reviews.
Statistics. Challenges. Series. Search. Sorting. Filtering beyond
`status=reading`. Settings beyond the server address and signing out.

All of it lives on the desktop, and every item is a reason the app stops being a
five-second interaction. If using the app proves something is genuinely missing,
add it then, with evidence — not in advance, on the argument that it would be
easy.

---

## 8. Ground rules

- **One branch per change, a PR into `dev`.** Nothing straight onto `dev` or
  `main`. `main` moves only at release time, and every release gets an annotated
  tag and a described GitHub release.
- **Work in `ios/`.** `server/` and `desktop/` are not part of this task.
- CI is path-filtered and `server.yml` will not cover this. Add a workflow once
  there is something worth running.
- Keep `ios/README.md` current as the setup document — specifically, how to build
  and sign from a clean checkout.
- The user writes in Polish; the repository's code, comments, commits and docs are
  in English. Keep both as they are.

---

## 9. Done means

The app is on the user's iPhone. It shows the books they are actually reading,
with covers. Moving a slider and putting the phone down changes the page count —
and opening BookWorm on the Mac shows the new value **and a reading session dated
today**.

Verify that last part explicitly rather than assuming it. The session is the
whole reason `/progress` exists, and its absence is exactly the failure a PATCH
would have caused silently.

Then stop, and ask what is worth adding. Do not guess.

---

## 10. Already learned, cheaper to read than to rediscover

Every one of these cost real time on the desktop side.

- **`null` is not `0`.** A book with no recorded page count is not a book of zero
  pages. Writing the wrong one is a silent edit of the user's data.
- **Never block the interface on the network or on the Keychain.** Both can take
  arbitrarily long. The desktop once froze so completely at launch that its
  window never appeared, because a Keychain read on the main thread was waiting
  behind a system dialog nobody could see.
- **A failed write must not lose its data.** Anything queued stays queued until
  the server confirms it.
- **Log what the app did**, somewhere retrievable. "Nothing happened" and
  "nothing was attempted" are indistinguishable from outside, and telling them
  apart was most of the work every time sync misbehaved.
- **Prefer a refused write to a wrong one.** This library is the user's real
  reading history, and there is no second networked copy.
