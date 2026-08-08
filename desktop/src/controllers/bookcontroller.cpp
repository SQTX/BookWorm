#include "bookcontroller.h"
#include "../database/databasemanager.h"

#include <QFile>
#include <QTextStream>
#include <QDate>
#include <QUrl>
#include <QSet>
#include <QHash>
#include <algorithm>

BookController::BookController(QObject *parent)
    : QObject(parent)
    , m_model(new BookModel(this))
    , m_priorityModel(new BookModel(this))
    , m_standardModel(new BookModel(this))
    , m_readingModel(new BookModel(this))
    , m_plannedModel(new BookModel(this))
    , m_readModel(new BookModel(this))
    , m_abandonedModel(new BookModel(this))
{
}

BookModel *BookController::model() const
{
    return m_model;
}

BookModel *BookController::priorityModel() const
{
    return m_priorityModel;
}

BookModel *BookController::standardModel() const
{
    return m_standardModel;
}

BookModel *BookController::readingModel() const   { return m_readingModel; }
BookModel *BookController::plannedModel() const   { return m_plannedModel; }
BookModel *BookController::readModel() const      { return m_readModel; }
BookModel *BookController::abandonedModel() const { return m_abandonedModel; }

void BookController::loadBooks()
{
    m_allBooks = DatabaseManager::instance().fetchAllBooks();
    applyFilters();
}

bool BookController::addBook(const QVariantMap &bookData)
{
    Book book = Book::fromVariantMap(bookData);

    if (book.title.isEmpty() || book.author.isEmpty()) {
        emit errorOccurred("Title and author are required");
        return false;
    }

    int newId = DatabaseManager::instance().insertBook(book);
    if (newId < 0) {
        emit errorOccurred("Failed to add book");
        return false;
    }

    book.id = newId;

    if (!book.tags.isEmpty())
        DatabaseManager::instance().syncTagsForBook(newId, book.tags);

    m_allBooks.prepend(book);
    applyFilters();
    emit booksChanged();
    return true;
}

bool BookController::updateBook(const QVariantMap &bookData)
{
    Book book = Book::fromVariantMap(bookData);

    if (book.id < 0) {
        emit errorOccurred("Invalid book ID");
        return false;
    }

    if (book.title.isEmpty() || book.author.isEmpty()) {
        emit errorOccurred("Title and author are required");
        return false;
    }

    if (!DatabaseManager::instance().updateBook(book)) {
        emit errorOccurred("Failed to update book");
        return false;
    }

    DatabaseManager::instance().syncTagsForBook(book.id, book.tags);

    // Update local cache
    for (int i = 0; i < m_allBooks.size(); ++i) {
        if (m_allBooks[i].id == book.id) {
            m_allBooks[i] = book;
            break;
        }
    }

    applyFilters();
    emit booksChanged();
    return true;
}

bool BookController::deleteBook(int id)
{
    DatabaseManager &db = DatabaseManager::instance();

    // Snapshot everything before the delete — the FK cascade wipes tags, quotes,
    // highlights and sessions with the row, so undo must reconstruct them.
    auto existing = db.fetchBookById(id);
    if (existing.has_value()) {
        m_lastDeleted.valid      = true;
        m_lastDeleted.book       = existing.value();
        m_lastDeleted.quotes     = db.fetchQuotesForBook(id);
        m_lastDeleted.highlights = db.fetchHighlightsForBook(id);
        m_lastDeleted.sessions   = db.fetchSessionsForBookRaw(id);
    } else {
        m_lastDeleted.valid = false;
    }

    if (!db.deleteBook(id)) {
        emit errorOccurred("Failed to delete book");
        m_lastDeleted.valid = false;
        return false;
    }

    m_allBooks.erase(
        std::remove_if(m_allBooks.begin(), m_allBooks.end(),
                        [id](const Book &b) { return b.id == id; }),
        m_allBooks.end()
    );

    applyFilters();
    emit booksChanged();
    if (m_lastDeleted.valid)
        emit bookDeletedUndoable(m_lastDeleted.book.title);
    return true;
}

bool BookController::undoDelete()
{
    if (!m_lastDeleted.valid)
        return false;

    DatabaseManager &db = DatabaseManager::instance();

    // Re-insert the book. It gets a fresh id (the old one is gone); children are
    // relinked to that new id below.
    Book book = m_lastDeleted.book;
    const int newId = db.insertBook(book);
    if (newId < 0) {
        emit errorOccurred("Failed to restore book");
        return false;
    }
    book.id = newId;

    if (!book.tags.isEmpty())
        db.syncTagsForBook(newId, book.tags);

    for (const QVariant &v : std::as_const(m_lastDeleted.quotes)) {
        const QVariantMap q = v.toMap();
        db.addQuote(newId, q.value("quote").toString(), q.value("page").toInt());
    }
    for (const QVariant &v : std::as_const(m_lastDeleted.highlights)) {
        const QVariantMap h = v.toMap();
        db.addHighlight(newId, h.value("title").toString(),
                        h.value("page").toInt(), h.value("note").toString());
    }
    for (const QVariant &v : std::as_const(m_lastDeleted.sessions)) {
        const QVariantMap s = v.toMap();
        db.restoreSession(newId, s.value("date").toDate(),
                          s.value("pageStart").toInt(), s.value("pageEnd").toInt(),
                          s.value("source").toString());
    }

    m_lastDeleted = DeletedSnapshot{};  // single-level undo — consume the snapshot

    m_allBooks.prepend(book);
    applyFilters();
    emit booksChanged();
    return true;
}

