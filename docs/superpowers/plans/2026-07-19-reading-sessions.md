# Reading Sessions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Record one reading session per book per day when the user adds pages, and report on those sessions in a new Statistics tab.

**Architecture:** A `reading_sessions` table written through a single `DatabaseManager::recordSession()` that merges same-day entries in SQL. Two new `BookController` invokables replace the QML "mutate a map and call updateBook" pattern for the two progress paths, so session recording cannot be bypassed. `StatisticsProvider` gains session queries behind the existing year filter. `StatisticsView.qml` splits into a tab shell plus one file per tab.

**Tech Stack:** C++17, Qt 6.11.1 (Core, Sql, Qml, Quick, QuickControls2, Charts), QML, PostgreSQL.

**Spec:** [2026-07-19-reading-sessions-design.md](../specs/2026-07-19-reading-sessions-design.md)

**Branch:** `feature/reading-sessions` (already checked out and pushed).

---

## Note on Testing

This project has no test framework — no test target in `CMakeLists.txt`, no test directory, no test dependency. Introducing one is out of scope.

Verification is **build + drive the running app + query the database**. Unlike the priority feature, most of this IS verifiable from the command line: sessions are rows, and `psql` can confirm them. Use that. Only the chart rendering needs human eyes.

**Rebuild** (no CMake changes):
```bash
cd /Users/sqtx/Projects/App/BookWorm/build && cmake --build . -j$(sysctl -n hw.ncpu)
```

**Full reconfigure** (required after adding a `Q_PROPERTY`, a signal, or a new QML file):
```bash
cd /Users/sqtx/Projects/App/BookWorm/build && cmake .. \
  -DCMAKE_PREFIX_PATH="/opt/homebrew/Cellar/qtbase/6.11.1;/opt/homebrew/Cellar/qtdeclarative/6.11.1;/opt/homebrew/Cellar/qtcharts/6.11.1;/opt/homebrew/Cellar/qtshadertools/6.11.1" \
  -DQt6Qml_DIR="/opt/homebrew/Cellar/qtdeclarative/6.11.1/lib/cmake/Qt6Qml" \
  -DQt6Quick_DIR="/opt/homebrew/Cellar/qtdeclarative/6.11.1/lib/cmake/Qt6Quick" \
  -DQt6QuickControls2_DIR="/opt/homebrew/Cellar/qtdeclarative/6.11.1/lib/cmake/Qt6QuickControls2" \
  -DQt6Charts_DIR="/opt/homebrew/Cellar/qtcharts/6.11.1/lib/cmake/Qt6Charts" \
  -DQt6ChartsQml_DIR="/opt/homebrew/Cellar/qtcharts/6.11.1/lib/cmake/Qt6ChartsQml" \
  -DCMAKE_BUILD_TYPE=Release -Wno-dev && cmake --build . -j$(sysctl -n hw.ncpu)
```

**Run detached** (GUI app; you cannot see the window):
```bash
cd /Users/sqtx/Projects/App/BookWorm/build && ./BookWorm.app/Contents/MacOS/BookWorm > /tmp/bw.log 2>&1 &
sleep 6
pkill -f "BookWorm.app/Contents/MacOS/BookWorm"
```
Then read `/tmp/bw.log`. Any QML warning is a finding. A `FileDialog: Cannot set /bookworm_export.csv` line is pre-existing and expected.

---

## File Structure

| File | Change |
| --- | --- |
| `src/database/databasemanager.h/.cpp` | `reading_sessions` table, index, `recordSession`, `deleteSession`, session statistics queries |
| `src/controllers/bookcontroller.h/.cpp` | `addPages`, `markAsRead`, `deleteReadingSession` invokables |
| `src/statistics/statisticsprovider.h/.cpp` | Session properties behind the year filter |
| `qml/components/BookListView.qml` | Two dialogs call the new invokables |
| `qml/components/StatisticsView.qml` | Becomes a tab shell |
| `qml/components/StatisticsOverview.qml` | **New** — the current statistics content, moved verbatim |
| `qml/components/StatisticsSessions.qml` | **New** — the sessions tab |
| `qml/theme/translations.js` | New PL keys |
| `CMakeLists.txt` | Two new QML files |
| `CLAUDE.md` | Schema, provider properties, feature list |

Tasks run in dependency order. Each ends in a working build.

---

### Task 1: Table and session writes

**Files:**
- Modify: `src/database/databasemanager.h`
- Modify: `src/database/databasemanager.cpp`

- [ ] **Step 1: Create the table**

In `initializeSchema()`, after the `highlights` table block, following the same style:

```cpp
    // Reading sessions table
    q.exec("CREATE TABLE IF NOT EXISTS reading_sessions ("
           "  id SERIAL PRIMARY KEY,"
           "  book_id INTEGER NOT NULL REFERENCES books(id) ON DELETE CASCADE,"
           "  session_date DATE NOT NULL,"
           "  page_start INTEGER NOT NULL,"
           "  page_end INTEGER NOT NULL,"
           "  source VARCHAR(16) NOT NULL DEFAULT 'manual',"
           "  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),"
           "  UNIQUE (book_id, session_date, source)"
           ")");
```

