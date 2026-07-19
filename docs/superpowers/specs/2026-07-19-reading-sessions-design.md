# Reading Sessions — Design

Date: 2026-07-19
Status: Approved

## Problem

`books.current_page` is a single number, overwritten on every update. The app knows
where you are in a book but not how you got there. Every pace figure it shows —
including the pages/day estimate in Challenges — is inferred from two dates rather
than measured.

## Solution Overview

A `reading_sessions` table recording one row per book per day. "Add Pages" writes a
session; a new Statistics tab reports on them.

This is the first of two related features. Full JSON backup/restore follows and will
cover this table, which is why it is being built second — writing the backup first
would mean rewriting it, and shipping a backup that silently omits session data is
the worst kind of backup bug.

## Scope Decisions

| Question | Decision |
| --- | --- |
| Session granularity | One row per (book, day, source). A second "Add Pages" on the same day extends the existing row rather than creating a new one. |
| What creates a session | "Add Pages" → `manual`. "Mark as Read" → `completion`. Nothing else. |
| Editing `currentPage` in the book form | No session. That field edits metadata; it does not report reading. |
| Page number going backwards | No session, no negative rows. Treated as correcting a mistake. |
| Backfill of existing progress | None. History cannot be reconstructed, and inventing it would corrupt every pace chart. Stats start empty and fill up from now. |
| Deleting a session | In scope, from the sessions tab. |
| Editing a session, manual backdated entry, session duration | Out of scope. |
| Challenges pace estimates | Unchanged for now. Switching them to measured data is a separate change once sessions have accumulated. |

## Data Layer

**Migration** — `DatabaseManager::initializeSchema()`, same idempotent style as the
existing tables:

```sql
CREATE TABLE IF NOT EXISTS reading_sessions (
    id           SERIAL PRIMARY KEY,
    book_id      INTEGER NOT NULL REFERENCES books(id) ON DELETE CASCADE,
    session_date DATE NOT NULL,
    page_start   INTEGER NOT NULL,
    page_end     INTEGER NOT NULL,
    source       VARCHAR(16) NOT NULL DEFAULT 'manual',
    UNIQUE (book_id, session_date, source)
)
```

Plus an index on `session_date`, matching the existing index convention.

Pages read for a row is `page_end - page_start`. `ON DELETE CASCADE` means deleting a
book takes its sessions with it, consistent with how quotes and highlights behave.

**Why `source` exists.** Finishing a 400-page book sets `current_page` to 400 in one
action. Recorded as ordinary reading, that single event would dominate every pace
average. Splitting it into `completion` lets pace calculations use `manual` rows only,
while total pages read still reconciles against `current_page`.

**Why the UNIQUE constraint spans `source`.** A book can be finished on a day it was
also read normally. That day legitimately produces one `manual` row and one
`completion` row.

## Writing Sessions

`DatabaseManager::recordSession(bookId, pageStart, pageEnd, source)` performs:

```sql
INSERT INTO reading_sessions (book_id, session_date, page_start, page_end, source)
VALUES (:bookId, CURRENT_DATE, :pageStart, :pageEnd, :source)
ON CONFLICT (book_id, session_date, source)
DO UPDATE SET page_end = GREATEST(reading_sessions.page_end, EXCLUDED.page_end)
```

The daily merge is the database's job, not the caller's. `GREATEST` keeps the row
monotonic even if a later update reports a lower page.

Callers live in `BookController`, at the points that already update progress:
- the "Add Pages" path → `source = 'manual'`
- the "Mark as Read" path → `source = 'completion'`

`recordSession` is skipped entirely when `pageEnd <= pageStart`.

## Statistics

**`StatisticsProvider`** gains queries and properties for:
- current streak and longest streak of consecutive days with a session
- pages read per day over the last 30 days
- pages-by-weekday distribution
- pages this month, and mean pages per reading day
- the recent sessions list (book title, date, pages)

Pace figures count `manual` rows only. Totals count both.

All of it respects the existing `selectedYear` filter, with `year = 0` meaning all
time, matching every other statistic in this class.

## UI

`StatisticsView.qml` is 774 lines today — a single `Flickable` holding one long
`ColumnLayout`. Adding a second tab inline would push it past 1200.

It becomes a thin shell: the year filter, a `TabBar` ("Overview" / "Sessions"), and a
`StackLayout`. The current content moves unchanged into `StatisticsOverview.qml`; the
new tab is `StatisticsSessions.qml`. Each file then has one clear job, and the two
tabs can be reasoned about separately.

**Sessions tab contents:**
- Summary cards: current streak, longest streak, pages this month, mean pages per reading day
- Bar chart: pages per day, last 30 days
- Weekday distribution: which days you actually read
- Recent sessions list: book, date, pages, with a delete control per row

Deleting is included deliberately. Without it, the first mistaken session is permanent
and quietly skews every average, with `psql` as the only escape.

## Empty State

Because there is no backfill, the tab is nearly empty until sessions accumulate. That
is correct behaviour, not a defect. Each panel shows an explicit empty state
explaining that sessions are recorded from the first use of "Add Pages" onward, so the
emptiness reads as expected rather than broken.

## Translations

New keys in the `_pl` object of `translations.js`, covering: Sessions, Overview,
Current streak, Longest streak, Pages this month, Pages per reading day, Pages per
day, By weekday, Recent sessions, and the empty-state text.

## Verification

1. Use "Add Pages" on a book — a `manual` row appears for today with the correct page range.
2. Use "Add Pages" again the same day — the same row's `page_end` advances; no second row.
3. Use "Mark as Read" — a `completion` row appears closing the book to `pageCount`.
4. Edit `currentPage` in the book form — no session is written.
5. Set a lower page via "Add Pages" — no session, no negative row.
6. Delete a book — its sessions are gone.
7. Open Statistics → Sessions — figures match the rows in the database.
8. Delete a session from the list — the figures update.
9. Switch the year filter — session statistics respect it.
10. On a fresh install with no sessions, every panel shows its empty state rather than a zero or a broken chart.

## Out of Scope

- Backfilling history for existing progress.
- Editing sessions or adding backdated ones by hand.
- Session duration in minutes.
- Rewiring the Challenges pace estimate onto measured data.
- Including sessions in the CSV export — the JSON backup feature covers this next.