QVariantMap BookController::getBookDetails(int id)
{
    auto book = DatabaseManager::instance().fetchBookById(id);
    if (!book.has_value())
        return {};
    return book->toVariantMap();
}

bool BookController::updateReadingProgress(int bookId, int newCurrentPage)
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

    updateCachedBook(book);
    return true;
}

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
    // Each completion is one more read — this is the sole path that grows the tally,
    // so finishing a book again (after restarting it) records a reread.
    book.readCount = book.readCount + 1;

    // DatabaseManager::updateBook() is what BookController::updateReview() ultimately
    // delegates to (fetch -> set review -> updateBook); folding the review into this
    // same object/write avoids a second redundant round trip. Only touched when
    // non-empty, matching the old QML behavior of leaving the review untouched otherwise.
    const QString trimmedReview = review.trimmed();
    if (!trimmedReview.isEmpty())
        book.review = trimmedReview;

    if (!DatabaseManager::instance().updateBook(book)) {
        emit errorOccurred("Failed to update book");
        return false;
    }

    // Closing session, tagged separately so it does not distort pace averages.
    DatabaseManager::instance().recordSession(bookId, previousPage, book.pageCount,
                                              QStringLiteral("completion"));

    updateCachedBook(book);
    return true;
}

// Patch one book in the in-memory cache and refresh the views. Cheaper and more
// predictable than loadBooks(), which refetches everything and reorders m_allBooks
// by updated_at, quietly changing tie-breaks in the less specific sort modes.
void BookController::updateCachedBook(const Book &book)
{
    for (int i = 0; i < m_allBooks.size(); ++i) {
        if (m_allBooks[i].id == book.id) {
            m_allBooks[i] = book;
            break;
        }
    }

    applyFilters();
    emit booksChanged();
}

bool BookController::deleteReadingSession(int sessionId)
{
    return DatabaseManager::instance().deleteSession(sessionId);
}

QString BookController::updateReadingSession(int sessionId, const QString &isoDate, int pages)
{
    const QDate date = QDate::fromString(isoDate, Qt::ISODate);
    if (!date.isValid() || pages < 1)
        return QStringLiteral("Invalid session values");

    if (DatabaseManager::instance().sessionDateTaken(sessionId, date))
        return QStringLiteral("A session for that day already exists");

    if (!DatabaseManager::instance().updateSession(sessionId, date, pages))
        return QStringLiteral("Failed to update session");

    return QString();
}

QVariantMap BookController::getTypeDistribution()
{
    QVariantMap dist;
    for (const Book &book : m_allBooks) {
        QString type = book.itemType.isEmpty() ? QStringLiteral("book") : book.itemType;
        dist[type] = dist.value(type, 0).toInt() + 1;
    }
    return dist;
}

QVariantList BookController::getSeriesList()
{
    // Group books by series name, preserving first-seen order via a parallel list.
    QStringList order;
    QHash<QString, QVariantList> booksBySeries;
    QHash<QString, int> readCountBySeries;

    for (const Book &book : m_allBooks) {
        const QString series = book.series.trimmed();
        if (series.isEmpty())
            continue;

        if (!booksBySeries.contains(series)) {
            booksBySeries.insert(series, {});
            readCountBySeries.insert(series, 0);
            order.append(series);
        }

        QVariantMap b;
        b["id"]             = book.id;
        b["title"]          = book.title;
        b["author"]         = book.author;
        b["status"]         = book.status;
        b["rating"]         = book.rating;
        b["coverImagePath"] = book.coverImagePath;
        booksBySeries[series].append(b);

        if (book.status == QStringLiteral("read"))
            readCountBySeries[series] += 1;
    }

    QVariantList result;
    for (const QString &name : std::as_const(order)) {
        const QVariantList &books = booksBySeries[name];
        QVariantMap entry;
        entry["name"]  = name;
        entry["total"] = books.size();
        entry["read"]  = readCountBySeries[name];
        entry["books"] = books;
        result.append(entry);
    }

    // Longest series first, so the fuller ones lead.
    std::stable_sort(result.begin(), result.end(), [](const QVariant &a, const QVariant &b) {
        return a.toMap().value("total").toInt() > b.toMap().value("total").toInt();
    });
    return result;
}

