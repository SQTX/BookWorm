# Book Priority Flag Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a per-book boolean priority flag that hoists flagged books to the front of the Library grid and marks their cards with an orange border.

**Architecture:** A new `is_priority` column flows through the existing layers unchanged in shape — `Book` struct → `BookModel` role → QML delegate. Hoisting is one extra comparison at the front of the existing default-sort comparator, gated by a `BookController::priorityEnabled` property that QML persists via `QSettings`.

**Tech Stack:** C++17, Qt 6.11.1 (Core, Sql, Qml, Quick, QuickControls2), QML, PostgreSQL.

**Spec:** [2026-07-19-book-priority-design.md](../specs/2026-07-19-book-priority-design.md)

---

## Note on Testing

This project has no test framework — no test target in `CMakeLists.txt`, no test directory, no test dependency. Introducing one is out of scope for this feature and would be a much larger change than the feature itself.

Verification is therefore **build + drive the running app**, and each task states exactly what to click and what to observe. This is weaker than automated tests: it catches "does it work", not "does it keep working". Treat the observations as required, not optional — an unobserved step is an unverified step.

Two commands recur throughout:

**Rebuild** (no CMake changes):
```bash
cd /Users/sqtx/Projects/App/BookWorm/build && cmake --build . -j$(sysctl -n hw.ncpu)
```

**Full reconfigure** (required after adding or removing a `Q_PROPERTY` or signal — a plain rebuild will not regenerate the moc output):
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

**Run:**
```bash
cd /Users/sqtx/Projects/App/BookWorm/build && ./BookWorm.app/Contents/MacOS/BookWorm
```

---

## File Structure

| File | Change |
| --- | --- |
| `src/models/book.h` | Add `isPriority` field |
| `src/models/book.cpp` | Serialize `isPriority` in all three converters |
| `src/database/databasemanager.cpp` | Migration + INSERT + UPDATE |
| `src/models/bookmodel.h` | Add `IsPriorityRole` |
| `src/models/bookmodel.cpp` | Add role name + data case |
| `src/controllers/bookcontroller.h` | Add `priorityEnabled` property, setter, signal, member |
| `src/controllers/bookcontroller.cpp` | Setter, sort comparison, CSV export/import |
| `qml/theme/Theme.qml` | Add `priority` colour token |
| `qml/theme/translations.js` | Add two PL keys |
| `qml/components/BookCard.qml` | Add `isPriority` property, border rule |
| `qml/components/BookListView.qml` | Delegate role, card binding, layout popup switch |
| `qml/components/BookForm.qml` | Priority checkbox + load/save/clear |
| `qml/Main.qml` | Settings alias + wiring |
| `CLAUDE.md` | Update field/role counts and feature list |

Tasks run in dependency order: data layer first, then model, then sorting, then UI. Each task ends in a working build.

---

### Task 1: Database column and Book struct

**Files:**
- Modify: `src/models/book.h`
- Modify: `src/models/book.cpp`
- Modify: `src/database/databasemanager.cpp`

- [ ] **Step 1: Add the field to the struct**

In `src/models/book.h`, after the `isNonFiction` line:

```cpp
    bool isNonFiction = false;
    bool isPriority = false;
```

- [ ] **Step 2: Add the migration**

In `src/database/databasemanager.cpp`, in `initializeSchema()`, directly after the `audio_mode` migration (around line 118), add a matching line for the new column:

```cpp
    q.exec("ALTER TABLE books ADD COLUMN IF NOT EXISTS is_priority BOOLEAN DEFAULT FALSE");
```

- [ ] **Step 3: Serialize in `toVariantMap()`**

In `src/models/book.cpp`, after the `isNonFiction` line:

```cpp
    map["isNonFiction"]    = isNonFiction;
    map["isPriority"]      = isPriority;
```

- [ ] **Step 4: Deserialize in `fromVariantMap()`**

After the `isNonFiction` line:

```cpp
    b.isNonFiction    = map.value("isNonFiction", false).toBool();
    b.isPriority      = map.value("isPriority", false).toBool();
```

- [ ] **Step 5: Deserialize in `fromSqlRecord()`**

After the `isNonFiction` line:

```cpp
    b.isNonFiction    = record.value("is_non_fiction").toBool();
    b.isPriority      = record.value("is_priority").toBool();
```

- [ ] **Step 6: Add the column to `insertBook()`**

In `src/database/databasemanager.cpp`, in `insertBook()`, extend the prepared statement so the column list ends with `review, is_priority` and the values list ends with `:review, :isPriority`:

