# Install — desktop only

The Qt application and a local PostgreSQL. **No server, no account, no
network.** This is the whole product for one person on one Mac; sync is off by
default and the application never mentions it.

If you want the phone app or a second machine, use
[`INSTALL-FULL.md`](INSTALL-FULL.md) instead — it starts from this same install,
so nothing here is wasted.

**Time:** about fifteen minutes, most of it Homebrew downloading Qt.

---

## 1. Requirements

- macOS on Apple Silicon or Intel, with [Homebrew](https://brew.sh)
- Xcode Command Line Tools — `xcode-select --install`

```bash
brew install qt qtcharts qtdeclarative qtshadertools cmake postgresql@16
```

`brew install qt` pulls a lot; this is the slow step.

---

## 2. PostgreSQL

```bash
brew services start postgresql@16
createdb wormbook
```

That is all the database setup there is. The application runs idempotent
migrations on every launch, so there is no schema to apply by hand and no
migration tool to learn. (`desktop/sql/init.sql` exists as a *reference* of what
the schema looks like — you do not need to run it.)

Verify:

```bash
psql wormbook -c 'SELECT 1'
```

---

## 3. The PostgreSQL driver for Qt

**Read this section even if you are in a hurry — it is the one step that is not
optional and not automatic.**

Homebrew's Qt ships without the PostgreSQL driver, and the application cannot
open its database without it. The symptom is unmistakable:

```
QSqlDatabase: can not load requested driver 'QPSQL', available drivers: QSQLITE
```

The repository carries a script that builds it against whatever Qt Homebrew
has installed, so clone first:

```bash
git clone https://github.com/SQTX/BookWorm.git
cd BookWorm
desktop/tools/build-qpsql-driver.sh
```

About a minute. It downloads the matching Qt source, builds only the
PostgreSQL plugin, refuses unless configure reports `PostgreSQL ... yes`, and
installs the result to `~/Library/Application Support/sqtx/BookWorm/plugins/`
— the application's own directory, which it searches at launch.

> **Why there and not in Qt's plugin tree:** every `brew upgrade` of `qtbase`
> deletes the old Cellar directory, and anything stored inside it. A version
> bump does it, and so does a bare revision bump (`6.11.2` → `6.11.2_1`) with
> no Qt change at all. A driver kept in Qt's tree therefore died on every
> upgrade. In the application's own directory it survives them: it links
> through `/opt/homebrew/opt/*` symlinks, and a plugin built against Qt 6.N
> loads under any later 6.x. Run the script again only on a Qt major bump, or
> if the application tells you to — a missing driver now opens a dialog
> naming this script, instead of the app silently not opening.

---

## 4. Build

The CMake invocation refers to Qt through Homebrew's `/opt/homebrew/opt/*`
symlinks, which always point at the installed version, so there is nothing to
substitute:

```bash
mkdir -p desktop/build && cd desktop/build

cmake .. \
  -DCMAKE_PREFIX_PATH="/opt/homebrew/opt/qtbase;/opt/homebrew/opt/qtdeclarative;/opt/homebrew/opt/qtcharts;/opt/homebrew/opt/qtshadertools;/opt/homebrew/opt/qtmultimedia" \
  -DQt6Qml_DIR="/opt/homebrew/opt/qtdeclarative/lib/cmake/Qt6Qml" \
  -DQt6Quick_DIR="/opt/homebrew/opt/qtdeclarative/lib/cmake/Qt6Quick" \
  -DQt6QuickControls2_DIR="/opt/homebrew/opt/qtdeclarative/lib/cmake/Qt6QuickControls2" \
  -DQt6Charts_DIR="/opt/homebrew/opt/qtcharts/lib/cmake/Qt6Charts" \
  -DQt6ChartsQml_DIR="/opt/homebrew/opt/qtcharts/lib/cmake/Qt6ChartsQml" \
  -DQt6Multimedia_DIR="/opt/homebrew/opt/qtmultimedia/lib/cmake/Qt6Multimedia" \
  -DCMAKE_BUILD_TYPE=Release -Wno-dev

cmake --build . -j$(sysctl -n hw.ncpu)
```

The explicit `*_DIR` variables are not ceremony: Homebrew splits Qt across
packages, and `ChartsQml` in particular is not found from `CMAKE_PREFIX_PATH`
alone on a clean build.

After a code change, only the second command is needed. Reconfigure (the first)
when files are added to `CMakeLists.txt` or Qt modules change.

---

## 5. Run

```bash
open desktop/build/BookWorm.app
```

Or, to see log output in the terminal:

```bash
./desktop/build/BookWorm.app/Contents/MacOS/BookWorm
```

Drag the `.app` to `/Applications` if you want it in Launchpad. It is a normal
bundle with its own icon.

---

## 6. Configuration

There is none to speak of. Language, theme and layout are in Settings and
persist. The database connection can be overridden by environment variables when
you need to point at something other than the default — testing a schema change
against a restored copy, most usefully:

| Variable | Default |
| --- | --- |
| `BOOKWORM_DB_NAME` | `wormbook` |
| `BOOKWORM_DB_HOST` | `localhost` |
| `BOOKWORM_DB_PORT` | `5432` |
| `BOOKWORM_DB_USER` | your login name |
| `BOOKWORM_DB_PASSWORD` | empty |

```bash
BOOKWORM_DB_NAME=wormbook_test ./desktop/build/BookWorm.app/Contents/MacOS/BookWorm
```

---

## 7. Back it up

Settings → **Backup**. One ZIP containing a full `pg_dump`, every cover image
and a manifest. The archive is verified before it reaches the destination and is
written through a temporary file, so a failed run cannot destroy the previous
good backup. You can also set an interval and have it run at launch.

Restoring is in the same place. It trial-loads the archive into a scratch
database before touching anything real, shows you the book count on both sides,
takes a safety backup of what it is about to replace, and makes you type
`RESTORE` before the destructive button becomes active.

**CSV export is not a backup.** It omits quotes, highlights, summaries, reviews,
challenges, tag colours and reading sessions.

Both backup and restore need PostgreSQL's own tools (`pg_dump`, `psql`,
`createdb`, `dropdb`) on `PATH` — you already have them from `postgresql@16`.

---

## 8. When something goes wrong

| Symptom | Cause |
| --- | --- |
| `can not load requested driver 'QPSQL'` (the app shows this in a dialog) | Section 3 — run `desktop/tools/build-qpsql-driver.sh` |
| CMake cannot find `Qt6ChartsQml` | `-DQt6ChartsQml_DIR` missing, or a stale build directory |
| An icon is missing in the UI | The SVG is not listed in `qt_add_qml_module(RESOURCES …)`; a file on disk that is not listed there does not exist at runtime |
| Odd behaviour after renaming the project directory | The CMake cache holds absolute paths — delete `desktop/build` entirely and reconfigure |

A truly clean build needs the dotfiles too:

```bash
rm -rf desktop/build
```

`rm -rf desktop/build/*` leaves `.qt` and `.rcc` behind and is not clean.

---

## What you have now

A complete, private library manager that never touches the network. If you later
want it on a second machine or on your phone, continue with
[`INSTALL-FULL.md`](INSTALL-FULL.md) — nothing here has to be undone.