QStringList BookController::getAllTags()
{
    return DatabaseManager::instance().fetchAllTags();
}

QVariantList BookController::getAllTagsWithColors()
{
    return DatabaseManager::instance().fetchAllTagsWithColors();
}

bool BookController::addTag(const QString &name, const QString &color)
{
    if (name.trimmed().isEmpty())
        return false;
    return DatabaseManager::instance().addTagWithColor(name.trimmed(), color);
}

bool BookController::updateTag(int id, const QString &name, const QString &color)
{
    if (name.trimmed().isEmpty())
        return false;
    return DatabaseManager::instance().updateTag(id, name.trimmed(), color);
}

bool BookController::deleteTag(int id)
{
    bool ok = DatabaseManager::instance().deleteTag(id);
    if (ok) {
        // Refresh books since tags may have changed
        loadBooks();
    }
    return ok;
}

QVariantList BookController::getAvailableYears()
{
    return DatabaseManager::instance().getAvailableYears();
}

QStringList BookController::getAllGenres()
{
    QStringList genres;
    QSet<QString> seen;
    for (const Book &book : m_allBooks) {
        if (!book.genre.isEmpty() && !seen.contains(book.genre)) {
            seen.insert(book.genre);
            genres.append(book.genre);
        }
    }
    genres.sort();
    return genres;
}

QStringList BookController::getAllSeries()
{
    QStringList seriesList;
    QSet<QString> seen;
    for (const Book &book : m_allBooks) {
        if (!book.series.isEmpty() && !seen.contains(book.series)) {
            seen.insert(book.series);
            seriesList.append(book.series);
        }
    }
    seriesList.sort();
    return seriesList;
}

QStringList BookController::getAllAuthors()
{
    QStringList authors;
    QSet<QString> seen;
    for (const Book &book : m_allBooks) {
        if (!book.author.isEmpty() && !seen.contains(book.author)) {
            seen.insert(book.author);
            authors.append(book.author);
        }
    }
    authors.sort();
    return authors;
}

QStringList BookController::getAllPublishers()
{
    QStringList publishers;
    QSet<QString> seen;
    for (const Book &book : m_allBooks) {
        if (!book.publisher.isEmpty() && !seen.contains(book.publisher)) {
            seen.insert(book.publisher);
            publishers.append(book.publisher);
        }
    }
    publishers.sort();
    return publishers;
}

QStringList BookController::getSeriesForAuthor(const QString &author)
{
    QStringList seriesList;
    QSet<QString> seen;
    const QString trimmed = author.trimmed();
    for (const Book &book : m_allBooks) {
        if (book.author.compare(trimmed, Qt::CaseInsensitive) == 0
            && !book.series.isEmpty() && !seen.contains(book.series)) {
            seen.insert(book.series);
            seriesList.append(book.series);
        }
    }
    seriesList.sort();
    return seriesList;
}

QStringList BookController::getDefaultGenres()
{
    static const QStringList defaults = {
        QStringLiteral("Fantasy"),
        QStringLiteral("Science Fiction"),
        QStringLiteral("Mystery"),
        QStringLiteral("Thriller"),
        QStringLiteral("Horror"),
        QStringLiteral("Romance"),
        QStringLiteral("Historical Fiction"),
        QStringLiteral("Literary Fiction"),
        QStringLiteral("Contemporary Fiction"),
        QStringLiteral("Dystopian"),
        QStringLiteral("Adventure"),
        QStringLiteral("Crime"),
        QStringLiteral("Drama"),
        QStringLiteral("Young Adult"),
        QStringLiteral("Children's"),
        QStringLiteral("Biography"),
        QStringLiteral("Autobiography"),
        QStringLiteral("Memoir"),
        QStringLiteral("Self-Help"),
        QStringLiteral("Psychology"),
        QStringLiteral("Philosophy"),
        QStringLiteral("History"),
        QStringLiteral("Science"),
        QStringLiteral("Technology"),
        QStringLiteral("Programming"),
        QStringLiteral("Mathematics"),
        QStringLiteral("Business"),
        QStringLiteral("Economics"),
        QStringLiteral("Politics"),
        QStringLiteral("Sociology"),
        QStringLiteral("Travel"),
        QStringLiteral("Cooking"),
        QStringLiteral("Art"),
        QStringLiteral("Music"),
        QStringLiteral("Poetry"),
        QStringLiteral("Essay"),
        QStringLiteral("Journalism"),
        QStringLiteral("True Crime"),
        QStringLiteral("Graphic Novel"),
        QStringLiteral("Manga"),
        QStringLiteral("Comic"),
        QStringLiteral("Religion"),
        QStringLiteral("Spirituality"),
        QStringLiteral("Health"),
        QStringLiteral("Fitness"),
        QStringLiteral("Education"),
        QStringLiteral("Reference"),
        QStringLiteral("Humor"),
        QStringLiteral("Western"),
        QStringLiteral("Military"),
        QStringLiteral("Classics"),
        QStringLiteral("Fairy Tale"),
        QStringLiteral("Mythology"),
        QStringLiteral("Satire"),
        QStringLiteral("Anthology")
    };

    // Merge defaults with genres from existing books
    QSet<QString> all(defaults.begin(), defaults.end());
    for (const Book &book : m_allBooks) {
        if (!book.genre.isEmpty())
            all.insert(book.genre);
    }

    QStringList result(all.begin(), all.end());
    result.sort();
    return result;
}