```cpp
        "INSERT INTO books (title, author, genre, page_count, start_date, end_date, "
        "  rating, status, notes, isbn, publisher, publication_year, language, "
        "  cover_image_path, item_type, is_non_fiction, audio_mode, current_page, series, "
        "  publication_date, summary, review, is_priority) "
        "VALUES (:title, :author, :genre, :pageCount, :startDate, :endDate, "
        "  :rating, :status, :notes, :isbn, :publisher, :pubYear, :language, "
        "  :coverPath, :itemType, :isNonFiction, :audioMode, :currentPage, :series, "
        "  :pubDate, :summary, :review, :isPriority) "
        "RETURNING id"
```

Then add the bind after the `:review` bind:

```cpp
    q.bindValue(":isPriority",   book.isPriority);
```

- [ ] **Step 7: Add the column to `updateBook()`**

In `updateBook()`, change the SET clause line so `review = :review` is followed by the new column:

```cpp
        "  summary = :summary, review = :review, is_priority = :isPriority, updated_at = NOW() "
```

Then add the bind after the `:review` bind:

```cpp
    q.bindValue(":isPriority",   book.isPriority);
```

- [ ] **Step 8: Rebuild**

Run the **Rebuild** command. Expected: `[100%] Built target BookWorm`, no errors.

- [ ] **Step 9: Verify the migration ran**

Run the app once, close it, then:

```bash
psql -d wormbook -c "\d books" | grep is_priority
```

Expected: the column is listed as `boolean` with default `false`.

- [ ] **Step 10: Commit**

```bash
git add src/models/book.h src/models/book.cpp src/database/databasemanager.cpp
git commit -m "feat: add is_priority column and Book field"
```

---

### Task 2: Model role

**Files:**
- Modify: `src/models/bookmodel.h`
- Modify: `src/models/bookmodel.cpp`

The role is appended **after** `TagsRole` so existing role integer values do not shift. QML looks roles up by name, but C++ code and any cached indices rely on the numbering.

- [ ] **Step 1: Add the enum value**

In `src/models/bookmodel.h`, at the end of the `BookRoles` enum:

```cpp
        SeriesRole,
        TagsRole,
        IsPriorityRole
```

- [ ] **Step 2: Add the role name**

In `src/models/bookmodel.cpp`, in `roleNames()`, add a trailing entry (note the comma added to the `TagsRole` line):

```cpp
        { TagsRole,            "tags" },
        { IsPriorityRole,      "isPriority" }
```

- [ ] **Step 3: Add the data case**

In `data()`, after the `TagsRole` case:

```cpp
    case TagsRole:            return book.tags.join(", ");
    case IsPriorityRole:      return book.isPriority;
```

- [ ] **Step 4: Rebuild**

Run the **Rebuild** command. Expected: `[100%] Built target BookWorm`, no errors.

- [ ] **Step 5: Commit**

```bash
git add src/models/bookmodel.h src/models/bookmodel.cpp
git commit -m "feat: expose isPriority role on BookModel"
```

---

### Task 3: Controller property and sorting

**Files:**
- Modify: `src/controllers/bookcontroller.h`
- Modify: `src/controllers/bookcontroller.cpp`

This task adds a `Q_PROPERTY`, so it needs a **full reconfigure**, not a plain rebuild.

- [ ] **Step 1: Declare the property**

In `src/controllers/bookcontroller.h`, after the `sortMode` property:

```cpp
    Q_PROPERTY(bool priorityEnabled READ priorityEnabled WRITE setPriorityEnabled NOTIFY priorityEnabledChanged)
```

- [ ] **Step 2: Declare the accessors**

After the `setSortMode` declaration:

```cpp
    bool priorityEnabled() const;
    void setPriorityEnabled(bool enabled);
```

- [ ] **Step 3: Declare the signal**

In the `signals:` block, after `sortModeChanged()`:

```cpp
    void priorityEnabledChanged();
```

- [ ] **Step 4: Declare the member**

At the end of the private member list, after `m_sortMode`:

```cpp
    bool m_priorityEnabled = true;
```

- [ ] **Step 5: Implement the accessors**

In `src/controllers/bookcontroller.cpp`, directly after `setSortMode()`:

```cpp
bool BookController::priorityEnabled() const
{
    return m_priorityEnabled;
}

void BookController::setPriorityEnabled(bool enabled)
{
    if (m_priorityEnabled != enabled) {
        m_priorityEnabled = enabled;
        emit priorityEnabledChanged();
        applyFilters();
    }
}
```

- [ ] **Step 6: Add the sort comparison**

In `sortBooks()`, in the `default` branch only, capture `this` and make the priority check the first comparison:

