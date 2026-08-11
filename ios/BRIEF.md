# Brief — BookWorm Progress (iOS)

Hand this to a fresh session. It is the whole assignment.

---

## What to build

A one-purpose iPhone app: **update how far I am in the books I am currently
reading.** Open it, drag a slider, done.

Not a library app. Not a smaller version of the desktop. Someone puts a book
down, picks up the phone, moves a slider from 180 to 212, and puts the phone
down. If that takes more than five seconds or more than two taps, the app has
failed at the only thing it does.

### The screen

One screen. A list of the books whose status is `reading` — realistically one to
five of them. Each is a card with:

- cover thumbnail, title, author
- current page against total, and the percentage
- **a slider**, which is the entire interaction

Dragging the slider shows the page it would land on and the change from where the
book is now (`212 · +32 pages`). Releasing it sends the update. The card shows
that it saved, briefly and without a dialog.

That is the app. If a second screen appears, question it.

### Cases that will happen and must not break it

- **`pageCount` is `null`.** A slider needs a range and there isn't one. Fall
  back to a plain number field for those books. Do not invent a page count.
- **`currentPage` is `null`.** That is not page zero — it means unrecorded. Show
  it as unstarted; the slider begins at 0 but the book's stored value stays
  `null` until the user actually sets one.
- **Going backwards.** The slider's range is `0…pageCount`, not
  `currentPage…pageCount`. People misremember and correct themselves.
- **No books being read.** An empty state that says so plainly, not a spinner
  that never resolves.
- **Audiobooks** (`audioMode` is `audiobook`) still carry pages in this data
  model. Treat them the same; do not special-case them yet.

---

## The API

Full contract: [`docs/API.md`](../docs/API.md). Read it before writing the client
layer — it leads with the mistakes that have already been made once.

This app needs three endpoints. That is not a simplification; it is all of them.

```
POST /v1/auth/login          {email, password} → {accessToken, refreshToken, expiresIn}
POST /v1/auth/refresh        {refreshToken}    → {accessToken, refreshToken, expiresIn}

GET  /v1/books?status=reading                  → {books: [...]}
POST /v1/books/:id/progress  {currentPage}     → {book, pagesRead}
```

Base URL is the server's, e.g. `https://57.128.199.27.nip.io`. Ask the user for
it on first launch rather than hardcoding it.

**Use `/progress`, never a PATCH of `currentPage`.** The progress endpoint writes
the book *and* records a reading session in one operation. A PATCH updates the
number and silently leaves the statistics wrong, with no error to notice.

**Covers**: `GET /v1/covers/:hash/thumb`, using the book's `coverHash`. Responses
are immutable with a one-year cache, so cache them on disk by hash and never
re-fetch. Use `thumb`, not the full image, on a list.

**Tokens**: the access token is short-lived. Handle a `401` by refreshing once
and retrying, inside the HTTP layer, so no call site deals with it. Refresh
tokens rotate — always send the newest one you received, and never retry a failed
refresh with the same token, because the server treats a replayed refresh token
as theft and revokes every session.

Store both tokens in the Keychain, never in `UserDefaults`.

---

## Decisions to make before writing code

### 1. Distribution — decided: free personal signing

*(decided 2026-08-12)*

A free Apple ID and Xcode's Personal Team. No paid Developer Program, no
TestFlight — TestFlight requires the paid account, so "beta" here means the app
runs on the one phone it was built for, and nowhere else.

**The provisioning profile expires after seven days.** When it does, the app
stops launching and has to be re-deployed from Xcode with the phone connected.
That is the entire cost, and for one app on one phone it is the right trade: the
paid account buys convenience, not capability, and this app needs no capability
it cannot have.

Three consequences that shape the build:

- **Re-deploying is a normal event, not an error.** Do not build anything that
  assumes continuous installation. If the app is reinstalled rather than
  re-signed, its Keychain items go with it — so "no stored session, ask the user
  to sign in" must be an ordinary path with a clear prompt, not an error state.
  The desktop learned this the hard way for the same underlying reason: an
  identity that changes underneath stored credentials.
- **Restrict yourself to entitlements a Personal Team can sign.** Push
  notifications, App Groups and CloudKit are not available. This app needs none
  of them. If a design starts to want one, that is a signal the design has grown
  past the brief.
- **Keep the build reproducible from a clean checkout.** It will be rebuilt
  roughly weekly, potentially months apart. A build that needs remembered manual
  steps in Xcode is a build that will not work the third time.

If the weekly rebuild becomes genuinely irritating, the paid account is the fix
and nothing about this app has to change for it. Do not pre-emptively design
around a subscription the user has declined.

### 2. Offline

The phone will be offline sometimes, and a train is exactly where someone
finishes a chapter.

**Recommended:** a small local queue, not full sync. Persist pending updates as
`{bookId, currentPage, editedAt}`, apply them optimistically to the interface,
and flush on next launch or foreground. If two updates for the same book are
queued, keep the last. That is a few dozen lines and covers the real case.

Do **not** implement the full `/v1/sync` protocol for this app. It is most of the
work of the whole iOS phase and this app does not need it — it writes one field
through an endpoint designed for exactly that.

### 3. Language and framework

Swift and SwiftUI unless something argues otherwise. Say so and move on.

---

## What not to build

Adding books. Editing metadata. Tags, quotes, highlights, reviews. Statistics.
Challenges. Search. Settings beyond the server address and signing out.

All of that lives on the desktop, and every one of them is a reason the app takes
longer than five seconds to use. If the app proves useful and something is
genuinely missing, add it then — with evidence, not in advance.

---

## Ground rules

- **No server changes are needed.** Everything this app requires already exists
  and is deployed. If you believe you need a server change, that is a signal to
  re-read `docs/API.md` first.
- One branch per change, a PR into `dev`, `main` only at release time with an
  annotated tag. Nothing straight onto `dev`.
- Work in `ios/`. `server/` and `desktop/` are not part of this task.
- CI is path-filtered; `server.yml` will not cover this. Add a workflow once
  there is something to run.
- The user's library is real data accumulated over years, and the server holds
  the only networked copy. This app writes to it. Prefer a refused write to a
  wrong one.

---

## Done means

The app is on the user's iPhone. It shows the books they are actually reading,
with covers. Moving a slider and putting the phone down changes the page count,
and opening BookWorm on the Mac shows the new value and a reading session for
today.

Then stop and ask what is worth adding, rather than guessing.