bool BookController::addQuote(int bookId, const QString &quote, int page)
{
    return DatabaseManager::instance().addQuote(bookId, quote, page);
}

bool BookController::removeQuote(int quoteId)
{
    return DatabaseManager::instance().removeQuote(quoteId);
}

QVariantList BookController::getQuotesForBook(int bookId)
{
    return DatabaseManager::instance().fetchQuotesForBook(bookId);
}

// ─── Highlights ─────────────────────────────────────────────

bool BookController::addHighlight(int bookId, const QString &title, int page, const QString &note)
{
    if (title.trimmed().isEmpty()) {
        emit errorOccurred("Highlight title is required");
        return false;
    }
    return DatabaseManager::instance().addHighlight(bookId, title.trimmed(), page, note.trimmed());
}

bool BookController::removeHighlight(int highlightId)
{
    return DatabaseManager::instance().removeHighlight(highlightId);
}

QVariantList BookController::getHighlightsForBook(int bookId)
{
    return DatabaseManager::instance().fetchHighlightsForBook(bookId);
}

// ─── Summary / Review ───────────────────────────────────────

bool BookController::updateSummary(int bookId, const QString &summary)
{
    // Update only the summary field via a direct query
    auto optBook = DatabaseManager::instance().fetchBookById(bookId);
    if (!optBook) return false;
    Book book = *optBook;
    book.summary = summary.trimmed();
    bool ok = DatabaseManager::instance().updateBook(book);
    if (ok) {
        for (auto &b : m_allBooks) {
            if (b.id == bookId) { b.summary = book.summary; break; }
        }
    }
    return ok;
}

bool BookController::updateReview(int bookId, const QString &review)
{
    auto optBook = DatabaseManager::instance().fetchBookById(bookId);
    if (!optBook) return false;
    Book book = *optBook;
    book.review = review.trimmed();
    bool ok = DatabaseManager::instance().updateBook(book);
    if (ok) {
        for (auto &b : m_allBooks) {
            if (b.id == bookId) { b.review = book.review; break; }
        }
    }
    return ok;
}

// ─── Challenges ─────────────────────────────────────────────

QVariantList BookController::getChallenges()
{
    return DatabaseManager::instance().fetchAllChallenges();
}

bool BookController::addChallenge(const QString &name, const QString &metric, int targetValue,
                                  const QString &isoDeadline, const QString &periodUnit, int periodCount)
{
    static const QSet<QString> validMetrics = {
        QStringLiteral("books"), QStringLiteral("pages"), QStringLiteral("pages_per_day")
    };
    const QString m = validMetrics.contains(metric) ? metric : QStringLiteral("books");

    // Two ways to set the deadline: a period from today, or an explicit end date.
    QDate deadline;
    QString unit = periodUnit;
    if (periodCount > 0) {
        const QDate today = QDate::currentDate();
        if (periodUnit == QStringLiteral("day"))         deadline = today.addDays(periodCount);
        else if (periodUnit == QStringLiteral("month"))  deadline = today.addMonths(periodCount);
        else if (periodUnit == QStringLiteral("year"))   deadline = today.addYears(periodCount);
        else                                             deadline = today.addYears(periodCount);
    } else {
        deadline = QDate::fromString(isoDeadline, Qt::ISODate);
        unit = QStringLiteral("custom");
    }

    if (name.trimmed().isEmpty() || !deadline.isValid() || targetValue < 1
        || deadline < QDate::currentDate()) {
        emit errorOccurred("Invalid challenge data");
        return false;
    }

    int id = DatabaseManager::instance().insertChallenge(name.trimmed(), m, targetValue,
                                                         deadline, unit, periodCount);
    return id > 0;
}

bool BookController::deleteChallenge(int id)
{
    return DatabaseManager::instance().deleteChallenge(id);
}

QVariantList BookController::getBooksForChallenge(int challengeId)
{
    return DatabaseManager::instance().fetchBooksForChallenge(challengeId);
}

bool BookController::resetAllData()
{
    bool ok = DatabaseManager::instance().resetAllData();
    if (ok) {
        m_allBooks.clear();
        m_model->setBooks({});
        emit booksChanged();
    }
    return ok;
}