```cpp
    if (m_sortMode == QStringLiteral("default")) {
        std::stable_sort(books.begin(), books.end(), [this](const Book &a, const Book &b) {
            if (m_priorityEnabled && a.isPriority != b.isPriority)
                return a.isPriority;

            int pa = statusPriority(a.status);
            int pb = statusPriority(b.status);
            if (pa != pb) return pa < pb;
```

Leave the rest of the lambda exactly as it is. Note the capture changed from `[]` to `[this]` — without it the member access will not compile.

Do not touch any other sort branch. Explicit sorts stay pure by design.

- [ ] **Step 7: Full reconfigure and build**

Run the **Full reconfigure** command (a `Q_PROPERTY` was added). Expected: `[100%] Built target BookWorm`, no errors.

- [ ] **Step 8: Verify sorting via the database**

Flag one planned book directly, so sorting can be checked before any UI exists:

```bash
psql -d wormbook -c "UPDATE books SET is_priority = TRUE WHERE status = 'planned' AND id = (SELECT MIN(id) FROM books WHERE status = 'planned')"
psql -d wormbook -c "SELECT id, title, status FROM books WHERE is_priority = TRUE"
```

Note the title returned. Run the app, open the Library with sort mode "Default".

Expected: that planned book is the **first card in the grid**, ahead of every book in progress.

Then switch the sort combo to "Title A→Z". Expected: the book returns to its alphabetical position — priority no longer hoists.

- [ ] **Step 9: Commit**

```bash
git add src/controllers/bookcontroller.h src/controllers/bookcontroller.cpp
git commit -m "feat: hoist priority books in default sort order"
```

---

### Task 4: Theme token and card border

**Files:**
- Modify: `qml/theme/Theme.qml`
- Modify: `qml/components/BookCard.qml`

- [ ] **Step 1: Add the colour token**

In `qml/theme/Theme.qml`, after the `statusAbandoned` block (around line 186), before the `// ── Typography ──` comment:

```qml
    // ── Priority ──

    property color priority: {
        switch (currentTheme) {
            case "minimalist_dark":  return "#D08A45";
            case "minimalist_light": return "#C1702A";
            case "classic":          return "#C87A32";
            default:                 return "#D08A45";
        }
    }
```

The light variant is darker so it holds contrast against the light surface.

- [ ] **Step 2: Add the card property**

In `qml/components/BookCard.qml`, after the `isNonFiction` property:

```qml
    required property bool isNonFiction
    required property bool isPriority
```

- [ ] **Step 3: Change the border rule**

In `qml/components/BookCard.qml`, in the hover border overlay (around line 295), replace the `border.color` line:

```qml
        border.color: mouseArea.containsMouse ? Theme.statusColor(card.status)
                    : (card.isPriority ? Theme.priority : "transparent")
```

The surrounding `Behavior on border.color { ColorAnimation { duration: 150 } }` stays and animates the transition for free.

- [ ] **Step 4: Rebuild**

Run the **Rebuild** command. Expected: `[100%] Built target BookWorm`.

The app will not run correctly yet — `BookCard` now declares a `required property` that `BookListView` does not pass. That is fixed in Task 5. Do not run the app at this step.

- [ ] **Step 5: Commit**

```bash
git add qml/theme/Theme.qml qml/components/BookCard.qml
git commit -m "feat: add priority theme colour and card border"
```

---

### Task 5: Library view wiring and the view toggle

**Files:**
- Modify: `qml/components/BookListView.qml`
- Modify: `qml/Main.qml`

- [ ] **Step 1: Add the delegate role**

In `qml/components/BookListView.qml`, in the `GridView` delegate, after the `isNonFiction` line (around line 301):

```qml
                    required property bool isNonFiction
                    required property bool isPriority
```

A `required property` that is declared on the card but not listed here silently fails to bind — this line is what makes the role reach the card.

- [ ] **Step 2: Pass it to the card**

In the same delegate, in the `BookCard` block, after the `isNonFiction` binding:

```qml
                        isNonFiction: cellDelegate.isNonFiction
                        isPriority: cellDelegate.isPriority
```

- [ ] **Step 3: Add the page property**

At the top of `BookListView.qml`, after `userCardsPerRow`:

```qml
    property int userCardsPerRow: 6  // persisted from Main.qml Settings
    property bool priorityEnabled: true  // persisted from Main.qml Settings
```

- [ ] **Step 4: Push the property into the controller**

Replace the existing `Component.onCompleted` block (around line 22) with this — QML allows only one handler per signal, so do not add a second one:

```qml
    onPriorityEnabledChanged: bookController.priorityEnabled = priorityEnabled

    Component.onCompleted: {
        availableYears = bookController.getAvailableYears();
        bookController.priorityEnabled = priorityEnabled;
    }
```

