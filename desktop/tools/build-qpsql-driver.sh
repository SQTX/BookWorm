#!/usr/bin/env bash
# Build Qt's PostgreSQL SQL driver against the Homebrew Qt currently installed and put
# it where BookWorm looks for it — the app's own data directory, outside the Cellar.
#
# Why this exists: Homebrew does not ship QPSQL, and every `brew upgrade` of qtbase
# (a version bump *or* a revision bump such as 6.11.2 → 6.11.2_1) deletes the old
# Cellar directory, taking a driver stored in Qt's plugin tree with it. The app then
# starts and immediately fails with:
#   QSqlDatabase: can not load requested driver 'QPSQL', available drivers: QSQLITE
# main.cpp adds <AppDataLocation>/plugins to the library path; nothing but this app
# touches that directory. A driver built against Qt 6.N loads under any later 6.x,
# so this is needed once per Qt major, not once per upgrade — but it is cheap enough
# to just rerun whenever the symptom appears.
#
# Requirements: Homebrew qtbase and libpq, curl, cmake. Takes about a minute.
set -euo pipefail

QT_PREFIX=/opt/homebrew/opt/qtbase
LIBPQ_PREFIX=/opt/homebrew/opt/libpq
DEST="$HOME/Library/Application Support/sqtx/BookWorm/plugins/sqldrivers"

# Homebrew's version string may carry a revision suffix ("6.11.2_1"); the Qt source
# tarball does not. Strip it.
V="$(brew list --versions qtbase | awk '{print $2}' | sed 's/_[0-9]*$//')"
[[ -n "$V" ]] || { echo "qtbase is not installed via Homebrew" >&2; exit 1; }
[[ -x "$QT_PREFIX/bin/qt-cmake" ]] || { echo "qt-cmake not found at $QT_PREFIX/bin" >&2; exit 1; }
[[ -f "$LIBPQ_PREFIX/lib/libpq.dylib" ]] || { echo "libpq not found at $LIBPQ_PREFIX (brew install libpq)" >&2; exit 1; }

WORK="$(mktemp -d -t bookworm-qpsql)"
trap 'rm -rf "$WORK"' EXIT
cd "$WORK"

SRC="qtbase-everywhere-src-$V"
echo "==> Downloading $SRC"
curl -fsSLO "https://download.qt.io/official_releases/qt/${V%.*}/$V/submodules/$SRC.tar.xz"
tar xf "$SRC.tar.xz"

echo "==> Configuring sqldrivers against Qt $V"
"$QT_PREFIX/bin/qt-cmake" -S "$SRC/src/plugins/sqldrivers" -B build \
    -DCMAKE_BUILD_TYPE=Release \
    -DPostgreSQL_INCLUDE_DIR="$LIBPQ_PREFIX/include" \
    -DPostgreSQL_LIBRARY="$LIBPQ_PREFIX/lib/libpq.dylib" > configure.log 2>&1 \
    || { cat configure.log >&2; exit 1; }

grep -q 'PostgreSQL .* yes' build/config.summary \
    || { echo "configure did not enable PostgreSQL:" >&2; cat build/config.summary >&2; exit 1; }

echo "==> Building"
cmake --build build --target QPSQLDriverPlugin -j"$(sysctl -n hw.ncpu)" > build.log 2>&1 \
    || { tail -40 build.log >&2; exit 1; }

mkdir -p "$DEST"
cp build/share/qt/plugins/sqldrivers/libqsqlpsql.dylib "$DEST/"
echo "==> Installed $DEST/libqsqlpsql.dylib"
otool -L "$DEST/libqsqlpsql.dylib" | grep -E 'QtSql|libpq'
