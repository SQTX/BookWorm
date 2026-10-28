#pragma once

#include <QString>
#include <QVector>

/**
 * What can be earned, and what it takes.
 *
 * The catalogue is data rather than code on purpose: adding an achievement
 * should be one line, and every one of them then behaves identically — the same
 * progress arithmetic, the same unlock rule, the same row in the browse view.
 * A family of five thresholds on one metric costs five lines, not five
 * functions.
 *
 * Titles and descriptions are English strings used verbatim as translation
 * keys, which is the convention the rest of the application follows: QML passes
 * them through `Theme.tr()`, which returns Polish when the language is Polish
 * and the key itself otherwise. Keeping them here rather than in QML means the
 * catalogue is one list rather than a list and a parallel table that can drift
 * out of step with it.
 */
namespace BookWorm::Achievements {

/**
 * The quantities achievements are measured against.
 *
 * Every one is a plain count that only ever grows, which is what makes the
 * unlock rule safe: an achievement earned cannot be un-earned by deleting a
 * book, because the row recording it is already written and nothing removes it.
 * A metric that could fall — "books currently reading", say — would need a rule
 * for taking an achievement away again, and taking one away is not something
 * this should ever do.
 */
enum class Metric {
    LibrarySize,        ///< Books on the shelf, whatever their status.
    BooksRead,          ///< Distinct books finished.
    BooksReadThisYear,  ///< Finished with an end date inside the current year.
    PagesRead,          ///< Pages in the books that were finished.
    SeriesCompleted,    ///< Multi-book series with every part read.
    GenresRead,         ///< Distinct genres among finished books.
    LongestStreak,      ///< Longest run of consecutive days with a reading session.
    Rereads,            ///< Times a book was finished again after the first.
    BooksRated,         ///< Finished books carrying a rating.
    NotesTaken,         ///< Quotes and highlights, together.
};

struct Definition {
    QString key;         ///< Stable identifier. Stored; never change one.
    Metric metric;
    int threshold;       ///< The value at which it unlocks.
    QString title;       ///< English, and the translation key.
    QString description; ///< English, and the translation key.
    QString icon;        ///< qrc path.
};

/** The whole catalogue, in the order the browse view shows it. */
const QVector<Definition> &catalog();

} // namespace BookWorm::Achievements