- [ ] **Step 5: Add the toggle to the layout popup**

In `layoutPopup`, inside the `ColumnLayout`, after the cards-per-row `RowLayout` closes (the block ending around line 828) and before the `ColumnLayout` closes:

```qml
            Rectangle { Layout.fillWidth: true; height: 1; color: Theme.divider }

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spacingMedium

                Text {
                    Layout.fillWidth: true
                    text: Theme.tr("Prioritize books")
                    color: Theme.textOnSurface
                    font.pixelSize: Theme.fontSizeMedium
                }

                Switch {
                    checked: bookListPage.priorityEnabled
                    Material.accent: Theme.primary
                    onToggled: bookListPage.priorityEnabled = checked
                }
            }
```

- [ ] **Step 6: Add the settings alias**

In `qml/Main.qml`, in the `Settings` block:

```qml
    Settings {
        id: appSettings
        property alias style: root.appStyle
        property alias language: root.appLanguage
        property alias cardsPerRow: root.libraryCardsPerRow
        property alias priorityEnabled: root.libraryPriorityEnabled
    }
```

- [ ] **Step 7: Add the backing property**

In `qml/Main.qml`, next to `libraryCardsPerRow` (around line 442):

```qml
    property int libraryCardsPerRow: 6  // default: 6 cards per row (0 = auto)
    property bool libraryPriorityEnabled: true  // default: priority hoisting on
```

- [ ] **Step 8: Bind it into the view**

In `qml/Main.qml`, in the `BookListView` block (around line 402):

```qml
        BookListView {
            userCardsPerRow: root.libraryCardsPerRow
            onUserCardsPerRowChanged: root.libraryCardsPerRow = userCardsPerRow
            priorityEnabled: root.libraryPriorityEnabled
            onPriorityEnabledChanged: root.libraryPriorityEnabled = priorityEnabled
```

- [ ] **Step 9: Rebuild and run**

Run the **Rebuild** command, then run the app.

Expected, using the book flagged in Task 3:
1. It sits first in the grid with an orange border.
2. Hovering it turns the border to its status colour; leaving restores orange.
3. Open the Layout popup (the button left of the + button) — the "Prioritize books" switch is on.
4. Turn it off — the book drops back to its normal position, **border still orange**.
5. Close and reopen the app — the switch is still off and the book is still unhoisted.
6. Turn it back on — the book returns to the front.

- [ ] **Step 10: Commit**

```bash
git add qml/components/BookListView.qml qml/Main.qml
git commit -m "feat: wire priority into library view with persisted toggle"
```

---

### Task 6: Priority checkbox in the book form

**Files:**
- Modify: `qml/components/BookForm.qml`

- [ ] **Step 1: Add the checkbox**

In `qml/components/BookForm.qml`, in the `RowLayout` holding `nonFictionCheck` (around line 553), append this after the existing `Text`, inside the same `RowLayout`:

```qml
                            Item { Layout.fillWidth: true }

                            CheckBox {
                                id: priorityCheck
                                Material.accent: Theme.priority
                            }

                            Text {
                                text: Theme.tr("Priority")
                                color: Theme.textOnSurface
                                font.pixelSize: Theme.fontSizeMedium

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: priorityCheck.checked = !priorityCheck.checked
                                }
                            }
```

- [ ] **Step 2: Load the value when editing**

Around line 145, after the `nonFictionCheck` line:

```qml
            nonFictionCheck.checked = editData.isNonFiction || false;
            priorityCheck.checked = editData.isPriority || false;
```

- [ ] **Step 3: Include it in the saved data**

Around line 243, after the `isNonFiction` entry:

```qml
            isNonFiction:    nonFictionCheck.checked,
            isPriority:      priorityCheck.checked,
```

- [ ] **Step 4: Reset it in `clearForm()`**

Around line 267, after the `nonFictionCheck` reset:

```qml
        nonFictionCheck.checked = false;
        priorityCheck.checked = false;
```

- [ ] **Step 5: Rebuild and run**

Run the **Rebuild** command, then run the app.

Expected:
1. Right-click any unflagged book → Edit. The dialog shows an unchecked "Priority" checkbox next to the technical-book checkbox.
2. Check it, save. The card gains an orange border and jumps to the front of the grid.
3. Right-click it → Edit again. The checkbox is checked — the value round-tripped through the database.
4. Uncheck it, save. The border clears and the card returns to its normal position.
5. Click + to add a new book. The Priority checkbox is unchecked, not carrying state from the previous edit.

- [ ] **Step 6: Commit**

