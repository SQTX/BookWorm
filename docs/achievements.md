# Achievements

Every achievement in BookWorm, with the name it shows in both languages, the rule
that unlocks it, and the filename its artwork has to take.

**Generated, not written by hand.** Run
`python3 desktop/tools/gen-achievement-docs.py` after changing the catalogue. The
definitions live in
[`desktop/src/achievements/achievementcatalog.cpp`](../desktop/src/achievements/achievementcatalog.cpp)
and the Polish strings in
[`desktop/qml/theme/translations.js`](../desktop/qml/theme/translations.js).

39 achievements across 9 families. Artwork prompts for all of them are in
[`achievement-icon-prompts.md`](achievement-icon-prompts.md).

## Artwork specification

| | |
| --- | --- |
| Format | PNG with transparency |
| Source size | 256 x 256 |
| Displayed at | 56 x 56, in both the notification panel and the list |
| Corners | square — the app rounds and crops |
| Filename | exactly the `Filename` column below |
| Location | `desktop/src/img/achievements/` |

Two constraints that decide how the art should be drawn:

- The icon sits on **whichever of three themes the user picked** — minimalist dark,
  minimalist light, or classic. A shape that relies on a pale background disappears in
  one of them.
- A locked achievement shows the **same artwork at 28% opacity**, not a different
  picture. The silhouette has to stay recognisable when it is barely there.

Both argue for solid shapes over fine linework.

## Wiring one up

1. Drop the PNG into `desktop/src/img/achievements/`.
2. Add it to `RESOURCES` in `desktop/CMakeLists.txt`. A file on disk but missing from
   that list is not compiled into the `qrc:` and is **silently absent** at runtime — no
   error, no picture.
3. In `achievementcatalog.cpp`, replace that row's `PLACEHOLDER` with
   `QStringLiteral("qrc:/qt/qml/BookWorm/src/img/achievements/<key>.png")`.
4. Reconfigure CMake — the resource list changed — then rebuild.

**Partial sets are fine.** Every definition points at the placeholder today, so icons can
land one at a time; an achievement without its own artwork keeps showing the placeholder
rather than breaking.

---

## The shelf

Owning, not reading — these fire on acquisition, so they are the first thing a new user meets.

- `LibrarySize` — Books in the library, whatever their status.

| Filename | Title | Tytuł | Description | Opis | Target |
| --- | --- | --- | --- | --- | ---: |
| `library_10.png` | A Shelf Begins | Półka się zaczyna | Ten books in your library | Dziesięć książek w bibliotece | 10 |
| `library_25.png` | Filling Out | Zapełnia się | Twenty-five books in your library | Dwadzieścia pięć książek w bibliotece | 25 |
| `library_50.png` | A Proper Collection | Prawdziwa kolekcja | Fifty books in your library | Pięćdziesiąt książek w bibliotece | 50 |
| `library_100.png` | Private Library | Biblioteka domowa | A hundred books in your library | Sto książek w bibliotece | 100 |
| `library_250.png` | Wall to Wall | Od ściany do ściany | Two hundred and fifty books in your library | Dwieście pięćdziesiąt książek w bibliotece | 250 |
| `library_500.png` | You Need Another Room | Potrzebujesz kolejnego pokoju | Five hundred books in your library | Pięćset książek w bibliotece | 500 |
| `library_1000.png` | Load-Bearing | Ściana nośna | A thousand books in your library | Tysiąc książek w bibliotece | 1,000 |

## Books finished

The spine of the set. Seven steps from one book to two hundred and fifty.

- `BooksRead` — Books whose status is `read`.

| Filename | Title | Tytuł | Description | Opis | Target |
| --- | --- | --- | --- | --- | ---: |
| `read_1.png` | The First One | Pierwsza | Finish your first book | Skończ pierwszą książkę | 1 |
| `read_5.png` | Getting Somewhere | Coś się dzieje | Finish five books | Skończ pięć książek | 5 |
| `read_10.png` | Double Figures | Dwucyfrowo | Finish ten books | Skończ dziesięć książek | 10 |
| `read_25.png` | Well Read | Oczytany | Finish twenty-five books | Skończ dwadzieścia pięć książek | 25 |
| `read_50.png` | Half a Hundred | Pół setki | Finish fifty books | Skończ pięćdziesiąt książek | 50 |
| `read_100.png` | Centurion | Centurion | Finish a hundred books | Skończ sto książek | 100 |
| `read_250.png` | Bookworm | Mól książkowy | Finish two hundred and fifty books | Skończ dwieście pięćdziesiąt książek | 250 |
| `read_500.png` | Half a Thousand | Pół tysiąca | Finish five hundred books | Skończ pięćset książek | 500 |
| `read_1000.png` | A Life in Books | Życie w książkach | Finish a thousand books | Skończ tysiąc książek | 1,000 |
| `read_10000.png` | Statistically Improbable | Statystycznie nieprawdopodobne | Finish ten thousand books | Skończ dziesięć tysięcy książek | 10,000 |

## Books finished this year

Resets every January. The only family that can become unreachable and come back.