- [ ] **Step 2: Add the indexes**

With the other `CREATE INDEX` lines:

```cpp
    q.exec("CREATE INDEX IF NOT EXISTS idx_reading_sessions_book_id ON reading_sessions(book_id)");
    q.exec("CREATE INDEX IF NOT EXISTS idx_reading_sessions_date ON reading_sessions(session_date)");
```

- [ ] **Step 3: Declare the API**

In `src/database/databasemanager.h`, after the Challenges block:

```cpp
    // Reading sessions
    bool recordSession(int bookId, int pageStart, int pageEnd, const QString &source);
    bool deleteSession(int sessionId);
```

- [ ] **Step 4: Implement `recordSession`**

In `src/database/databasemanager.cpp`, after the challenges implementations:

```cpp
bool DatabaseManager::recordSession(int bookId, int pageStart, int pageEnd, const QString &source)
{
    // Nothing was read — a correction, or a no-op save.
    if (pageEnd <= pageStart)
        return false;

    QSqlQuery q(m_db);
    q.prepare(
        "INSERT INTO reading_sessions (book_id, session_date, page_start, page_end, source) "
        "VALUES (:bookId, CURRENT_DATE, :pageStart, :pageEnd, :source) "
        "ON CONFLICT (book_id, session_date, source) DO UPDATE SET "
        "  page_start = LEAST(reading_sessions.page_start, EXCLUDED.page_start), "
        "  page_end = GREATEST(reading_sessions.page_end, EXCLUDED.page_end)"
    );
    q.bindValue(":bookId",    bookId);
    q.bindValue(":pageStart", pageStart);
    q.bindValue(":pageEnd",   pageEnd);
    q.bindValue(":source",    source);

    if (!q.exec()) {
        qWarning() << "recordSession error:" << q.lastError().text();
        return false;
    }
    return true;
}
```

The daily merge happens in SQL, not in the caller. `LEAST`/`GREATEST` keep the row spanning the whole day's reading regardless of the order updates arrive in.

- [ ] **Step 5: Implement `deleteSession`**

```cpp
bool DatabaseManager::deleteSession(int sessionId)
{
    QSqlQuery q(m_db);
    q.prepare("DELETE FROM reading_sessions WHERE id = :id");
    q.bindValue(":id", sessionId);

    if (!q.exec()) {
        qWarning() << "deleteSession error:" << q.lastError().text();
        return false;
    }
    return true;
}
```

- [ ] **Step 6: Build**

Run the **Rebuild** command. Expected: `[100%] Built target BookWorm`.

- [ ] **Step 7: Verify the table exists**

Run the app detached, kill it, then:

```bash
psql -d wormbook -c "\d reading_sessions"
```

Expected: the six columns, the `UNIQUE (book_id, session_date, source)` constraint, and the two indexes.

Then exercise the merge directly through SQL to prove the `ON CONFLICT` clause works:

```bash
psql -d wormbook -c "INSERT INTO reading_sessions (book_id, session_date, page_start, page_end, source) VALUES ((SELECT MIN(id) FROM books), CURRENT_DATE, 10, 20, 'manual') ON CONFLICT (book_id, session_date, source) DO UPDATE SET page_start = LEAST(reading_sessions.page_start, EXCLUDED.page_start), page_end = GREATEST(reading_sessions.page_end, EXCLUDED.page_end)"
psql -d wormbook -c "INSERT INTO reading_sessions (book_id, session_date, page_start, page_end, source) VALUES ((SELECT MIN(id) FROM books), CURRENT_DATE, 20, 35, 'manual') ON CONFLICT (book_id, session_date, source) DO UPDATE SET page_start = LEAST(reading_sessions.page_start, EXCLUDED.page_start), page_end = GREATEST(reading_sessions.page_end, EXCLUDED.page_end)"
psql -d wormbook -c "SELECT book_id, session_date, page_start, page_end, source FROM reading_sessions"
```

Expected: exactly ONE row, `page_start = 10`, `page_end = 35`. Two rows means the constraint or the conflict target is wrong.

Clean up:
```bash
psql -d wormbook -c "DELETE FROM reading_sessions"
```

- [ ] **Step 8: Commit**

```bash
git add src/database/databasemanager.h src/database/databasemanager.cpp
git commit -m "feat: add reading_sessions table and write path"
```

---

### Task 2: Controller invokables and QML wiring

**Files:**
- Modify: `src/controllers/bookcontroller.h`
- Modify: `src/controllers/bookcontroller.cpp`
- Modify: `qml/components/BookListView.qml`