```bash
git add qml/components/BookForm.qml
git commit -m "feat: add priority checkbox to book form"
```

---

### Task 7: CSV export and import

**Files:**
- Modify: `src/controllers/bookcontroller.cpp`

The new field is appended **after** `tags`, which is currently last. Appending anywhere else would shift the positional indices the importer relies on and silently corrupt existing files.

- [ ] **Step 1: Add the export header column**

In `exportToCsv()`, extend the header line:

```cpp
    out << "title,author,genre,page_count,start_date,end_date,rating,status,"
           "notes,isbn,publisher,publication_year,language,item_type,is_non_fiction,audio_mode,current_page,tags,is_priority\n";
```

- [ ] **Step 2: Add the export value**

Change the last written field so `tags` is no longer the line terminator:

```cpp
            << escapeCsvField(book.tags.join(", ")) << ','
            << (book.isPriority ? "true" : "false") << '\n';
```

- [ ] **Step 3: Parse it on import**

In `importFromCsv()`, after the tags parsing block and before the `if (book.title.isEmpty() ...)` guard:

```cpp
        // is_priority at index 18 (if present) — absent in files exported before this column existed
        if (fields.size() >= 19)
            book.isPriority = fields[18].trimmed().toLower() == "true";
```

A missing column leaves the default `false`, so older CSV files still import.

- [ ] **Step 4: Rebuild**

Run the **Rebuild** command. Expected: `[100%] Built target BookWorm`.

- [ ] **Step 5: Verify the round trip**

Run the app. Ensure at least one book is flagged. Export via the sidebar export button to `~/Desktop/bw-test.csv`, then:

```bash
head -1 ~/Desktop/bw-test.csv | tr ',' '\n' | tail -1
grep -c ',true$' ~/Desktop/bw-test.csv
```

Expected: first command prints `is_priority`; second prints the number of books you flagged (at least `1`).

Now import that same file back through the sidebar import button. Expected: the imported duplicate books carry the orange border on the same titles that had it before.

Clean up the duplicates afterwards:

```bash
psql -d wormbook -c "DELETE FROM books a USING books b WHERE a.id > b.id AND a.title = b.title AND a.author = b.author"
```

- [ ] **Step 6: Commit**

```bash
git add src/controllers/bookcontroller.cpp
git commit -m "feat: round-trip priority flag through CSV"
```

---

### Task 8: Translations and documentation

**Files:**
- Modify: `qml/theme/translations.js`
- Modify: `CLAUDE.md`

- [ ] **Step 1: Add the Polish strings**

In `qml/theme/translations.js`, add to the `_pl` object:

```javascript
    "Priority": "Priorytet",
    "Prioritize books": "Priorytetyzuj książki",
```

- [ ] **Step 2: Rebuild and verify both languages**

Run the **Rebuild** command, then run the app.

Expected: with Polish selected in settings, the form checkbox reads "Priorytet" and the layout popup switch reads "Priorytetyzuj książki". Switch to English — they read "Priority" and "Prioritize books". No key appears as raw untranslated text in Polish mode.

- [ ] **Step 3: Update the counts in CLAUDE.md**

Three edits, since the field and role counts are stated in several places:

- In the **C++ Layer** section, `Book` — change "23 fields" to "24 fields".
- In the same section, `BookModel` — change "22 roles (IdRole through TagsRole)" to "23 roles (IdRole through IsPriorityRole)".
- Change the heading `## Book Fields (23)` to `## Book Fields (24)` and append `isPriority` to the field list at the end.

- [ ] **Step 4: Document the feature**

In the **Database Schema** section, add `is_priority` to the migrations list. In **App Features**, add:

```markdown
- Priority flag: hoists flagged books to the front of the Library grid (default sort only), orange card border, toggle in Layout popup (persisted)
```

- [ ] **Step 5: Commit**

`CLAUDE.md` is in `.gitignore`, so only the translations file is tracked:

```bash
git add qml/theme/translations.js
git commit -m "feat: add Polish translations for priority feature"
```

---

## Final Verification

Run through the spec's verification list end to end on a fresh launch:

- [ ] Flag a planned book — it leads the grid, ahead of books in progress, with an orange border.
- [ ] Flag several books across different statuses — within the leading group they order by status, then completion %, then date, then author.
- [ ] Switch sort to "Title A→Z" — order is purely alphabetical; borders remain.
- [ ] Turn the toggle off — order matches pre-feature behaviour; borders remain.
- [ ] Restart the app — the toggle state persists.
- [ ] Export to CSV and re-import — flags are preserved.
- [ ] Hover a flagged card — border switches to the status colour, then back on exit.
- [ ] Switch through all three themes — the orange stays legible on each.
