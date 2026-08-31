#include "achievementcatalog.h"

namespace BookWorm::Achievements {

namespace {

/**
 * The one artwork every achievement currently uses.
 *
 * A placeholder, and deliberately a single shared one rather than a per-family
 * guess: the icons do not exist yet, and inventing paths for files nobody has
 * drawn would mean a browse view full of broken images. Giving each definition
 * its own filename here is the only change needed when the real artwork lands —
 * `src/img/achievements/` is where it goes, and the CMake RESOURCES list is the
 * other half of that (a file on disk but not listed there is silently absent at
 * runtime).
 */
const QString PLACEHOLDER =
    QStringLiteral("qrc:/qt/qml/BookWorm/src/img/achievements/placeholder.jpg");

} // namespace

const QVector<Definition> &catalog()
{
    // Function-local static: built once, on first use, after QString's own
    // initialisation is guaranteed to have happened. A namespace-scope QVector
    // of QStrings would depend on static initialisation order.
    static const QVector<Definition> entries = {
        // ── The shelf ────────────────────────────────────────────────────────
        { QStringLiteral("library_10"), Metric::LibrarySize, 10,
          QStringLiteral("A Shelf Begins"),
          QStringLiteral("Ten books in your library"), QStringLiteral("qrc:/qt/qml/BookWorm/src/img/achievements/library_10.png") },
        { QStringLiteral("library_25"), Metric::LibrarySize, 25,
          QStringLiteral("Filling Out"),
          QStringLiteral("Twenty-five books in your library"), QStringLiteral("qrc:/qt/qml/BookWorm/src/img/achievements/library_25.png") },
        { QStringLiteral("library_50"), Metric::LibrarySize, 50,
          QStringLiteral("A Proper Collection"),
          QStringLiteral("Fifty books in your library"), QStringLiteral("qrc:/qt/qml/BookWorm/src/img/achievements/library_50.png") },
        { QStringLiteral("library_100"), Metric::LibrarySize, 100,
          QStringLiteral("Private Library"),
          QStringLiteral("A hundred books in your library"), QStringLiteral("qrc:/qt/qml/BookWorm/src/img/achievements/library_100.png") },
        { QStringLiteral("library_250"), Metric::LibrarySize, 250,
          QStringLiteral("Wall to Wall"),
          QStringLiteral("Two hundred and fifty books in your library"), QStringLiteral("qrc:/qt/qml/BookWorm/src/img/achievements/library_250.png") },
        { QStringLiteral("library_500"), Metric::LibrarySize, 500,
          QStringLiteral("You Need Another Room"),
          QStringLiteral("Five hundred books in your library"), QStringLiteral("qrc:/qt/qml/BookWorm/src/img/achievements/library_500.png") },
        { QStringLiteral("library_1000"), Metric::LibrarySize, 1000,
          QStringLiteral("Load-Bearing"),
          QStringLiteral("A thousand books in your library"), QStringLiteral("qrc:/qt/qml/BookWorm/src/img/achievements/library_1000.png") },

        // ── Books finished ───────────────────────────────────────────────────
        { QStringLiteral("read_1"), Metric::BooksRead, 1,
          QStringLiteral("The First One"),
          QStringLiteral("Finish your first book"), QStringLiteral("qrc:/qt/qml/BookWorm/src/img/achievements/read_1.png") },
        { QStringLiteral("read_5"), Metric::BooksRead, 5,
          QStringLiteral("Getting Somewhere"),
          QStringLiteral("Finish five books"), QStringLiteral("qrc:/qt/qml/BookWorm/src/img/achievements/read_5.png") },
        { QStringLiteral("read_10"), Metric::BooksRead, 10,
          QStringLiteral("Double Figures"),
          QStringLiteral("Finish ten books"), QStringLiteral("qrc:/qt/qml/BookWorm/src/img/achievements/read_10.png") },
        { QStringLiteral("read_25"), Metric::BooksRead, 25,
          QStringLiteral("Well Read"),
          QStringLiteral("Finish twenty-five books"), QStringLiteral("qrc:/qt/qml/BookWorm/src/img/achievements/read_25.png") },
        { QStringLiteral("read_50"), Metric::BooksRead, 50,
          QStringLiteral("Half a Hundred"),
          QStringLiteral("Finish fifty books"), QStringLiteral("qrc:/qt/qml/BookWorm/src/img/achievements/read_50.png") },
        { QStringLiteral("read_100"), Metric::BooksRead, 100,
          QStringLiteral("Centurion"),
          QStringLiteral("Finish a hundred books"), QStringLiteral("qrc:/qt/qml/BookWorm/src/img/achievements/read_100.png") },
        { QStringLiteral("read_250"), Metric::BooksRead, 250,
          QStringLiteral("Bookworm"),
          QStringLiteral("Finish two hundred and fifty books"), QStringLiteral("qrc:/qt/qml/BookWorm/src/img/achievements/read_250.png") },

        // ── Books finished this year ─────────────────────────────────────────
        { QStringLiteral("year_12"), Metric::BooksReadThisYear, 12,
          QStringLiteral("A Book a Month"),
          QStringLiteral("Finish twelve books in one year"), PLACEHOLDER },
        { QStringLiteral("year_24"), Metric::BooksReadThisYear, 24,
          QStringLiteral("Two a Month"),
          QStringLiteral("Finish twenty-four books in one year"), PLACEHOLDER },
        { QStringLiteral("year_52"), Metric::BooksReadThisYear, 52,
          QStringLiteral("A Book a Week"),
          QStringLiteral("Finish fifty-two books in one year"), PLACEHOLDER },

        // ── Pages ────────────────────────────────────────────────────────────
        { QStringLiteral("pages_1000"), Metric::PagesRead, 1000,
          QStringLiteral("A Thousand Pages"),
          QStringLiteral("Read a thousand pages"), PLACEHOLDER },
        { QStringLiteral("pages_10000"), Metric::PagesRead, 10000,
          QStringLiteral("Ten Thousand"),
          QStringLiteral("Read ten thousand pages"), PLACEHOLDER },
        { QStringLiteral("pages_50000"), Metric::PagesRead, 50000,
          QStringLiteral("Fifty Thousand"),
          QStringLiteral("Read fifty thousand pages"), PLACEHOLDER },
        { QStringLiteral("pages_100000"), Metric::PagesRead, 100000,
          QStringLiteral("Six Figures"),
          QStringLiteral("Read a hundred thousand pages"), PLACEHOLDER },

        // ── Series ───────────────────────────────────────────────────────────
        { QStringLiteral("series_1"), Metric::SeriesCompleted, 1,
          QStringLiteral("Saw It Through"),
          QStringLiteral("Finish every book in a series"), PLACEHOLDER },
        { QStringLiteral("series_5"), Metric::SeriesCompleted, 5,
          QStringLiteral("Completionist"),
          QStringLiteral("Finish five series"), PLACEHOLDER },
        { QStringLiteral("series_10"), Metric::SeriesCompleted, 10,
          QStringLiteral("No Loose Ends"),
          QStringLiteral("Finish ten series"), PLACEHOLDER },

        // ── Breadth ──────────────────────────────────────────────────────────
        { QStringLiteral("genres_5"), Metric::GenresRead, 5,
          QStringLiteral("Broadening Out"),
          QStringLiteral("Finish books in five genres"), PLACEHOLDER },
        { QStringLiteral("genres_10"), Metric::GenresRead, 10,
          QStringLiteral("Catholic Taste"),
          QStringLiteral("Finish books in ten genres"), PLACEHOLDER },
        { QStringLiteral("genres_20"), Metric::GenresRead, 20,
          QStringLiteral("Omnivore"),
          QStringLiteral("Finish books in twenty genres"), PLACEHOLDER },

        // ── Habit ────────────────────────────────────────────────────────────
        { QStringLiteral("streak_7"), Metric::LongestStreak, 7,
          QStringLiteral("Seven Days"),
          QStringLiteral("Read on seven days in a row"), PLACEHOLDER },
        { QStringLiteral("streak_30"), Metric::LongestStreak, 30,
          QStringLiteral("A Month Straight"),
          QStringLiteral("Read on thirty days in a row"), PLACEHOLDER },
        { QStringLiteral("streak_100"), Metric::LongestStreak, 100,
          QStringLiteral("A Hundred Days"),
          QStringLiteral("Read on a hundred days in a row"), PLACEHOLDER },
        { QStringLiteral("streak_365"), Metric::LongestStreak, 365,
          QStringLiteral("Every Single Day"),
          QStringLiteral("Read on three hundred and sixty-five days in a row"), PLACEHOLDER },

        // ── Revisiting ───────────────────────────────────────────────────────
        { QStringLiteral("reread_1"), Metric::Rereads, 1,
          QStringLiteral("Worth Another Look"),
          QStringLiteral("Read a book for the second time"), PLACEHOLDER },
        { QStringLiteral("reread_5"), Metric::Rereads, 5,
          QStringLiteral("Old Friends"),
          QStringLiteral("Reread five times over your library"), PLACEHOLDER },

        // ── Keeping records ──────────────────────────────────────────────────
        { QStringLiteral("rated_25"), Metric::BooksRated, 25,
          QStringLiteral("An Opinion on Everything"),
          QStringLiteral("Rate twenty-five books you have finished"), PLACEHOLDER },
        { QStringLiteral("notes_10"), Metric::NotesTaken, 10,
          QStringLiteral("Marginalia"),
          QStringLiteral("Save ten quotes or highlights"), PLACEHOLDER },
        { QStringLiteral("notes_100"), Metric::NotesTaken, 100,
          QStringLiteral("The Commonplace Book"),
          QStringLiteral("Save a hundred quotes or highlights"), PLACEHOLDER },
    };

    return entries;
}

} // namespace BookWorm::Achievements
