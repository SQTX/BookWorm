#include "bookcontroller.h"
#include "../database/databasemanager.h"

#include <QFile>
#include <QTextStream>
#include <QUrl>

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

QStringList BookController::getAllTags()
{
    return DatabaseManager::instance().fetchAllTags();
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

        filtered.append(book);
    }

    m_model->setBooks(filtered);
}