Today both progress paths live in QML: fetch the book map, mutate a key, call `updateBook`. If session recording is bolted on next to those calls, the next progress path someone adds will silently skip it. Moving both into `BookController` makes the session part of the operation instead of something callers remember to do.

- [ ] **Step 1: Declare the invokables**

In `src/controllers/bookcontroller.h`, after `getBookDetails`:

```cpp
    Q_INVOKABLE bool addPages(int bookId, int newCurrentPage);
    Q_INVOKABLE bool markAsRead(int bookId, int rating, const QString &review);
    Q_INVOKABLE bool deleteReadingSession(int sessionId);
```

- [ ] **Step 2: Implement `addPages`**

In `src/controllers/bookcontroller.cpp`, after `getBookDetails()`:

```cpp
bool BookController::addPages(int bookId, int newCurrentPage)
{
    auto existing = DatabaseManager::instance().fetchBookById(bookId);
    if (!existing.has_value()) {
        emit errorOccurred("Book not found");
        return false;
    }

    Book book = existing.value();
    const int previousPage = book.currentPage;
    book.currentPage = newCurrentPage;

    if (!DatabaseManager::instance().updateBook(book)) {
        emit errorOccurred("Failed to update progress");
        return false;
    }

    // Skipped automatically when the page did not advance.
    DatabaseManager::instance().recordSession(bookId, previousPage, newCurrentPage,
                                              QStringLiteral("manual"));

    loadBooks();
    emit booksChanged();
    return true;
}
```

- [ ] **Step 3: Implement `markAsRead`**

```cpp
bool BookController::markAsRead(int bookId, int rating, const QString &review)
{
    auto existing = DatabaseManager::instance().fetchBookById(bookId);
    if (!existing.has_value()) {
        emit errorOccurred("Book not found");
        return false;
    }

    Book book = existing.value();
    const int previousPage = book.currentPage;

    book.status = QStringLiteral("read");
    book.endDate = QDate::currentDate();
    book.rating = rating;
    book.currentPage = book.pageCount;

    if (!DatabaseManager::instance().updateBook(book)) {
        emit errorOccurred("Failed to update book");
        return false;
    }

    // Closing session, tagged separately so it does not distort pace averages.
    DatabaseManager::instance().recordSession(bookId, previousPage, book.pageCount,
                                              QStringLiteral("completion"));

    if (!review.trimmed().isEmpty())
        DatabaseManager::instance().updateReview(bookId, review.trimmed());

    loadBooks();
    emit booksChanged();
    return true;
}
```

Check the exact name of the review-updating method on `DatabaseManager` before writing this line — `BookController::updateReview` delegates to it, so read that method and call the same thing.

- [ ] **Step 4: Implement `deleteReadingSession`**

```cpp
bool BookController::deleteReadingSession(int sessionId)
{
    return DatabaseManager::instance().deleteSession(sessionId);
}
```

- [ ] **Step 5: Switch the Add Pages dialog**

In `qml/components/BookListView.qml`, replace the body of `addPagesDialog`'s `onAccepted` (around line 648):

```qml
        onAccepted: {
            // Force-commit typed text (editable SpinBox doesn't update value until Enter/focus-loss)
            addPagesSpinBox.value = addPagesSpinBox.valueFromText(addPagesSpinBox.contentItem.text, addPagesSpinBox.locale);
            bookController.addPages(bookListPage.contextBookId, addPagesSpinBox.value);
        }
```

- [ ] **Step 6: Switch the Mark as Read dialog**

Replace the body of `markAsReadDialog`'s `onAccepted` (around line 768):

```qml
        onAccepted: {
            bookController.markAsRead(bookListPage.contextBookId,
                                      markStarRating.selectedRating,
                                      markReviewField.text);
        }
```

- [ ] **Step 7: Full reconfigure and build**

New `Q_INVOKABLE` methods require regenerated moc output. Run the **Full reconfigure** command. Expected: `[100%] Built target BookWorm`.

- [ ] **Step 8: Verify both paths write sessions**

You cannot click the dialogs. Verify the C++ path directly by checking that the database ends up correct after driving the app is impossible — so instead verify by reading the code carefully AND confirming the app starts clean:

```bash
psql -d wormbook -c "DELETE FROM reading_sessions"
```

Run the app detached, kill it, and confirm `/tmp/bw.log` has no QML warnings about `addPages` or `markAsRead` being undefined — an unknown method on a context property produces a `TypeError` in the log at the moment it is called, not at startup, so absence of a startup error is NOT proof.

Report honestly that the two dialog paths need a human to click them. State exactly what the human should check:
- Use "Add Pages" on a book, advancing it by some pages.
- Run `psql -d wormbook -c "SELECT * FROM reading_sessions"` — one `manual` row for today with the correct range.
- Use "Add Pages" again the same day — the same row widens; still one row.
- Use "Mark as Read" on a different book — a `completion` row appears.

- [ ] **Step 9: Commit**

