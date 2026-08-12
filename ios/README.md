# BookWorm Progress (iOS)

A one-purpose iPhone app: **move the page count on the books you are currently
reading.** Open it, drag a slider, put the phone down. Everything else — adding
books, metadata, tags, statistics — stays on the desktop, which is where a
library is curated.

The scope is set by [`BRIEF.md`](BRIEF.md); the server contract by
[`../docs/API.md`](../docs/API.md). This file is how to build it.

---

## What it does

One screen. A card per book whose status is `reading`, each with a cover, the
page against the total, and a slider. Releasing the slider writes the page —
one request per gesture, sent to `POST /v1/books/:id/progress`, which records a
reading session as well as the number. The desktop's streaks, pages-per-day
chart and heatmap are built from those sessions, which is why this app never
PATCHes `currentPage`.

Behaviour worth knowing before reading the code:

- **The slider spans `0…pageCount`**, not `currentPage…pageCount`. People
  misremember and correct downwards.
- **Fine adjustment**: drag away from the track and the rate drops to a quarter,
  then a tenth. `−` and `+` move a single page. On a 400-page book a stock
  `Slider` gives about three pages per point of travel, which makes landing on
  an exact page a fight.
- **`null` is not `0`.** A book with no recorded page shows as *not started* and
  stays `null` until the user sets a page. A book with no `pageCount` gets a
  number field instead of a slider — there is no range to invent.
- **Optimistic writes.** The card shows the new page immediately and reconciles
  when the server answers. A refused write puts the old value back rather than
  leaving a number the server does not have.
- **Offline**: writes are persisted to a queue *before* they are attempted,
  coalesced per book (a page is a state, not an increment), and flushed on
  launch and on foreground. The last successful reading list is cached, so the
  app opens to books rather than to a spinner.
- **Sign-in is asked for, never hardcoded** — server address, email, password.
  The address goes to `UserDefaults`, the tokens to the Keychain.

## Layout

```
ios/
├── BookWormProgress.xcodeproj/     # hand-written; opens in Xcode with no setup step
├── BookWormProgress/               # the app: SwiftUI, Keychain, covers
│   ├── BookWormProgressApp.swift   # entry point, foreground flush
│   ├── AppModel.swift              # screen state, optimistic writes, reconciliation
│   ├── Platform/                   # Keychain, file locations, cover cache
│   └── Views/                      # list, card, slider, sign-in, settings
└── BookWormKit/                    # a local Swift package: the logic, and its tests
    └── Sources/BookWormKit/
        ├── APIClient.swift         # HTTP, 401-refresh-retry, token rotation
        ├── ProgressService.swift   # queue + cache + API, the write path
        ├── PendingWrites.swift     # the offline queue
        ├── PageScrubber.swift      # the slider arithmetic
        └── …
```

`BookWormProgress/` is a *synchronized folder* in the Xcode project: files added
to it are picked up without editing the project file, and without a merge
conflict in `project.pbxproj` every time.

The split is not ceremony. The package builds for macOS too, so `swift test`
runs the whole of the logic in about a second with **no simulator runtime and no
code signing** — which is also all CI needs.

## Building from a clean checkout

Requires Xcode 26 or later and the iOS platform support. A fresh Xcode install
often has only the macOS toolchain; the symptom is
`iOS 26.5 is not installed` for every destination, including your connected
phone. Fix it once — it is a large download:

```bash
xcodebuild -downloadPlatform iOS
```

It wants roughly 15 GB free — the download, then the expanded platform — so
check `df -h /System/Volumes/Data` first. A near-full disk fails this part way
through rather than up front.

Run the logic tests (no simulator needed):

```bash
cd ios/BookWormKit && swift test
```

Build the app for the simulator, unsigned:

```bash
cd ios && xcodebuild build -project BookWormProgress.xcodeproj -scheme BookWormProgress \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  -configuration Debug CODE_SIGNING_ALLOWED=NO
```

## Putting it on the phone (free personal signing)

Decided in the brief, D9: a free Apple ID and Xcode's **Personal Team**. No paid
Developer Program, so no TestFlight — the app runs on the one phone it is built
for.

1. `open ios/BookWormProgress.xcodeproj`.
2. **Settings → Accounts** → add your Apple ID if it is not there.
3. Select the **BookWormProgress** target → **Signing & Capabilities**:
   - *Automatically manage signing* is already on.
   - Set **Team** to your personal team. This is the one manual step, and it is
     per-machine: `DEVELOPMENT_TEAM` is deliberately empty in the project so the
     file is not tied to one Apple ID.
   - If the bundle identifier `com.sqtx.bookworm.progress` is taken (someone
     else already registered it), change it to anything unique. Nothing in the
     code depends on it except the Keychain service name, which follows the
     bundle only by convention — changing it just means signing in again.
4. Connect the iPhone, pick it as the run destination, press Run.
5. On the phone, first launch only: **Settings → General → VPN & Device
   Management** → trust your developer certificate.
6. In the app: enter the server address, email and password.

### The seven-day expiry

A free provisioning profile lasts seven days. After that the app refuses to
launch until it is rebuilt from Xcode with the phone connected — step 4 again,
which takes under a minute. That is the whole cost of not paying, and it was a
deliberate trade: the paid account buys convenience, not capability.

**A rebuild can reinstall rather than re-sign, and a reinstall takes the
Keychain item with it.** The app treats that as an ordinary path: it says *"No
stored session. That is normal after the app is re-deployed from Xcode — sign in
again."* rather than showing an error. Queued writes survive it; they live in
Application Support, not the Keychain.

Also, because only a Personal Team can sign this: no push notifications, no App
Groups, no CloudKit. Nothing here needs them, and a feature that starts wanting
one has outgrown the brief.

## When something looks wrong

**Settings → Activity** is a log of what the app actually did — fetches, writes,
queued writes, refreshes, sign-outs, newest first. It exists because "nothing
happened" and "nothing was attempted" are indistinguishable from outside, and
telling them apart was most of the work every time the desktop's sync
misbehaved.

A book showing an orange *Queued* line is a write that has not reached the
server. It is on disk and goes out on the next launch or foreground.

## What is deliberately not here

Adding books, editing metadata, tags, quotes, highlights, summaries, reviews,
statistics, challenges, series, search, sorting, filtering beyond
`status=reading`, and `POST /v1/sync`. Each of them is a reason the app stops
being a five-second interaction. The sync protocol in particular is most of the
work of a full client and buys nothing here: this app writes one field through
an endpoint built for exactly that.