QString BookController::filterStatus() const
{
    return m_filterStatus;
}

void BookController::setFilterStatus(const QString &status)
{
    if (m_filterStatus != status) {
        m_filterStatus = status;
        emit filterStatusChanged();
        applyFilters();
    }
}

QString BookController::searchQuery() const
{
    return m_searchQuery;
}

void BookController::setSearchQuery(const QString &query)
{
    if (m_searchQuery != query) {
        m_searchQuery = query;
        emit searchQueryChanged();
        applyFilters();
    }
}

int BookController::filterYear() const
{
    return m_filterYear;
}

void BookController::setFilterYear(int year)
{
    if (m_filterYear != year) {
        m_filterYear = year;
        emit filterYearChanged();
        applyFilters();
    }
}

QString BookController::filterYearMode() const
{
    return m_filterYearMode;
}

void BookController::setFilterYearMode(const QString &mode)
{
    if (m_filterYearMode != mode) {
        m_filterYearMode = mode;
        emit filterYearModeChanged();
        applyFilters();
    }
}

QString BookController::sortMode() const
{
    return m_sortMode;
}

void BookController::setSortMode(const QString &mode)
{
    if (m_sortMode != mode) {
        m_sortMode = mode;
        emit sortModeChanged();
        applyFilters();
    }
}

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

int BookController::filterMinRating() const
{
    return m_filterMinRating;
}

void BookController::setFilterMinRating(int rating)
{
    if (m_filterMinRating != rating) {
        m_filterMinRating = rating;
        emit filterMinRatingChanged();
        applyFilters();
    }
}

QString BookController::filterTag() const
{
    return m_filterTag;
}

void BookController::setFilterTag(const QString &tag)
{
    if (m_filterTag != tag) {
        m_filterTag = tag;
        emit filterTagChanged();
        applyFilters();
    }
}

// ─── CSV helpers ────────────────────────────────────────────

static QString escapeCsvField(const QString &field)
{
    if (field.contains(',') || field.contains('"') || field.contains('\n')) {
        QString escaped = field;
        escaped.replace('"', "\"\"");
        return '"' + escaped + '"';
    }
    return field;
}

static QString parseCsvField(const QString &field)
{
    QString f = field.trimmed();
    if (f.startsWith('"') && f.endsWith('"')) {
        f = f.mid(1, f.length() - 2);
        f.replace("\"\"", "\"");
    }
    return f;
}

static QStringList splitCsvLine(const QString &line)
{
    QStringList fields;
    QString current;
    bool inQuotes = false;

    for (int i = 0; i < line.length(); ++i) {
        QChar c = line[i];
        if (c == '"') {
            if (inQuotes && i + 1 < line.length() && line[i + 1] == '"') {
                current += '"';
                ++i;
            } else {
                inQuotes = !inQuotes;
            }
        } else if (c == ',' && !inQuotes) {
            fields.append(current);
            current.clear();
        } else {
            current += c;
        }
    }
    fields.append(current);
    return fields;
}

bool BookController::exportToCsv(const QString &filePath)
{
    QString path = filePath;
    if (path.startsWith("file://"))
        path = QUrl(path).toLocalFile();

    QFile file(path);
    if (!file.open(QIODevice::WriteOnly | QIODevice::Text)) {
        emit errorOccurred("Cannot open file for writing: " + path);
        return false;
    }

    QTextStream out(&file);

    // Header
    out << "title,author,genre,page_count,start_date,end_date,rating,status,"
           "notes,isbn,publisher,publication_year,language,item_type,is_non_fiction,audio_mode,current_page,tags,is_priority\n";

    const auto allBooks = DatabaseManager::instance().fetchAllBooks();
    for (const Book &book : allBooks) {
        out << escapeCsvField(book.title) << ','
            << escapeCsvField(book.author) << ','
            << escapeCsvField(book.genre) << ','
            << book.pageCount << ','
            << (book.startDate.isValid() ? book.startDate.toString(Qt::ISODate) : QString()) << ','
            << (book.endDate.isValid() ? book.endDate.toString(Qt::ISODate) : QString()) << ','
            << book.rating << ','
            << escapeCsvField(book.status) << ','
            << escapeCsvField(book.notes) << ','
            << escapeCsvField(book.isbn) << ','
            << escapeCsvField(book.publisher) << ','
            << book.publicationYear << ','
            << escapeCsvField(book.language) << ','
            << escapeCsvField(book.itemType) << ','
            << (book.isNonFiction ? "true" : "false") << ','
            << escapeCsvField(book.audioMode) << ','
            << book.currentPage << ','
            << escapeCsvField(book.tags.join(", ")) << ','
            << (book.isPriority ? "true" : "false") << '\n';
    }

    file.close();
    return true;
}