```bash
git add src/controllers/bookcontroller.h src/controllers/bookcontroller.cpp qml/components/BookListView.qml
git commit -m "feat: record reading sessions from the progress paths"
```

---

### Task 3: Session statistics queries

**Files:**
- Modify: `src/database/databasemanager.h`
- Modify: `src/database/databasemanager.cpp`

All queries take a `year` parameter, where `0` means all years — matching every existing statistics query in this class.

- [ ] **Step 1: Declare the queries**

In `src/database/databasemanager.h`, with the other statistics declarations:

```cpp
    // Reading session statistics (year = 0 means all years)
    QVariantList sessionDates(int year = 0);
    QVariantList pagesPerDay(int year = 0, int lastNDays = 30);
    QVariantList pagesByWeekday(int year = 0);
    QVariantList recentSessions(int year = 0, int limit = 30);
    int totalSessionPages(int year = 0);
    int readingDayCount(int year = 0);
```

- [ ] **Step 2: Implement `sessionDates`**

Returns the distinct days that have at least one `manual` session, newest first. Streaks are computed from this in `StatisticsProvider` — plain C++ over a date list is far easier to read and reason about than a SQL window function, and the list is small.

```cpp
QVariantList DatabaseManager::sessionDates(int year)
{
    QVariantList dates;
    QSqlQuery q(m_db);
    q.prepare(
        "SELECT DISTINCT session_date FROM reading_sessions "
        "WHERE source = 'manual' "
        "  AND (:year = 0 OR EXTRACT(YEAR FROM session_date) = :year) "
        "ORDER BY session_date DESC"
    );
    q.bindValue(":year", year);

    if (!q.exec()) {
        qWarning() << "sessionDates error:" << q.lastError().text();
        return dates;
    }
    while (q.next())
        dates.append(q.value(0).toDate());
    return dates;
}
```

- [ ] **Step 3: Implement `pagesPerDay`**

```cpp
QVariantList DatabaseManager::pagesPerDay(int year, int lastNDays)
{
    QVariantList result;
    QSqlQuery q(m_db);
    q.prepare(
        "SELECT session_date, SUM(page_end - page_start) AS pages "
        "FROM reading_sessions "
        "WHERE source = 'manual' "
        "  AND (:year = 0 OR EXTRACT(YEAR FROM session_date) = :year) "
        "  AND session_date >= CURRENT_DATE - :days::integer "
        "GROUP BY session_date ORDER BY session_date"
    );
    q.bindValue(":year", year);
    q.bindValue(":days", lastNDays);

    if (!q.exec()) {
        qWarning() << "pagesPerDay error:" << q.lastError().text();
        return result;
    }
    while (q.next()) {
        QVariantMap entry;
        entry["date"]  = q.value(0).toDate();
        entry["pages"] = q.value(1).toInt();
        result.append(entry);
    }
    return result;
}
```

- [ ] **Step 4: Implement `pagesByWeekday`**

`EXTRACT(DOW)` returns 0 for Sunday through 6 for Saturday. Days with no reading are absent from the result set, so the caller must handle gaps — the QML fills all seven slots.

```cpp
QVariantList DatabaseManager::pagesByWeekday(int year)
{
    QVariantList result;
    QSqlQuery q(m_db);
    q.prepare(
        "SELECT EXTRACT(DOW FROM session_date) AS dow, SUM(page_end - page_start) AS pages "
        "FROM reading_sessions "
        "WHERE source = 'manual' "
        "  AND (:year = 0 OR EXTRACT(YEAR FROM session_date) = :year) "
        "GROUP BY dow ORDER BY dow"
    );
    q.bindValue(":year", year);

    if (!q.exec()) {
        qWarning() << "pagesByWeekday error:" << q.lastError().text();
        return result;
    }
    while (q.next()) {
        QVariantMap entry;
        entry["weekday"] = q.value(0).toInt();  // 0 = Sunday
        entry["pages"]   = q.value(1).toInt();
        result.append(entry);
    }
    return result;
}
```

- [ ] **Step 5: Implement `recentSessions`**

Includes `completion` rows — the list is a log of what happened, not a pace measure. The `source` field is returned so the UI can label them.

```cpp
QVariantList DatabaseManager::recentSessions(int year, int limit)
{
    QVariantList result;
    QSqlQuery q(m_db);
    q.prepare(
        "SELECT s.id, s.session_date, s.page_start, s.page_end, s.source, b.title, b.author "
        "FROM reading_sessions s JOIN books b ON b.id = s.book_id "
        "WHERE (:year = 0 OR EXTRACT(YEAR FROM s.session_date) = :year) "
        "ORDER BY s.session_date DESC, s.id DESC LIMIT :limit"
    );
    q.bindValue(":year",  year);
    q.bindValue(":limit", limit);

    if (!q.exec()) {
        qWarning() << "recentSessions error:" << q.lastError().text();
        return result;
    }
    while (q.next()) {
        QVariantMap entry;
        entry["id"]     = q.value(0).toInt();
        entry["date"]   = q.value(1).toDate();
        entry["pages"]  = q.value(3).toInt() - q.value(2).toInt();
        entry["source"] = q.value(4).toString();
        entry["title"]  = q.value(5).toString();
        entry["author"] = q.value(6).toString();
        result.append(entry);
    }
    return result;
}
```

