<p align="center">
   <img src="./docs/img/sqtx_logo_v2.svg" width=200px>
</p>
<h1 align="center">BookWorm — Personal Library Manager</h1>
<p align="center">
  <img src="https://img.shields.io/badge/C++17-00599C?style=for-the-badge&logo=cplusplus&logoColor=white"/>
  <img src="https://img.shields.io/badge/QML-41CD52?style=for-the-badge&logo=qt&logoColor=white"/>
  <img src="https://img.shields.io/badge/Qt_6.10-41CD52?style=for-the-badge&logo=qt&logoColor=white"/>
  <img src="https://img.shields.io/badge/PostgreSQL-4169E1?style=for-the-badge&logo=postgresql&logoColor=white"/>
  <img src="https://img.shields.io/badge/CMake-064F8C?style=for-the-badge&logo=cmake&logoColor=white"/>
  <img src="https://img.shields.io/badge/macOS-000000?style=for-the-badge&logo=apple&logoColor=white"/>
</p>

---

## Description

A desktop application for tracking your personal book library — what you're reading, what you've read, and what you plan to read next. Built with **Qt 6 (C++ / QML)** and backed by **PostgreSQL**, BookWorm offers a dark Material-themed UI with multiple views, reading statistics, and full Polish/English localization.

**Keywords:** *book tracker, reading list, Qt6, QML, PostgreSQL, desktop app, dark theme*.

### Features

- **Three views**: Library (card grid), Table (spreadsheet), and Statistics (charts & analytics).
- **Book CRUD**: Add, edit, and delete books with cover images, ratings, genres, tags, and more.
- **Item types**: Book, article, newspaper, magazine, comic, manga, thesis, and other.
- **Reading progress**: Track current page with a visual progress bar for books in "reading" status.
- **Rating system**: 0–6 star rating (only available for finished books).
- **Tags & genres**: Color-coded tags with a dedicated management popup, genre categorization.
- **Favorite quotes**: Save quotes from books with page numbers.
- **Highlights & summaries**: Store important passages and book summaries.
- **Reading challenges**: Set time-bound reading goals and track completion.
- **Statistics dashboard**: Total books, pages read, average rating, genre distribution, monthly/yearly charts.
- **CSV import/export**: Migrate your data in and out.
- **Bilingual UI**: Full English and Polish translations with automatic system language detection.
- **Three themes**: Classic (warm dark), Minimalist Dark, and Minimalist Light.
- **Native macOS menu bar**: About dialog, CSV operations, language/theme switching via system menus.
- **Persistent settings**: Language, theme, and layout preferences saved between sessions.

## Technicalities

| Component | Details |
|---|---|
| **Language** | C++17 + QML |
| **Framework** | Qt 6.10.2 (Homebrew) |
| **Qt Modules** | Core, Sql, Qml, Quick, QuickControls2, Charts, ChartsQml, Widgets |
| **Database** | PostgreSQL 16+ |
| **Build system** | CMake 3.21+ |
| **Platform** | macOS (Apple Silicon / Intel) |
| **Theme** | Material Dark / Light |

### Architecture

```
User --> QML Signal --> BookController (Q_INVOKABLE) --> DatabaseManager --> PostgreSQL
                                                     |
                                       BookModel::setBooks() --> QML bindings --> UI
```

- **DatabaseManager** — Singleton. PostgreSQL connection, schema init with idempotent migrations, all CRUD operations.
- **Book** — Plain struct (19 fields), serialization via `toVariantMap()` / `fromVariantMap()`.
- **BookModel** — `QAbstractListModel` with 19 roles, registered as `QML_ELEMENT`.
- **BookController** — QML bridge: filtering, search, CSV import/export, tag/quote/challenge management.
- **StatisticsProvider** — Computes reading stats exposed as QML properties.
- **Theme.qml** — Singleton managing colors, fonts, spacing, and translations via `tr()` function.

### Project Structure

```
BookWorm/
├── CMakeLists.txt
├── README.md
├── qml/
│   ├── Main.qml                     # Root window, sidebar, navigation, menus, settings
│   ├── theme/
│   │   ├── Theme.qml                # Singleton — colors, fonts, spacing, i18n helpers
│   │   └── translations.js          # Polish translation dictionary (~200 entries)
│   └── components/
│       ├── BookCard.qml             # Card for grid view
│       ├── BookForm.qml             # Add/edit dialog
│       ├── BookDetails.qml          # Full detail view with quotes & highlights
│       ├── BookListView.qml         # Grid (Library) view
│       ├── BookTableView.qml        # Spreadsheet table view
│       ├── StatisticsView.qml       # Charts and statistics
│       └── ChallengesView.qml       # Reading challenges
├── src/
│   ├── main.cpp                     # Entry point, plugin paths, context properties
│   ├── constants.h                  # DB config, app info
│   ├── database/
│   │   └── databasemanager.h/.cpp   # Singleton PostgreSQL manager
│   ├── models/
│   │   ├── book.h/.cpp              # Book struct (19 fields)
│   │   └── bookmodel.h/.cpp         # QAbstractListModel
│   ├── controllers/
│   │   └── bookcontroller.h/.cpp    # QML bridge
│   ├── statistics/
│   │   └── statisticsprovider.h/.cpp
│   └── img/                         # SVG icons and PNG assets
├── sql/
│   └── init.sql                     # Reference database schema
└── docs/
    └── img/                         # README images
```

## Getting Started

### Prerequisites

- **macOS** with Homebrew
- **Qt 6.10+** (`brew install qt qtcharts qtdeclarative qtshadertools`)
- **PostgreSQL 16+** (`brew install postgresql@16`)
- **CMake 3.21+**

### Database Setup

```bash
# Start PostgreSQL
brew services start postgresql@16

# Create the database
createdb wormbook

# (Optional) Initialize schema from reference file
psql wormbook < sql/init.sql
```

> The app runs idempotent migrations on every launch, so manual schema init is optional.

### Build

```bash
mkdir -p build && cd build
cmake .. \
  -DCMAKE_PREFIX_PATH="/opt/homebrew/Cellar/qtbase/6.10.2;/opt/homebrew/Cellar/qtdeclarative/6.10.2;/opt/homebrew/Cellar/qtcharts/6.10.2;/opt/homebrew/Cellar/qtshadertools/6.10.2" \
  -DQt6Qml_DIR="/opt/homebrew/Cellar/qtdeclarative/6.10.2/lib/cmake/Qt6Qml" \
  -DQt6Quick_DIR="/opt/homebrew/Cellar/qtdeclarative/6.10.2/lib/cmake/Qt6Quick" \
  -DQt6QuickControls2_DIR="/opt/homebrew/Cellar/qtdeclarative/6.10.2/lib/cmake/Qt6QuickControls2" \
  -DQt6Charts_DIR="/opt/homebrew/Cellar/qtcharts/6.10.2/lib/cmake/Qt6Charts" \
  -DQt6ChartsQml_DIR="/opt/homebrew/Cellar/qtcharts/6.10.2/lib/cmake/Qt6ChartsQml" \
  -DCMAKE_BUILD_TYPE=Release -Wno-dev \
  && cmake --build . -j$(sysctl -n hw.ncpu)
```

### Run

```bash
./build/BookWorm.app/Contents/MacOS/BookWorm
```

## Screenshots

<!-- Add screenshots here -->
<!-- <p align="center">
   <img src="./docs/img/library_view.png" width=700px>
   <br>
   <b>Fig. 1</b> <i>Library view — card grid with status indicators</i>
</p> -->

## Author

**Jakub SQTX Sitarczyk**

Copyright &copy; 2024–2026. All rights reserved.
