# Restore — Design

Date: 2026-07-20
Status: Approved

## Problem

Backup produces a ZIP holding a full `pg_dump` and every cover image, but nothing
reads it back. Recovering today means running `dropdb`, `createdb` and `psql` by
hand, and then dealing with cover files separately.

The archive format itself is proven: an archive was restored into a scratch database
with zero errors and matching row counts for all seven tables. What is missing is the
path from a file to a working library without a terminal.

## Solution Overview

Pick a `.zip`, and the app replaces the current database with its contents — after
proving the archive loads, and after taking a safety copy of what is about to be
destroyed.

## Guiding Principle

**The current database is not touched until the archive has been proven to load.**

Restore is the most destructive operation in the application, more so than "Reset All
Data" — reset at least leaves the user expecting emptiness. Every decision below
follows from that.

## Scope Decisions

| Question | Decision |
| --- | --- |
| Cover handling | Extracted into the app's data directory, with `cover_image_path` rewritten to point there. |
| Confirmation strength | Safety backup, plus typing a confirmation word to unlock the button. |
| Merge or replace | Replace. Merging is a different feature with its own duplicate-resolution questions. |
| Older archives | Must work. Validation requires only `books`; migrations run after loading. |
| Newer archives | Load as-is; unknown columns are simply present and unused. |

### Why covers move into the app directory

All 89 covers currently live under `~/Pictures/Notion/Banners/Books/book_cover/` as
absolute paths, so the database is tied to this machine and to a folder the app does
not own. Extracting them on restore breaks that dependency: after a restore, the
library is self-contained.

Covers that were absent at backup time keep their original path — it may still
resolve.

## Pipeline

1. **Choose file.** A file dialog filtered to `*.zip`.
2. **Validate the archive** without unpacking it: the ZIP opens, and `database.sql`
   and `manifest.json` are present and non-empty.
3. **Safety backup** of the current database into the app data directory, timestamped.
   Reuses the existing `backupTo` path. If it fails, restore aborts — refusing to
   destroy data we could not first copy.
4. **Trial load** into a scratch database, `wormbook_restore_check`. This is the
   moment of truth: a corrupt or truncated dump fails here, while the real database is
   still untouched.
5. **Count** what landed in the scratch database. These are the numbers shown in the
   confirmation.
6. **Confirm.** A dialog stating how many books exist now, how many the archive holds,
   and where the safety backup was written, with a text field requiring the word
   `RESTORE` (`ODTWÓRZ` in Polish) before the button enables.
7. **Replace.** `DROP SCHEMA public CASCADE; CREATE SCHEMA public;` then load the dump
   into the real database.
8. **Run migrations.** `initializeSchema()` again, so an archive predating a table or
   column arrives fully upgraded.
9. **Restore covers.** Extract `covers/` into the app data directory and rewrite
   `cover_image_path` for each book the manifest maps.
10. **Reload.** Books, models and statistics refresh so the UI reflects the new data.
11. **Clean up.** Drop the scratch database and remove temporary files.

The dump loads twice — once into the scratch database and once for real. That cost
buys the guarantee in the guiding principle, and is worth it.

## Failure Handling

| Failure | Behaviour |
| --- | --- |
| Archive unreadable or missing members | Abort at step 2. Nothing touched. |
| Safety backup fails | Abort at step 3. Nothing touched. |
| Trial load fails | Abort at step 4. Nothing touched. Report that the archive is unusable. |
| Scratch database cannot be created | Abort. Report that restore needs database-creation rights. |
| Real load fails after the schema was dropped | **This is the dangerous window.** Report the failure and the exact path of the safety backup, prominently, so recovery is one step away. |
| Cover extraction fails | Do not abort. The data is already restored; report which covers could not be written. |

Step 7 is the only point where data can be lost, and only if the load fails after the
drop. The safety backup exists specifically for that window.

## Implementation Shape

Extends `BackupManager`, which already owns `pg_dump` discovery, archive verification,
and process handling. A separate class would duplicate all of it.

New members:
- `Q_INVOKABLE QVariantMap inspectArchive(const QString &filePath)` — steps 2, 4 and
  5. Returns validity, the book count found, and any error, leaving the database
  untouched. This is what the confirmation dialog is built from.
- `Q_INVOKABLE bool restoreFrom(const QString &filePath)` — steps 3 and 7 to 11.
- `Q_INVOKABLE QString safetyBackupDir() const` — where safety copies are written.
- `restoreFinished(bool ok, QString message)`.

`psql` is located the same way `pg_dump` already is: `PATH` first, then known Homebrew
locations, failing loudly when absent.

## UI

In the Settings backup section, below the existing controls:
- A "Restore from Backup" button, opening a file dialog.
- A confirmation dialog showing the current book count, the archive's book count, the
  safety backup path, and a text field gating the confirm button.
- The result reported through the existing toast.

The button carries the same visual weight as "Reset All Data" — this is a destructive
action and should not look like a convenience.

## Out of Scope

- Merging an archive into the existing library.
- Selective restore of individual tables or books.
- Restoring from anything other than an archive this app produced.
- Automatic pruning of safety backups.

## Verification

1. Restore an archive into a library with different contents — book count matches the archive.
2. Reading sessions, priority flags, tags with colours, quotes, highlights, challenges all arrive.
3. Covers appear in the app data directory and render in the Library.
4. A safety backup exists at the reported path, and restoring it returns the previous state.
5. Feed a truncated ZIP — restore aborts and the library is unchanged.
6. Feed a ZIP without `database.sql` — rejected at validation.
7. Restore an archive predating `reading_sessions` — it loads, and the table exists afterwards.
8. Type the wrong word — the confirm button stays disabled.
9. With `psql` unavailable — the button explains itself rather than failing mid-way.
10. Polish UI shows no raw English.