- [ ] **Step 6: Implement the two scalars**

```cpp
int DatabaseManager::totalSessionPages(int year)
{
    QSqlQuery q(m_db);
    q.prepare(
        "SELECT COALESCE(SUM(page_end - page_start), 0) FROM reading_sessions "
        "WHERE source = 'manual' "
        "  AND (:year = 0 OR EXTRACT(YEAR FROM session_date) = :year)"
    );
    q.bindValue(":year", year);

    if (!q.exec() || !q.next()) {
        qWarning() << "totalSessionPages error:" << q.lastError().text();
        return 0;
    }
    return q.value(0).toInt();
}

int DatabaseManager::readingDayCount(int year)
{
    QSqlQuery q(m_db);
    q.prepare(
        "SELECT COUNT(DISTINCT session_date) FROM reading_sessions "
        "WHERE source = 'manual' "
        "  AND (:year = 0 OR EXTRACT(YEAR FROM session_date) = :year)"
    );
    q.bindValue(":year", year);

    if (!q.exec() || !q.next()) {
        qWarning() << "readingDayCount error:" << q.lastError().text();
        return 0;
    }
    return q.value(0).toInt();
}
```

- [ ] **Step 7: Build**

Run the **Rebuild** command. Expected: `[100%] Built target BookWorm`.

- [ ] **Step 8: Verify the SQL against seeded data**

The queries are not called from anywhere yet, so verify the SQL itself. Seed three days of sessions, then run each statement by hand:

```bash
psql -d wormbook -c "DELETE FROM reading_sessions"
psql -d wormbook -c "INSERT INTO reading_sessions (book_id, session_date, page_start, page_end, source) VALUES ((SELECT MIN(id) FROM books), CURRENT_DATE, 0, 30, 'manual'), ((SELECT MIN(id) FROM books), CURRENT_DATE - 1, 30, 55, 'manual'), ((SELECT MIN(id) FROM books), CURRENT_DATE - 2, 55, 70, 'manual')"
psql -d wormbook -c "SELECT COALESCE(SUM(page_end - page_start), 0) FROM reading_sessions WHERE source = 'manual'"
psql -d wormbook -c "SELECT COUNT(DISTINCT session_date) FROM reading_sessions WHERE source = 'manual'"
psql -d wormbook -c "SELECT session_date, SUM(page_end - page_start) FROM reading_sessions WHERE source = 'manual' GROUP BY session_date ORDER BY session_date"
```

Expected: total pages `70`, reading days `3`, three rows of 15/25/30 pages ascending by date.

Leave this seed data in place — Task 5 and Task 6 need something to render.

- [ ] **Step 9: Commit**

```bash
git add src/database/databasemanager.h src/database/databasemanager.cpp
git commit -m "feat: add reading session statistics queries"
```

---

### Task 4: StatisticsProvider properties

**Files:**
- Modify: `src/statistics/statisticsprovider.h`
- Modify: `src/statistics/statisticsprovider.cpp`

- [ ] **Step 1: Declare the properties**

In `src/statistics/statisticsprovider.h`, after the Extended block:

```cpp
    // Reading sessions
    Q_PROPERTY(int currentStreak READ currentStreak NOTIFY dataChanged)
    Q_PROPERTY(int longestStreak READ longestStreak NOTIFY dataChanged)
    Q_PROPERTY(int sessionPagesTotal READ sessionPagesTotal NOTIFY dataChanged)
    Q_PROPERTY(double meanPagesPerReadingDay READ meanPagesPerReadingDay NOTIFY dataChanged)
    Q_PROPERTY(QVariantList pagesPerDay READ pagesPerDay NOTIFY dataChanged)
    Q_PROPERTY(QVariantList pagesByWeekday READ pagesByWeekday NOTIFY dataChanged)
    Q_PROPERTY(QVariantList recentSessions READ recentSessions NOTIFY dataChanged)
```

- [ ] **Step 2: Declare the getters and members**

Public getters, matching the existing style:

```cpp
    // Reading sessions
    int currentStreak() const;
    int longestStreak() const;
    int sessionPagesTotal() const;
    double meanPagesPerReadingDay() const;
    QVariantList pagesPerDay() const;
    QVariantList pagesByWeekday() const;
    QVariantList recentSessions() const;
```

Private members:

```cpp
    // Reading sessions
    int m_currentStreak = 0;
    int m_longestStreak = 0;
    int m_sessionPagesTotal = 0;
    double m_meanPagesPerReadingDay = 0.0;
    QVariantList m_pagesPerDay;
    QVariantList m_pagesByWeekday;
    QVariantList m_recentSessions;
```

