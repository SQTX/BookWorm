# Backup — Design

Date: 2026-07-19
Status: Approved

## Problem

The app has no backup. CSV export is the only way data leaves it, and it is lossy by
construction: it writes 19 book columns and omits favourite quotes, highlights,
summaries, reviews, challenges, tag colours, and reading sessions entirely. Restoring
from it would return the metadata and drop everything that took effort to write.

Covers make it worse. All 89 books reference absolute paths under
`~/Pictures/Notion/Banners/Books/book_cover/`, outside the app. The database is
therefore tied to this machine: move that folder, or move to another machine, and
every cover breaks.

## Solution Overview

A ZIP archive containing a complete `pg_dump` of the database plus every referenced
cover image, produced either on demand or on an interval checked at app start.

## Archive Layout

```
bookworm-2026-07-19-2312.zip
├── manifest.json     # app version, timestamp, cover mapping, counts
├── database.sql      # pg_dump of the whole database
└── covers/
    ├── 8.webp
    ├── 43.jpg
    └── ...           # <book id>.<original extension>
```

### Why `pg_dump` rather than hand-written JSON

This reverses an earlier inclination toward JSON, for a reason visible in this very
codebase: the CSV exporter already suffers schema drift. It omits seven kinds of data
because each new feature required someone to remember to extend it, and nobody did.
Hand-rolled JSON would inherit exactly that failure mode — add a column, and the
backup silently stops covering it. The gap only surfaces during a restore, which is
the worst possible moment.

`pg_dump` captures everything without anyone remembering anything, and restoring is a
single command that does not require this application at all.

The cost is a dependency on an external binary. It is located at runtime by searching
`PATH` first, then known Homebrew locations. **If it cannot be found, the backup fails
loudly and writes nothing** — a partial backup presented as a complete one is worse
than no backup.

### Why covers are renamed by book id

Cover filenames are not unique: the source tree has per-year subdirectories, so two
`722371-352x500.jpg` files can exist under different years. Flattening by original
name would silently overwrite. `covers/<book id>.<ext>` cannot collide, and the id is
exactly what a future restore needs to reattach the image to its row.

`manifest.json` records each book's original absolute path alongside its archived
name, so a later restore can either rewrite paths to the extracted folder or put the
files back where they came from.

## Triggering

**Manual** — a button in Settings opens a file dialog for the destination, every time.
This mirrors the existing CSV export and needs no stored configuration.

**Automatic** — requires a destination folder chosen once in Settings. The interval is
a number plus a unit of days, months, or years. At application start, if the elapsed
time since the last successful backup exceeds the interval, a backup runs.

While no folder is configured, the automatic toggle is disabled and explains why.

### The limitation, stated plainly

BookWorm is not a background service. It has no daemon and does not start with the
system. "Automatic" can therefore only mean "checked when the app launches". If the
app is not opened for two months, no backup happens in those two months, whatever the
interval says.

This is worth knowing before relying on it, and it makes long intervals — the `Y`
option especially — weak protection. A `launchd` job running `pg_dump` independently
of the app would genuinely run on schedule, but it lives outside the application,
installs a file into the user's system, and is harder to undo. Rejected for now.

## Retention

Nothing is deleted automatically. Old archives accumulate until removed by hand.
Automatic deletion of backups is the last behaviour to add without an explicit
request, and a monthly interval produces twelve files a year.

## Settings UI

A new "Backup" section in the settings popup:
- A "Back up now" button.
- A destination-folder row: current path, or a prompt to choose one.
- An "Automatic backup" switch, disabled until a folder is set.
- Interval: a number field and a three-position selector for `D` / `M` / `Y`.
- The timestamp of the last successful backup, or a note that none has run.

Persistence follows the project's established `QSettings` pattern: a property on
`root` in `Main.qml`, a `property alias` in `Settings {}`, passed down by binding.

Stored settings: destination folder, automatic on/off, interval number, interval unit,
last successful backup timestamp.

## Implementation Shape

A new `BackupManager` class, registered as a QML element, owning the whole operation
so that neither `BookController` nor `DatabaseManager` grows another responsibility:

- `Q_INVOKABLE bool backupTo(const QString &filePath)` — the whole pipeline.
- `Q_INVOKABLE bool runAutomaticIfDue()` — called once at startup.
- Signals for success and failure, carrying a message for the existing toast system.

The pipeline, in a temporary directory:
1. Locate `pg_dump`; fail loudly if absent.
2. Run it into `database.sql` via `QProcess`.
3. Copy each non-empty `cover_image_path` to `covers/<id>.<ext>`, recording misses.
4. Write `manifest.json`.
5. Run `/usr/bin/zip -r` over the directory.
6. Verify the result (see below), then move it to the destination.
7. Remove the temporary directory whether or not the run succeeded.

Missing cover files are recorded in the manifest and reported in the result message
rather than aborting the backup — a broken image path should not cost the user their
database dump.

## Verification of the Archive

Restore is out of scope, which means these archives are unproven until the day someone
needs one. To narrow that gap, each backup is checked immediately after creation:

- the ZIP opens and lists its entries
- `database.sql` is present and non-empty, and mentions every expected table
- the number of archived covers matches the number of books that had a readable one

A failure here surfaces as a failed backup, not a silent success.

## Out of Scope

- Restore. **Consequence: these archives are unverified as restorable.** The checks
  above confirm the file is well-formed, not that it reconstitutes the database.
- Automatic deletion of old archives.
- Cloud or remote destinations.
- Backing up while the app is closed.
- Migrating cover paths so the library stops depending on `~/Pictures`.

## Verification

1. "Back up now", choose a path — a ZIP appears there.
2. `unzip -l` lists `manifest.json`, `database.sql`, and 89 covers.
3. `database.sql` contains `COPY` blocks for books, tags, book_tags, favorite_quotes, challenges, highlights, and reading_sessions.
4. Rename one cover file on disk, back up again — the backup still succeeds and reports the missing file.
5. Rename `pg_dump` out of `PATH`, back up — it fails with a clear message and writes no partial file.
6. Set the destination folder, enable automatic backup with an interval of 1 day, restart — a backup appears.
7. Restart again immediately — no second backup, because the interval has not elapsed.
8. Settings survive a restart.
9. Polish UI shows no raw English.