// ─── Markdown notes export ──────────────────────────────────

// Build the Markdown for one book. Returns an empty string when the book has
// nothing worth exporting (no summary, review, notes, quotes or highlights), so
// the whole-library export can skip books that would otherwise be empty headers.
static QString buildBookMarkdown(const Book &book,
                                 const QVariantList &quotes,
                                 const QVariantList &highlights)
{
    const bool hasText = !book.summary.trimmed().isEmpty()
                         || !book.review.trimmed().isEmpty()
                         || !book.notes.trimmed().isEmpty();
    if (!hasText && quotes.isEmpty() && highlights.isEmpty())
        return QString();

    QString md;
    md += QStringLiteral("# %1\n").arg(book.title);
    md += QStringLiteral("*%1*").arg(book.author);
    if (!book.series.trimmed().isEmpty())
        md += QStringLiteral("  ·  %1").arg(book.series);
    md += QStringLiteral("\n\n");

    if (book.rating > 0)
        md += QStringLiteral("**Rating:** %1/6\n\n").arg(book.rating);

    if (!book.summary.trimmed().isEmpty())
        md += QStringLiteral("## Summary\n\n%1\n\n").arg(book.summary.trimmed());

    if (!book.review.trimmed().isEmpty())
        md += QStringLiteral("## Review\n\n%1\n\n").arg(book.review.trimmed());

    if (!book.notes.trimmed().isEmpty())
        md += QStringLiteral("## Notes\n\n%1\n\n").arg(book.notes.trimmed());

    if (!quotes.isEmpty()) {
        md += QStringLiteral("## Favorite quotes\n\n");
        for (const QVariant &v : quotes) {
            const QVariantMap q = v.toMap();
            const QString text = q.value("quote").toString().trimmed();
            const int page = q.value("page").toInt();
            // Prefix every line of the quote with "> " so multi-line quotes stay a blockquote.
            QString quoted = text;
            quoted.replace(QStringLiteral("\n"), QStringLiteral("\n> "));
            md += QStringLiteral("> %1\n").arg(quoted);
            if (page > 0)
                md += QStringLiteral(">\n> — p. %1\n").arg(page);
            md += QStringLiteral("\n");
        }
    }

    if (!highlights.isEmpty()) {
        md += QStringLiteral("## Highlights\n\n");
        for (const QVariant &v : highlights) {
            const QVariantMap h = v.toMap();
            const QString title = h.value("title").toString().trimmed();
            const int page = h.value("page").toInt();
            const QString note = h.value("note").toString().trimmed();
            md += QStringLiteral("### %1").arg(title.isEmpty() ? QStringLiteral("—") : title);
            if (page > 0)
                md += QStringLiteral(" (p. %1)").arg(page);
            md += QStringLiteral("\n\n");
            if (!note.isEmpty())
                md += QStringLiteral("%1\n\n").arg(note);
        }
    }

    return md;
}

bool BookController::exportBookNotesToMarkdown(int bookId, const QString &filePath)
{
    QString path = filePath;
    if (path.startsWith("file://"))
        path = QUrl(path).toLocalFile();

    auto existing = DatabaseManager::instance().fetchBookById(bookId);
    if (!existing.has_value()) {
        emit errorOccurred("Book not found");
        return false;
    }

    DatabaseManager &db = DatabaseManager::instance();
    const QString md = buildBookMarkdown(existing.value(),
                                         db.fetchQuotesForBook(bookId),
                                         db.fetchHighlightsForBook(bookId));

    QFile file(path);
    if (!file.open(QIODevice::WriteOnly | QIODevice::Text)) {
        emit errorOccurred("Cannot open file for writing: " + path);
        return false;
    }
    QTextStream out(&file);
    // A book with no notes still produces a minimal file rather than a silent no-op.
    out << (md.isEmpty() ? QStringLiteral("# %1\n\n*%2*\n\n_(no notes)_\n")
                               .arg(existing->title, existing->author)
                         : md);
    file.close();
    return true;
}

int BookController::exportAllNotesToMarkdown(const QString &filePath)
{
    QString path = filePath;
    if (path.startsWith("file://"))
        path = QUrl(path).toLocalFile();

    QFile file(path);
    if (!file.open(QIODevice::WriteOnly | QIODevice::Text)) {
        emit errorOccurred("Cannot open file for writing: " + path);
        return -1;
    }

    QTextStream out(&file);
    out << QStringLiteral("# Reading notes\n\n");

    DatabaseManager &db = DatabaseManager::instance();
    const auto allBooks = db.fetchAllBooks();
    int written = 0;
    for (const Book &book : allBooks) {
        const QString md = buildBookMarkdown(book,
                                             db.fetchQuotesForBook(book.id),
                                             db.fetchHighlightsForBook(book.id));
        if (md.isEmpty())
            continue;  // skip books with nothing to export
        if (written > 0)
            out << QStringLiteral("\n---\n\n");
        out << md;
        ++written;
    }
    file.close();
    return written;
}