Also declare a private helper:

```cpp
    void computeStreaks(const QVariantList &dates);
```

- [ ] **Step 3: Implement the getters**

One trivial getter per property, returning the matching member, in the same style as the existing ones.

- [ ] **Step 4: Implement `computeStreaks`**

`dates` arrives newest-first and contains only days that had reading.

```cpp
void StatisticsProvider::computeStreaks(const QVariantList &dates)
{
    m_currentStreak = 0;
    m_longestStreak = 0;

    if (dates.isEmpty())
        return;

    // Current streak counts back from today, or from yesterday if today has no
    // session yet — an evening reader should not see their streak reset each morning.
    const QDate today = QDate::currentDate();
    const QDate newest = dates.first().toDate();
    if (newest == today || newest == today.addDays(-1)) {
        QDate expected = newest;
        for (const QVariant &value : dates) {
            if (value.toDate() != expected)
                break;
            ++m_currentStreak;
            expected = expected.addDays(-1);
        }
    }

    // Longest streak: walk the whole list looking for consecutive runs.
    int run = 1;
    m_longestStreak = 1;
    for (int i = 1; i < dates.size(); ++i) {
        const QDate previous = dates.at(i - 1).toDate();
        const QDate current  = dates.at(i).toDate();
        if (current == previous.addDays(-1)) {
            ++run;
        } else {
            run = 1;
        }
        if (run > m_longestStreak)
            m_longestStreak = run;
    }
}
```

- [ ] **Step 5: Populate in `refresh()`**

In `refresh()`, alongside the existing assignments, using `m_selectedYear` exactly as the existing statistics do:

```cpp
    auto &db = DatabaseManager::instance();

    m_sessionPagesTotal = db.totalSessionPages(m_selectedYear);
    m_pagesPerDay       = db.pagesPerDay(m_selectedYear);
    m_pagesByWeekday    = db.pagesByWeekday(m_selectedYear);
    m_recentSessions    = db.recentSessions(m_selectedYear);

    const int readingDays = db.readingDayCount(m_selectedYear);
    m_meanPagesPerReadingDay = readingDays > 0
        ? static_cast<double>(m_sessionPagesTotal) / readingDays
        : 0.0;

    computeStreaks(db.sessionDates(m_selectedYear));
```

Match the surrounding code's way of getting at `DatabaseManager` — if `refresh()` already holds a reference, reuse it rather than adding a second one.

- [ ] **Step 6: Full reconfigure and build**

New `Q_PROPERTY` declarations require regenerated moc output. Run the **Full reconfigure** command. Expected: `[100%] Built target BookWorm`.

- [ ] **Step 7: Verify against the seeded data**

Task 3 left three days of sessions totalling 70 pages. Run the app detached and confirm `/tmp/bw.log` is clean.

The properties are not bound to anything yet, so their values cannot be observed from the command line. Say so plainly rather than implying they were checked. What you CAN state is that the build succeeded, the app starts, and the SQL those properties call was verified in Task 3.

- [ ] **Step 8: Commit**

```bash
git add src/statistics/statisticsprovider.h src/statistics/statisticsprovider.cpp
git commit -m "feat: expose reading session statistics"
```

---

### Task 5: Split StatisticsView into a tab shell

**Files:**
- Create: `qml/components/StatisticsOverview.qml`
- Create: `qml/components/StatisticsSessions.qml`
- Modify: `qml/components/StatisticsView.qml`
- Modify: `CMakeLists.txt`

This task is a pure restructure — no new statistics content. `StatisticsSessions.qml` is a placeholder here and gets filled in Task 6. Keeping the move and the new content in separate commits means that if the tabs break, the diff that broke them is small.

**Critical:** a `.qml` file that is not listed in `CMakeLists.txt` under `QML_FILES` will not be compiled into the module and fails at runtime with a module-import error. Do not skip Step 4.

- [ ] **Step 1: Create `StatisticsOverview.qml`**

Move the ENTIRE current content of `StatisticsView.qml` into the new file, with two changes:
- The root item keeps its type and id.
- The year filter `ComboBox` does NOT move — it stays in the shell. Remove it from the moved content, and replace every reference to its value with a property on the root:

```qml
    property int selectedYear: 0
```

Anything that read the ComboBox now reads `statsProvider.selectedYear` or this property, whichever the surrounding code already uses. Read the existing bindings before deciding; do not guess.

- [ ] **Step 2: Create a placeholder `StatisticsSessions.qml`**

```qml
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import BookWorm

Item {
    id: sessionsPage

    Text {
        anchors.centerIn: parent
        text: Theme.tr("No reading sessions yet")
        color: Theme.textSecondary
        font.pixelSize: Theme.fontSizeLarge
    }
}
```

- [ ] **Step 3: Rewrite `StatisticsView.qml` as the shell**

