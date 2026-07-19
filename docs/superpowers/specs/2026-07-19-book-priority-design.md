# Book Priority Flag — Design

Date: 2026-07-19
Status: Approved

## Problem

There is no way to mark a small set of books as "what I am focusing on right now".
Status alone does not express this: a planned book can matter more than a book
already in progress, and the Library grid gives both the same weight.

## Solution Overview

A per-book boolean `isPriority` flag. Flagged books are hoisted to the front of the
Library grid in default sort order and carry an orange border on their card. A view
setting turns the hoisting off without clearing any flags.

## Scope Decisions

Resolved during brainstorming:

| Question | Decision |
| --- | --- |
| Flag or levels? | Boolean flag, on/off. |
| Dedicated section in the grid? | No. Hoisting via sort order only — same mechanism the status grouping already uses. The Library is a flat `GridView`; the horizontal lines are per-row separators, not section headers. |
| Priority vs status ordering | Priority outranks status. Flagged books lead the list regardless of status. |
| Ordering inside the priority group | Unchanged existing rules: status rank → completion % → date → author. |
| Other sort modes (title, rating, pages…) | Priority is ignored. Explicit sorts stay pure. Border still renders. |
| Toggle semantics | Disables hoisting only. Nothing is hidden or removed. |
| Border when hoisting is off | Border stays. The flag remains visible; only ordering reverts. |
| Status restrictions | None. Any status can be flagged, including `read`. |
| Table view | Out of scope. It has its own per-column sorting. |

## Data Layer

**Migration** — `DatabaseManager::initializeSchema()`, following the existing
idempotent pattern:

```sql
ALTER TABLE books ADD COLUMN IF NOT EXISTS is_priority BOOLEAN DEFAULT FALSE
```

**`Book` struct** — new field `bool isPriority = false`, wired through
`toVariantMap()`, `fromVariantMap()`, and `fromSqlRecord()`. Book field count
goes 23 → 24.

**`BookModel`** — new role `IsPriorityRole`, appended after `TagsRole` so existing
role values do not shift. Add to `roleNames()` and `data()`. Role count 22 → 23.

**`DatabaseManager`** — `is_priority` added to the INSERT and UPDATE statements.

## Sorting

In `BookController::sortBooks()`, in the `default` branch only, as the first
comparison in the lambda:

```cpp
if (a.isPriority != b.isPriority) return a.isPriority;
```

Everything after it is unchanged, so the existing rules apply within each of the
two groups. No other sort mode is touched.

Guarded by a new `BookController` property `priorityEnabled` (bool, default true).
When false the comparison is skipped and ordering matches current behaviour exactly.
Changing it re-runs `applyFilters()`.

## UI

**`BookForm`** — a `Switch` labelled "Priority", placed in the same group as the
existing non-fiction switch. Reuses that row's layout rather than adding a new one.

**View toggle** — lives in `layoutPopup` (behind the Layout button in
`BookListView`), alongside the cards-per-row control. It is a view setting, not a
content filter, so it belongs with layout rather than on the filter bar — which
already carries search, year, year mode, sort, five status chips, and two buttons.

**Persistence** — `QSettings` via the project's established pattern: property on
`root` in `Main.qml`, `property alias` inside `Settings {}`, bound down into
`BookListView`, `onChanged` writing back to `bookController.priorityEnabled`.

## Visuals

**Theme token** — new `Theme.priority`, an orange defined separately for each of
the three themes so it stays legible in `minimalist_light`.

**`BookCard`** — the existing hover border overlay gains a resting state:

```qml
border.color: mouseArea.containsMouse ? Theme.statusColor(card.status)
            : (card.isPriority ? Theme.priority : "transparent")
```

Hover behaviour is unchanged; the existing `Behavior on border.color` animates the
transition. The card needs a new `isPriority` property, and the `BookListView`
delegate needs `required property bool isPriority` — an omitted `required property`
silently breaks the binding.

## CSV

`is_priority` is added to both export and import so the flag survives a round trip.
Import treats a missing column as `false`, keeping older CSV files loadable.

## Translations

Two keys added to the `_pl` object in `translations.js`:

- `"Priority"` → `"Priorytet"`
- `"Prioritize books"` → `"Priorytetyzuj książki"`

## Verification

1. Flag a planned book — it moves to the front of the Library grid, ahead of books
   in progress, with an orange border.
2. Flag several books across different statuses — within the leading group they
   order by status, then completion %, then date, then author.
3. Switch sort to "Title A→Z" — order is purely alphabetical; borders remain.
4. Turn the toggle off — order matches pre-feature behaviour; borders remain.
5. Restart the app — the toggle state persists.
6. Export to CSV and re-import — flags are preserved.
7. Hover a flagged card — border switches to the status colour, then back on exit.

## Out of Scope

- Priority levels or ranking beyond the boolean.
- A dedicated grid section with its own header.
- Priority in the Table view.
- Priority as a chip on the status filter bar.
