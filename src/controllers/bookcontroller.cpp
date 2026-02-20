#include "bookcontroller.h"
#include "../database/databasemanager.h"

#include <QFile>
#include <QTextStream>
#include <QUrl>
#include <QSet>

BookController::BookController(QObject *parent)
    : QObject(parent)
    , m_model(new BookModel(this))
{
}

BookModel *BookController::model() const
{
    return m_model;
}

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
    if (!DatabaseManager::instance().deleteBook(id)) {
        emit errorOccurred("Failed to delete book");
        return false;
    }

    m_allBooks.erase(
        std::remove_if(m_allBooks.begin(), m_allBooks.end(),
                        [id](const Book &b) { return b.id == id; }),
        m_allBooks.end()
    );

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

QVariantMap BookController::getTypeDistribution()
{
    QVariantMap dist;
    for (const Book &book : m_allBooks) {
        QString type = book.itemType.isEmpty() ? QStringLiteral("book") : book.itemType;
        dist[type] = dist.value(type, 0).toInt() + 1;
    }
    return dist;
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

bool BookController::addChallenge(const QString &name, int targetBooks, const QString &deadline)
{
    QDate dl = QDate::fromString(deadline, Qt::ISODate);
    if (name.trimmed().isEmpty() || !dl.isValid() || targetBooks < 1) {
        emit errorOccurred("Invalid challenge data");
        return false;
    }

    int id = DatabaseManager::instance().insertChallenge(name.trimmed(), targetBooks, dl);
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
           "notes,isbn,publisher,publication_year,language,item_type,is_non_fiction,current_page,tags\n";

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
            << book.currentPage << ','
            << escapeCsvField(book.tags.join(", ")) << '\n';
    }

    file.close();
    return true;
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
        // current_page at index 15 (if present), tags at 16
        if (fields.size() >= 17) {
            book.currentPage = fields[15].trimmed().toInt();
        }

        const QString tagsStr = parseCsvField(fields.size() >= 17 ? fields[16] : fields[15]);
        if (!tagsStr.isEmpty()) {
            const auto parts = tagsStr.split(',');
            for (const auto &part : parts) {
                const QString trimmed = part.trimmed();
                if (!trimmed.isEmpty())
                    book.tags.append(trimmed);
            }
        }

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

        filtered.append(book);
    }

    m_model->setBooks(filtered);
}