```qml
import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts
import BookWorm

Item {
    id: statisticsPage

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.spacingXL
        spacing: Theme.spacingLarge

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacingLarge

            Text {
                text: Theme.tr("Statistics")
                color: Theme.textOnBackground
                font.pixelSize: Theme.fontSizeHeader
                font.bold: true
            }

            Item { Layout.fillWidth: true }

            ComboBox {
                id: yearCombo
                Layout.preferredWidth: 120
                Layout.preferredHeight: 36
                font.pixelSize: Theme.fontSizeSmall
                Material.accent: Theme.primary

                model: {
                    var items = [Theme.tr("All time")];
                    var years = statsProvider.availableYears;
                    for (var i = 0; i < years.length; i++)
                        items.push(String(years[i]));
                    return items;
                }

                onCurrentIndexChanged: {
                    statsProvider.selectedYear =
                        currentIndex === 0 ? 0 : parseInt(currentText);
                }
            }
        }

        TabBar {
            id: statsTabs
            Layout.fillWidth: true
            Material.accent: Theme.primary

            TabButton { text: Theme.tr("Overview") }
            TabButton { text: Theme.tr("Sessions") }
        }

        StackLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            currentIndex: statsTabs.currentIndex

            StatisticsOverview { selectedYear: statsProvider.selectedYear }
            StatisticsSessions { }
        }
    }
}
```

The year ComboBox above is a reconstruction. Read the existing one in `StatisticsView.qml` first and preserve its actual behaviour — its model, its "All time" handling, and how it writes `selectedYear`. If the existing one differs from this sketch, the existing one wins.

- [ ] **Step 4: Register both new files in CMakeLists.txt**

In `qt_add_qml_module(BookWorm ... QML_FILES ...)`, after `qml/components/StatisticsView.qml`:

```cmake
        qml/components/StatisticsOverview.qml
        qml/components/StatisticsSessions.qml
```

- [ ] **Step 5: Full reconfigure and build**

New QML files require a reconfigure, not just a rebuild. Run the **Full reconfigure** command. Expected: `[100%] Built target BookWorm`.

- [ ] **Step 6: Verify nothing regressed**

Run the app detached and read `/tmp/bw.log` in full. Expected: no QML errors. Specifically watch for `StatisticsOverview is not a type` or `StatisticsSessions is not a type` — that means Step 4 was missed or the reconfigure did not happen.

The Statistics page must still render all its existing charts. You cannot see them; report that a human needs to confirm the Overview tab looks exactly as before, and that switching tabs and changing the year filter both work.

- [ ] **Step 7: Commit**

```bash
git add qml/components/StatisticsView.qml qml/components/StatisticsOverview.qml qml/components/StatisticsSessions.qml CMakeLists.txt
git commit -m "refactor: split StatisticsView into tab shell and per-tab files"
```

---

### Task 6: Build the sessions tab

**Files:**
- Modify: `qml/components/StatisticsSessions.qml`

Follow the visual conventions already used in `StatisticsOverview.qml`: read it first and reuse its card, chart, and spacing patterns rather than inventing new ones. The four summary cards should look like the existing summary cards, not like something new.

- [ ] **Step 1: Build the layout skeleton**