int BookController::importFromCsv(const QString &filePath)
{
    QString path = filePath;
    if (path.startsWith("file://"))
        path = QUrl(path).toLocalFile();

    QFile file(path);
    if (!file.open(QIODevice::ReadOnly | QIODevice::Text)) {
        emit errorOccurred("Cannot open file for reading: " + path);
        return -1;
    }

    QTextStream in(&file);

    // Skip header line
    if (!in.atEnd())
        in.readLine();

    int imported = 0;
    auto &db = DatabaseManager::instance();

    while (!in.atEnd()) {
        const QString line = in.readLine().trimmed();
        if (line.isEmpty())
            continue;

        QStringList fields = splitCsvLine(line);
        if (fields.size() < 16)
            continue;

        Book book;
        book.title           = parseCsvField(fields[0]);
        book.author          = parseCsvField(fields[1]);
        book.genre           = parseCsvField(fields[2]);
        book.pageCount       = fields[3].trimmed().toInt();
        book.startDate       = QDate::fromString(fields[4].trimmed(), Qt::ISODate);
        book.endDate         = QDate::fromString(fields[5].trimmed(), Qt::ISODate);
        book.rating          = fields[6].trimmed().toInt();
        book.status          = parseCsvField(fields[7]);
        book.notes           = parseCsvField(fields[8]);
        book.isbn            = parseCsvField(fields[9]);
        book.publisher       = parseCsvField(fields[10]);
        book.publicationYear = fields[11].trimmed().toInt();
        book.language        = parseCsvField(fields[12]);
        book.itemType        = parseCsvField(fields[13]);
        book.isNonFiction    = fields[14].trimmed().toLower() == "true";
        // audio_mode at index 15 (if present)
        if (fields.size() >= 16) {
            book.audioMode = parseCsvField(fields[15]);
            if (book.audioMode.isEmpty()) book.audioMode = QStringLiteral("none");
        }
        // current_page at index 16 (if present), tags at 17
        if (fields.size() >= 18) {
            book.currentPage = fields[16].trimmed().toInt();
        }

        const QString tagsStr = parseCsvField(fields.size() >= 18 ? fields[17] : (fields.size() >= 17 ? fields[16] : fields[15]));
        if (!tagsStr.isEmpty()) {
            const auto parts = tagsStr.split(',');
            for (const auto &part : parts) {
                const QString trimmed = part.trimmed();
                if (!trimmed.isEmpty())
                    book.tags.append(trimmed);
            }
        }

        // is_priority at index 18 (if present) — absent in files exported before this column existed
        if (fields.size() >= 19)
            book.isPriority = fields[18].trimmed().toLower() == "true";

        if (book.title.isEmpty() || book.author.isEmpty())
            continue;

        if (book.status.isEmpty())
            book.status = QStringLiteral("planned");

        int newId = db.insertBook(book);
        if (newId > 0) {
            if (!book.tags.isEmpty())
                db.syncTagsForBook(newId, book.tags);
            ++imported;
        }
    }

    file.close();

    if (imported > 0) {
        loadBooks();
        emit booksChanged();
    }

    return imported;
}

void BookController::applyFilters()
{
    QVector<Book> filtered;

    for (const Book &book : m_allBooks) {
        // Status filter
        if (!m_filterStatus.isEmpty() && book.status != m_filterStatus)
            continue;

        // Search filter (title + author)
        if (!m_searchQuery.isEmpty()) {
            const QString query = m_searchQuery.toLower();
            if (!book.title.toLower().contains(query) &&
                !book.author.toLower().contains(query))
                continue;
        }

        // Year filter
        if (m_filterYear > 0) {
            if (m_filterYearMode == QStringLiteral("start")) {
                if (!book.startDate.isValid() || book.startDate.year() != m_filterYear)
                    continue;
            } else {
                if (!book.endDate.isValid() || book.endDate.year() != m_filterYear)
                    continue;
            }
        }

        // Minimum-rating filter (Table view)
        if (m_filterMinRating > 0 && book.rating < m_filterMinRating)
            continue;

        // Tag filter (Table view)
        if (!m_filterTag.isEmpty() && !book.tags.contains(m_filterTag))
            continue;

        filtered.append(book);
    }

    sortBooks(filtered);

    // `model` always holds every filtered book — the Table view and anything else
    // that wants the whole list reads it. The Library grid instead reads the two
    // split models below, so flagged books can render in their own section.
    m_model->setBooks(filtered);

    // Grouping (priority split + per-status sections) applies only to the default
    // sort. An explicit sort is an ordering the user asked for, so it stays one flat
    // list in m_standardModel with every section model emptied.
    const bool grouped = (m_sortMode == QStringLiteral("default"));

    if (grouped) {
        QVector<Book> prioritized;
        QVector<Book> standard;
        if (m_priorityEnabled) {
            for (const Book &book : filtered) {
                if (book.isPriority)
                    prioritized.append(book);
                else
                    standard.append(book);
            }
        } else {
            standard = filtered;
        }
        m_priorityModel->setBooks(prioritized);

        // Partition the non-priority remainder into one model per status. Each keeps
        // the already-applied default ordering, so sections stay internally sorted.
        QVector<Book> reading, planned, read, abandoned;
        for (const Book &book : standard) {
            if (book.status == QStringLiteral("reading"))        reading.append(book);
            else if (book.status == QStringLiteral("planned"))   planned.append(book);
            else if (book.status == QStringLiteral("read"))      read.append(book);
            else if (book.status == QStringLiteral("abandoned")) abandoned.append(book);
            else                                                 read.append(book);
        }
        m_readingModel->setBooks(reading);
        m_plannedModel->setBooks(planned);
        m_readModel->setBooks(read);
        m_abandonedModel->setBooks(abandoned);

        // Sections carry the books now; the flat grid stays empty.
        m_standardModel->setBooks({});
    } else {
        m_priorityModel->setBooks({});
        m_readingModel->setBooks({});
        m_plannedModel->setBooks({});
        m_readModel->setBooks({});
        m_abandonedModel->setBooks({});
        m_standardModel->setBooks(filtered);
    }
}