- `BooksReadThisYear` — Finished with an end date inside the current calendar year.

| Filename | Title | Tytuł | Description | Opis | Target |
| --- | --- | --- | --- | --- | ---: |
| `year_12.png` | A Book a Month | Książka na miesiąc | Finish twelve books in one year | Skończ dwanaście książek w jednym roku | 12 |
| `year_24.png` | Two a Month | Dwie na miesiąc | Finish twenty-four books in one year | Skończ dwadzieścia cztery książki w jednym roku | 24 |
| `year_52.png` | A Book a Week | Książka na tydzień | Finish fifty-two books in one year | Skończ pięćdziesiąt dwie książki w jednym roku | 52 |

## Pages

Volume rather than count — a long book weighs more here than a short one.

- `PagesRead` — Page counts summed over finished books.

| Filename | Title | Tytuł | Description | Opis | Target |
| --- | --- | --- | --- | --- | ---: |
| `pages_1000.png` | A Thousand Pages | Tysiąc stron | Read a thousand pages | Przeczytaj tysiąc stron | 1,000 |
| `pages_10000.png` | Ten Thousand | Dziesięć tysięcy | Read ten thousand pages | Przeczytaj dziesięć tysięcy stron | 10,000 |
| `pages_50000.png` | Fifty Thousand | Pięćdziesiąt tysięcy | Read fifty thousand pages | Przeczytaj pięćdziesiąt tysięcy stron | 50,000 |
| `pages_100000.png` | Six Figures | Sześciocyfrowo | Read a hundred thousand pages | Przeczytaj sto tysięcy stron | 100,000 |

## Series

Completion. A series of one does not count.

- `SeriesCompleted` — Series of more than one book where every part is read.

| Filename | Title | Tytuł | Description | Opis | Target |
| --- | --- | --- | --- | --- | ---: |
| `series_1.png` | Saw It Through | Do samego końca | Finish every book in a series | Skończ wszystkie książki z jednej serii | 1 |
| `series_5.png` | Completionist | Kompletysta | Finish five series | Skończ pięć serii | 5 |
| `series_10.png` | No Loose Ends | Żadnych niedokończonych wątków | Finish ten series | Skończ dziesięć serii | 10 |

## Breadth

Range instead of depth, counted on distinct genres among finished books.

- `GenresRead` — Distinct genres among finished books.

| Filename | Title | Tytuł | Description | Opis | Target |
| --- | --- | --- | --- | --- | ---: |
| `genres_5.png` | Broadening Out | Poszerzanie horyzontów | Finish books in five genres | Skończ książki z pięciu gatunków | 5 |
| `genres_10.png` | Catholic Taste | Szerokie gusta | Finish books in ten genres | Skończ książki z dziesięciu gatunków | 10 |
| `genres_20.png` | Omnivore | Wszystkożerny | Finish books in twenty genres | Skończ książki z dwudziestu gatunków | 20 |

## Habit

Consecutive reading days, from a week to a full year.

- `LongestStreak` — Longest run of consecutive days carrying a reading session.

| Filename | Title | Tytuł | Description | Opis | Target |
| --- | --- | --- | --- | --- | ---: |
| `streak_7.png` | Seven Days | Siedem dni | Read on seven days in a row | Czytaj przez siedem dni z rzędu | 7 |
| `streak_30.png` | A Month Straight | Miesiąc bez przerwy | Read on thirty days in a row | Czytaj przez trzydzieści dni z rzędu | 30 |
| `streak_100.png` | A Hundred Days | Sto dni | Read on a hundred days in a row | Czytaj przez sto dni z rzędu | 100 |
| `streak_365.png` | Every Single Day | Każdego dnia | Read on three hundred and sixty-five days in a row | Czytaj przez trzysta sześćdziesiąt pięć dni z rzędu | 365 |

## Revisiting

Rereads. The rarest family in an ordinary library.

- `Rereads` — Every finish past the first, summed across the library.

| Filename | Title | Tytuł | Description | Opis | Target |
| --- | --- | --- | --- | --- | ---: |
| `reread_1.png` | Worth Another Look | Warto wrócić | Read a book for the second time | Przeczytaj książkę po raz drugi | 1 |
| `reread_5.png` | Old Friends | Starzy znajomi | Reread five times over your library | Przeczytaj ponownie pięć razy w całej bibliotece | 5 |

## Keeping records

Using the app's own apparatus — ratings, quotes, highlights.

- `BooksRated` — Finished books that carry a rating.
- `NotesTaken` — Favourite quotes and highlights, together.

| Filename | Title | Tytuł | Description | Opis | Target |
| --- | --- | --- | --- | --- | ---: |
| `rated_25.png` | An Opinion on Everything | Opinia o wszystkim | Rate twenty-five books you have finished | Oceń dwadzieścia pięć skończonych książek | 25 |
| `notes_10.png` | Marginalia | Notatki na marginesie | Save ten quotes or highlights | Zapisz dziesięć cytatów lub fragmentów | 10 |
| `notes_100.png` | The Commonplace Book | Sylwa | Save a hundred quotes or highlights | Zapisz sto cytatów lub fragmentów | 100 |