Replace the placeholder with a `Flickable` + `ScrollBar.vertical` (not a `ScrollView` — see the codebase's own note about double-scroll) holding a `ColumnLayout` with four sections: summary cards, pages-per-day chart, weekday distribution, recent sessions list.

- [ ] **Step 2: Summary cards**

Four cards bound to the provider:
- `Theme.tr("Current streak")` → `statsProvider.currentStreak` + `Theme.tr("days")`
- `Theme.tr("Longest streak")` → `statsProvider.longestStreak` + `Theme.tr("days")`
- `Theme.tr("Pages read")` → `statsProvider.sessionPagesTotal`
- `Theme.tr("Pages per reading day")` → `statsProvider.meanPagesPerReadingDay.toFixed(1)`

- [ ] **Step 3: Pages-per-day chart**

A bar chart over `statsProvider.pagesPerDay`, whose entries are `{ date, pages }`. Match how `StatisticsOverview.qml` builds its monthly bar chart — if it uses Qt Charts, use Qt Charts; if it draws Rectangles, draw Rectangles. Consistency matters more than the specific technique.

- [ ] **Step 4: Weekday distribution**

Seven bars, Monday through Sunday. `statsProvider.pagesByWeekday` returns `{ weekday, pages }` with `weekday` 0 = Sunday, **and omits days with no reading entirely**. Build a seven-slot array filled with zeros first, then populate it from the returned list — indexing the list directly will put data on the wrong days as soon as one day is missing.

Use `Theme.getMonthLabels()`'s sibling for day names if one exists; if not, add a `dayLabels()` helper to `Theme.qml` alongside it rather than hardcoding Polish or English strings in this file.

- [ ] **Step 5: Recent sessions list**

A `Repeater` over `statsProvider.recentSessions`, whose entries are `{ id, date, pages, source, title, author }`. Each row shows title, author, date, and pages, with a delete button calling:

```qml
bookController.deleteReadingSession(modelData.id);
statsProvider.refresh();
```

Rows with `source === "completion"` get a subtle label distinguishing them from ordinary reading — they are book completions, not sessions at the keyboard.

- [ ] **Step 6: Empty states**

Each section shows an explicit empty state when its data is empty, rather than an empty chart or a bare `0`. Text: `Theme.tr("No reading sessions yet")` with a second line explaining that sessions are recorded from the first use of "Add Pages".

This matters more than usual here: with no backfill, every existing user sees this state on first launch, and an unexplained empty tab reads as a broken feature.

- [ ] **Step 7: Full reconfigure and build**

Run the **Full reconfigure** command. Expected: `[100%] Built target BookWorm`.

- [ ] **Step 8: Verify**

Task 3 seeded three days of sessions. Run the app detached and read `/tmp/bw.log` — no QML warnings, especially none about undefined properties on `statsProvider`.

Then confirm the underlying numbers so the human knows what the tab should show:

```bash
psql -d wormbook -c "SELECT COALESCE(SUM(page_end - page_start), 0) AS pages, COUNT(DISTINCT session_date) AS days FROM reading_sessions WHERE source = 'manual'"
```

Report those numbers and state that a human must confirm the tab displays them.

- [ ] **Step 9: Commit**

```bash
git add qml/components/StatisticsSessions.qml
git commit -m "feat: add the reading sessions statistics tab"
```

---

### Task 7: Translations and documentation

**Files:**
- Modify: `qml/theme/translations.js`
- Modify: `qml/theme/Theme.qml` (only if Step 4 of Task 6 added a day-labels helper)
- Modify: `CLAUDE.md`

- [ ] **Step 1: Add the Polish strings**

Add to the `_pl` object, grouped with the other statistics keys:

```javascript
    "Overview": "Przegląd",
    "Sessions": "Sesje",
    "Current streak": "Aktualna seria",
    "Longest streak": "Najdłuższa seria",
    "days": "dni",
    "Pages read": "Przeczytane strony",
    "Pages per reading day": "Stron na dzień czytania",
    "Pages per day": "Strony dziennie",
    "By weekday": "Wg dnia tygodnia",
    "Recent sessions": "Ostatnie sesje",
    "No reading sessions yet": "Brak sesji czytania",
    "Sessions are recorded when you add pages": "Sesje zapisują się przy dodawaniu stron",
    "Completed": "Ukończono",
```

Before committing, grep every `Theme.tr("...")` call added in Tasks 5 and 6 and confirm each key appears here EXACTLY as written at the call site. A mismatch silently falls back to English.

- [ ] **Step 2: Build and verify both languages**

Run the **Rebuild** command, run the app, and confirm the log is clean.

Report that a human must switch to Polish and confirm no raw English strings appear on the Statistics page.

- [ ] **Step 3: Update CLAUDE.md**

- **Database Schema** section: add `reading_sessions` to the table list, with its columns and the `UNIQUE (book_id, session_date, source)` constraint.
- **StatisticsProvider** bullet: add the seven new properties.
- **BookController** bullet: add `addPages`, `markAsRead`, `deleteReadingSession` to the invokable list.
- **Project Structure** tree: add `StatisticsOverview.qml` and `StatisticsSessions.qml`.
- **QML Layer** section: replace the `StatisticsView.qml` description with the shell/overview/sessions split.
- **App Features**: add a line for reading sessions.
- **Key Patterns & Gotchas**: note that same-day sessions merge via `ON CONFLICT` in SQL rather than in C++.

- [ ] **Step 4: Commit**

`CLAUDE.md` is in `.gitignore`, so only the QML files are tracked:

```bash
git add qml/theme/translations.js qml/theme/Theme.qml
git commit -m "feat: add Polish translations for reading sessions"
```

---

## Final Verification

Clear the seed data first, so the checks run against real usage:

```bash
psql -d wormbook -c "DELETE FROM reading_sessions"
```

Then, in the running app:

- [ ] "Add Pages" on a book → one `manual` row for today with the right range.
- [ ] "Add Pages" again the same day → the same row widens; still one row.
- [ ] "Add Pages" with a LOWER page → no new row, no negative row.
- [ ] Edit `currentPage` through the book form → no session written.
- [ ] "Mark as Read" → a `completion` row closing the book to its page count.
- [ ] Delete a book that has sessions → its sessions are gone.
- [ ] Statistics → Sessions: figures match `psql`.
- [ ] Delete a session from the list → figures update immediately.
- [ ] Change the year filter → session figures follow it.
- [ ] Statistics → Overview: unchanged from before this feature.
- [ ] Switch to Polish → no raw English on either tab.
- [ ] All three themes → the sessions tab stays legible.