static int statusPriority(const QString &s)
{
    if (s == QStringLiteral("reading"))   return 0;
    if (s == QStringLiteral("planned"))   return 1;
    if (s == QStringLiteral("read"))      return 2;
    if (s == QStringLiteral("abandoned")) return 3;
    return 4;
}

static QDate effectiveDate(const Book &book)
{
    if (book.endDate.isValid())   return book.endDate;
    if (book.startDate.isValid()) return book.startDate;
    return QDate(1900, 1, 1);
}

void BookController::sortBooks(QVector<Book> &books)
{
    if (m_sortMode == QStringLiteral("default")) {
        std::stable_sort(books.begin(), books.end(), [this](const Book &a, const Book &b) {
            // Priority hoisting applies to the default sort only. The other modes are
            // orderings the user asked for explicitly, so they deliberately ignore isPriority.
            if (m_priorityEnabled && a.isPriority != b.isPriority)
                return a.isPriority;

            int pa = statusPriority(a.status);
            int pb = statusPriority(b.status);
            if (pa != pb) return pa < pb;

            if (a.status == QStringLiteral("reading") && b.status == QStringLiteral("reading")) {
                double pctA = a.pageCount > 0 ? static_cast<double>(a.currentPage) / a.pageCount : 0.0;
                double pctB = b.pageCount > 0 ? static_cast<double>(b.currentPage) / b.pageCount : 0.0;
                if (pctA != pctB) return pctA > pctB;
            }

            QDate da = effectiveDate(a);
            QDate db = effectiveDate(b);
            if (da != db) return da > db;

            return a.author.toLower() < b.author.toLower();
        });
    } else if (m_sortMode == QStringLiteral("title_asc")) {
        std::stable_sort(books.begin(), books.end(), [](const Book &a, const Book &b) {
            return a.title.toLower() < b.title.toLower();
        });
    } else if (m_sortMode == QStringLiteral("title_desc")) {
        std::stable_sort(books.begin(), books.end(), [](const Book &a, const Book &b) {
            return a.title.toLower() > b.title.toLower();
        });
    } else if (m_sortMode == QStringLiteral("author_asc")) {
        std::stable_sort(books.begin(), books.end(), [](const Book &a, const Book &b) {
            return a.author.toLower() < b.author.toLower();
        });
    } else if (m_sortMode == QStringLiteral("author_desc")) {
        std::stable_sort(books.begin(), books.end(), [](const Book &a, const Book &b) {
            return a.author.toLower() > b.author.toLower();
        });
    } else if (m_sortMode == QStringLiteral("rating_desc")) {
        std::stable_sort(books.begin(), books.end(), [](const Book &a, const Book &b) {
            return a.rating > b.rating;
        });
    } else if (m_sortMode == QStringLiteral("date_desc")) {
        std::stable_sort(books.begin(), books.end(), [](const Book &a, const Book &b) {
            return effectiveDate(a) > effectiveDate(b);
        });
    } else if (m_sortMode == QStringLiteral("date_asc")) {
        std::stable_sort(books.begin(), books.end(), [](const Book &a, const Book &b) {
            return effectiveDate(a) < effectiveDate(b);
        });
    } else if (m_sortMode == QStringLiteral("pages_desc")) {
        std::stable_sort(books.begin(), books.end(), [](const Book &a, const Book &b) {
            return a.pageCount > b.pageCount;
        });
    }
}
