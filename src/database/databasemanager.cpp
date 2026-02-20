#include "databasemanager.h"
#include "../constants.h"

#include <QSqlQuery>
#include <QSqlError>
#include <QSqlRecord>
#include <QVariantMap>
#include <QDebug>

DatabaseManager &DatabaseManager::instance()
{
    static DatabaseManager inst;
    return inst;
}

DatabaseManager::~DatabaseManager()
{
    disconnect();
}

bool DatabaseManager::connect()
{
    if (m_db.isOpen())
        return true;

    m_db = QSqlDatabase::addDatabase(WormBook::Config::DB_DRIVER);
    m_db.setHostName(WormBook::Config::DB_HOST);
    m_db.setPort(WormBook::Config::DB_PORT);
    m_db.setDatabaseName(WormBook::Config::DB_NAME);
    m_db.setUserName(WormBook::Config::DB_USER);
    m_db.setPassword(WormBook::Config::DB_PASSWORD);

    if (!m_db.open()) {
        qCritical() << "Database connection failed:" << m_db.lastError().text();
        return false;
    }

    qInfo() << "Connected to PostgreSQL database:" << WormBook::Config::DB_NAME;
    return true;
}

void DatabaseManager::disconnect()
{
    if (m_db.isOpen())
        m_db.close();
}

bool DatabaseManager::isConnected() const
{
    return m_db.isOpen();
}

bool DatabaseManager::initializeSchema()
{
    QSqlQuery q(m_db);

    const QStringList statements = {
        QStringLiteral(
            "CREATE TABLE IF NOT EXISTS books ("
            "  id SERIAL PRIMARY KEY,"
            "  title VARCHAR(512) NOT NULL,"
            "  author VARCHAR(512) NOT NULL,"
            "  genre VARCHAR(128),"
            "  page_count INTEGER DEFAULT 0,"
            "  start_date DATE,"
            "  end_date DATE,"
            "  rating SMALLINT CHECK (rating >= 1 AND rating <= 10),"
            "  status VARCHAR(16) NOT NULL DEFAULT 'planned'"
            "    CHECK (status IN ('reading', 'read', 'planned', 'abandoned')),"
            "  notes TEXT,"
            "  isbn VARCHAR(20),"
            "  publisher VARCHAR(256),"
            "  publication_year SMALLINT,"
            "  language VARCHAR(64) DEFAULT 'English',"
            "  cover_image_path VARCHAR(1024),"
            "  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),"
            "  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()"
            ")"
        ),
        QStringLiteral(
            "CREATE TABLE IF NOT EXISTS tags ("
            "  id SERIAL PRIMARY KEY,"
            "  name VARCHAR(128) NOT NULL UNIQUE"
            ")"
        ),
        QStringLiteral(
            "CREATE TABLE IF NOT EXISTS book_tags ("
            "  book_id INTEGER NOT NULL REFERENCES books(id) ON DELETE CASCADE,"
            "  tag_id INTEGER NOT NULL REFERENCES tags(id) ON DELETE CASCADE,"
            "  PRIMARY KEY (book_id, tag_id)"
            ")"
        ),
        QStringLiteral(
            "CREATE TABLE IF NOT EXISTS favorite_quotes ("
            "  id SERIAL PRIMARY KEY,"
            "  book_id INTEGER NOT NULL REFERENCES books(id) ON DELETE CASCADE,"
            "  quote TEXT NOT NULL,"
            "  page INTEGER"
            ")"
        )
    };

    for (const auto &sql : statements) {
        if (!q.exec(sql)) {
            qWarning() << "Schema init error:" << q.lastError().text();
            return false;
        }
    }

    // Migrations: add new columns if missing
    q.exec("ALTER TABLE books ADD COLUMN IF NOT EXISTS item_type VARCHAR(32) DEFAULT 'book'");
    q.exec("ALTER TABLE books ADD COLUMN IF NOT EXISTS is_non_fiction BOOLEAN DEFAULT FALSE");
    q.exec("ALTER TABLE books ADD COLUMN IF NOT EXISTS current_page INTEGER DEFAULT 0");
    q.exec("ALTER TABLE books ADD COLUMN IF NOT EXISTS series VARCHAR(256)");
    q.exec("ALTER TABLE books ADD COLUMN IF NOT EXISTS publication_date DATE");

    // Update rating constraint to allow 1-6 instead of 1-10
    q.exec("UPDATE books SET rating = LEAST(rating, 6) WHERE rating > 6");
    q.exec("ALTER TABLE books DROP CONSTRAINT IF EXISTS books_rating_check");
    q.exec("ALTER TABLE books ADD CONSTRAINT books_rating_check CHECK (rating >= 1 AND rating <= 6)");

    // Update status constraint to allow 'abandoned'
    q.exec("ALTER TABLE books DROP CONSTRAINT IF EXISTS books_status_check");
    q.exec("ALTER TABLE books ADD CONSTRAINT books_status_check "
           "CHECK (status IN ('reading', 'read', 'planned', 'abandoned'))");

    // Challenges table
    q.exec("CREATE TABLE IF NOT EXISTS challenges ("
           "  id SERIAL PRIMARY KEY,"
           "  name VARCHAR(256) NOT NULL,"
           "  target_books INTEGER NOT NULL DEFAULT 1,"
           "  deadline DATE NOT NULL,"
           "  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()"
           ")");

    // Indexes (safe to call multiple times)
    q.exec("CREATE INDEX IF NOT EXISTS idx_books_status ON books(status)");
    q.exec("CREATE INDEX IF NOT EXISTS idx_books_genre ON books(genre)");
    q.exec("CREATE INDEX IF NOT EXISTS idx_books_end_date ON books(end_date)");
    q.exec("CREATE INDEX IF NOT EXISTS idx_book_tags_book_id ON book_tags(book_id)");
    q.exec("CREATE INDEX IF NOT EXISTS idx_favorite_quotes_book_id ON favorite_quotes(book_id)");
    q.exec("CREATE INDEX IF NOT EXISTS idx_challenges_deadline ON challenges(deadline)");

    qInfo() << "Database schema initialized";
    return true;
}

// ─── Book CRUD ──────────────────────────────────────────────

QVector<Book> DatabaseManager::fetchAllBooks()
{
    QVector<Book> books;
    QSqlQuery q(m_db);
    q.prepare("SELECT * FROM books ORDER BY updated_at DESC");

    if (!q.exec()) {
        qWarning() << "fetchAllBooks error:" << q.lastError().text();
        return books;
    }

    while (q.next()) {
        Book book = Book::fromSqlRecord(q.record());
        book.tags = fetchTagsForBook(book.id);
        books.append(book);
    }
    return books;
}

std::optional<Book> DatabaseManager::fetchBookById(int id)
{
    QSqlQuery q(m_db);
    q.prepare("SELECT * FROM books WHERE id = :id");
    q.bindValue(":id", id);

    if (!q.exec() || !q.next()) {
        qWarning() << "fetchBookById error:" << q.lastError().text();
        return std::nullopt;
    }

    Book book = Book::fromSqlRecord(q.record());
    book.tags = fetchTagsForBook(book.id);
    return book;
}

int DatabaseManager::insertBook(const Book &book)
{
    QSqlQuery q(m_db);
    q.prepare(
        "INSERT INTO books (title, author, genre, page_count, start_date, end_date, "
        "  rating, status, notes, isbn, publisher, publication_year, language, "
        "  cover_image_path, item_type, is_non_fiction, current_page, series, publication_date) "
        "VALUES (:title, :author, :genre, :pageCount, :startDate, :endDate, "
        "  :rating, :status, :notes, :isbn, :publisher, :pubYear, :language, "
        "  :coverPath, :itemType, :isNonFiction, :currentPage, :series, :pubDate) "
        "RETURNING id"
    );

    q.bindValue(":title",        book.title);
    q.bindValue(":author",       book.author);
    q.bindValue(":genre",        book.genre.isEmpty() ? QVariant() : book.genre);
    q.bindValue(":pageCount",    book.pageCount > 0 ? book.pageCount : QVariant());
    q.bindValue(":startDate",    book.startDate.isValid() ? book.startDate : QVariant());
    q.bindValue(":endDate",      book.endDate.isValid() ? book.endDate : QVariant());
    q.bindValue(":rating",       book.rating > 0 ? book.rating : QVariant());
    q.bindValue(":status",       book.status);
    q.bindValue(":notes",        book.notes.isEmpty() ? QVariant() : book.notes);
    q.bindValue(":isbn",         book.isbn.isEmpty() ? QVariant() : book.isbn);
    q.bindValue(":publisher",    book.publisher.isEmpty() ? QVariant() : book.publisher);
    q.bindValue(":pubYear",      book.publicationYear > 0 ? book.publicationYear : QVariant());
    q.bindValue(":language",     book.language.isEmpty() ? QVariant() : book.language);
    q.bindValue(":coverPath",    book.coverImagePath.isEmpty() ? QVariant() : book.coverImagePath);
    q.bindValue(":itemType",     book.itemType);
    q.bindValue(":isNonFiction", book.isNonFiction);
    q.bindValue(":currentPage",  book.currentPage > 0 ? book.currentPage : QVariant());
    q.bindValue(":series",       book.series.isEmpty() ? QVariant() : book.series);
    q.bindValue(":pubDate",      book.publicationDate.isValid() ? book.publicationDate : QVariant());

    if (!q.exec() || !q.next()) {
        qWarning() << "insertBook error:" << q.lastError().text();
        return -1;
    }

    return q.value(0).toInt();
}

bool DatabaseManager::updateBook(const Book &book)
{
    QSqlQuery q(m_db);
    q.prepare(
        "UPDATE books SET title = :title, author = :author, genre = :genre, "
        "  page_count = :pageCount, start_date = :startDate, end_date = :endDate, "
        "  rating = :rating, status = :status, notes = :notes, isbn = :isbn, "
        "  publisher = :publisher, publication_year = :pubYear, language = :language, "
        "  cover_image_path = :coverPath, item_type = :itemType, "
        "  is_non_fiction = :isNonFiction, current_page = :currentPage, "
        "  series = :series, publication_date = :pubDate, updated_at = NOW() "
        "WHERE id = :id"
    );

    q.bindValue(":id",           book.id);
    q.bindValue(":title",        book.title);
    q.bindValue(":author",       book.author);
    q.bindValue(":genre",        book.genre.isEmpty() ? QVariant() : book.genre);
    q.bindValue(":pageCount",    book.pageCount > 0 ? book.pageCount : QVariant());
    q.bindValue(":startDate",    book.startDate.isValid() ? book.startDate : QVariant());
    q.bindValue(":endDate",      book.endDate.isValid() ? book.endDate : QVariant());
    q.bindValue(":rating",       book.rating > 0 ? book.rating : QVariant());
    q.bindValue(":status",       book.status);
    q.bindValue(":notes",        book.notes.isEmpty() ? QVariant() : book.notes);
    q.bindValue(":isbn",         book.isbn.isEmpty() ? QVariant() : book.isbn);
    q.bindValue(":publisher",    book.publisher.isEmpty() ? QVariant() : book.publisher);
    q.bindValue(":pubYear",      book.publicationYear > 0 ? book.publicationYear : QVariant());
    q.bindValue(":language",     book.language.isEmpty() ? QVariant() : book.language);
    q.bindValue(":coverPath",    book.coverImagePath.isEmpty() ? QVariant() : book.coverImagePath);
    q.bindValue(":itemType",     book.itemType);
    q.bindValue(":isNonFiction", book.isNonFiction);
    q.bindValue(":currentPage",  book.currentPage > 0 ? book.currentPage : QVariant());
    q.bindValue(":series",       book.series.isEmpty() ? QVariant() : book.series);
    q.bindValue(":pubDate",      book.publicationDate.isValid() ? book.publicationDate : QVariant());

    if (!q.exec()) {
        qWarning() << "updateBook error:" << q.lastError().text();
        return false;
    }
    return true;
}

bool DatabaseManager::deleteBook(int id)
{
    QSqlQuery q(m_db);
    q.prepare("DELETE FROM books WHERE id = :id");
    q.bindValue(":id", id);

    if (!q.exec()) {
        qWarning() << "deleteBook error:" << q.lastError().text();
        return false;
    }
    return true;
}

// ─── Tags ───────────────────────────────────────────────────

QStringList DatabaseManager::fetchTagsForBook(int bookId)
{
    QStringList tags;
    QSqlQuery q(m_db);
    q.prepare(
        "SELECT t.name FROM tags t "
        "JOIN book_tags bt ON bt.tag_id = t.id "
        "WHERE bt.book_id = :bookId ORDER BY t.name"
    );
    q.bindValue(":bookId", bookId);

    if (q.exec()) {
        while (q.next())
            tags.append(q.value(0).toString());
    }
    return tags;
}

QStringList DatabaseManager::fetchAllTags()
{
    QStringList tags;
    QSqlQuery q("SELECT name FROM tags ORDER BY name", m_db);
    while (q.next())
        tags.append(q.value(0).toString());
    return tags;
}

bool DatabaseManager::syncTagsForBook(int bookId, const QStringList &tags)
{
    if (!m_db.transaction())
        return false;

    // Remove existing associations
    QSqlQuery q(m_db);
    q.prepare("DELETE FROM book_tags WHERE book_id = :bookId");
    q.bindValue(":bookId", bookId);
    if (!q.exec()) {
        m_db.rollback();
        return false;
    }

    for (const QString &tagName : tags) {
        const QString trimmed = tagName.trimmed();
        if (trimmed.isEmpty())
            continue;

        // Upsert tag
        QSqlQuery upsert(m_db);
        upsert.prepare("INSERT INTO tags (name) VALUES (:name) ON CONFLICT (name) DO NOTHING");
        upsert.bindValue(":name", trimmed);
        if (!upsert.exec()) {
            m_db.rollback();
            return false;
        }

        // Get tag id
        QSqlQuery getId(m_db);
        getId.prepare("SELECT id FROM tags WHERE name = :name");
        getId.bindValue(":name", trimmed);
        if (!getId.exec() || !getId.next()) {
            m_db.rollback();
            return false;
        }
        int tagId = getId.value(0).toInt();

        // Link book <-> tag
        QSqlQuery link(m_db);
        link.prepare("INSERT INTO book_tags (book_id, tag_id) VALUES (:bookId, :tagId)");
        link.bindValue(":bookId", bookId);
        link.bindValue(":tagId", tagId);
        if (!link.exec()) {
            m_db.rollback();
            return false;
        }
    }

    return m_db.commit();
}

// ─── Quotes ─────────────────────────────────────────────────

QVariantList DatabaseManager::fetchQuotesForBook(int bookId)
{
    QVariantList quotes;
    QSqlQuery q(m_db);
    q.prepare("SELECT id, quote, page FROM favorite_quotes WHERE book_id = :bookId ORDER BY id");
    q.bindValue(":bookId", bookId);

    if (q.exec()) {
        while (q.next()) {
            QVariantMap entry;
            entry["id"]    = q.value("id").toInt();
            entry["quote"] = q.value("quote").toString();
            entry["page"]  = q.value("page").toInt();
            quotes.append(entry);
        }
    }
    return quotes;
}

bool DatabaseManager::addQuote(int bookId, const QString &quote, int page)
{
    QSqlQuery q(m_db);
    q.prepare("INSERT INTO favorite_quotes (book_id, quote, page) VALUES (:bookId, :quote, :page)");
    q.bindValue(":bookId", bookId);
    q.bindValue(":quote",  quote);
    q.bindValue(":page",   page > 0 ? page : QVariant());

    if (!q.exec()) {
        qWarning() << "addQuote error:" << q.lastError().text();
        return false;
    }
    return true;
}

bool DatabaseManager::removeQuote(int quoteId)
{
    QSqlQuery q(m_db);
    q.prepare("DELETE FROM favorite_quotes WHERE id = :id");
    q.bindValue(":id", quoteId);

    if (!q.exec()) {
        qWarning() << "removeQuote error:" << q.lastError().text();
        return false;
    }
    return true;
}

// ─── Challenges ─────────────────────────────────────────────

QVariantList DatabaseManager::fetchAllChallenges()
{
    QVariantList result;
    QSqlQuery q(m_db);
    q.prepare("SELECT id, name, target_books, deadline, created_at FROM challenges ORDER BY deadline");

    if (!q.exec()) {
        qWarning() << "fetchAllChallenges error:" << q.lastError().text();
        return result;
    }

    while (q.next()) {
        QVariantMap ch;
        int id = q.value("id").toInt();
        ch["id"]          = id;
        ch["name"]        = q.value("name").toString();
        ch["targetBooks"] = q.value("target_books").toInt();
        ch["deadline"]    = q.value("deadline").toDate().toString(Qt::ISODate);
        ch["createdAt"]   = q.value("created_at").toDateTime().date().toString(Qt::ISODate);

        // Count books read within challenge period
        QSqlQuery countQ(m_db);
        countQ.prepare(
            "SELECT COUNT(*) FROM books "
            "WHERE status = 'read' AND end_date IS NOT NULL "
            "AND end_date >= :start AND end_date <= :deadline"
        );
        countQ.bindValue(":start", q.value("created_at").toDateTime().date());
        countQ.bindValue(":deadline", q.value("deadline").toDate());
        int currentCount = 0;
        if (countQ.exec() && countQ.next())
            currentCount = countQ.value(0).toInt();

        ch["currentCount"] = currentCount;
        int target = q.value("target_books").toInt();
        ch["progress"] = target > 0 ? qMin(1.0, static_cast<double>(currentCount) / target) : 0.0;

        result.append(ch);
    }
    return result;
}

int DatabaseManager::insertChallenge(const QString &name, int targetBooks, const QDate &deadline)
{
    QSqlQuery q(m_db);
    q.prepare("INSERT INTO challenges (name, target_books, deadline) VALUES (:name, :target, :deadline) RETURNING id");
    q.bindValue(":name", name);
    q.bindValue(":target", targetBooks);
    q.bindValue(":deadline", deadline);

    if (!q.exec() || !q.next()) {
        qWarning() << "insertChallenge error:" << q.lastError().text();
        return -1;
    }
    return q.value(0).toInt();
}

bool DatabaseManager::deleteChallenge(int id)
{
    QSqlQuery q(m_db);
    q.prepare("DELETE FROM challenges WHERE id = :id");
    q.bindValue(":id", id);

    if (!q.exec()) {
        qWarning() << "deleteChallenge error:" << q.lastError().text();
        return false;
    }
    return true;
}

QVariantList DatabaseManager::fetchBooksForChallenge(int challengeId)
{
    QVariantList result;
    QSqlQuery q(m_db);
    q.prepare("SELECT created_at, deadline FROM challenges WHERE id = :id");
    q.bindValue(":id", challengeId);

    if (!q.exec() || !q.next())
        return result;

    QDate start = q.value("created_at").toDateTime().date();
    QDate deadline = q.value("deadline").toDate();

    QSqlQuery booksQ(m_db);
    booksQ.prepare(
        "SELECT id, title, author, end_date FROM books "
        "WHERE status = 'read' AND end_date IS NOT NULL "
        "AND end_date >= :start AND end_date <= :deadline "
        "ORDER BY end_date"
    );
    booksQ.bindValue(":start", start);
    booksQ.bindValue(":deadline", deadline);

    if (booksQ.exec()) {
        while (booksQ.next()) {
            QVariantMap entry;
            entry["id"]      = booksQ.value("id").toInt();
            entry["title"]   = booksQ.value("title").toString();
            entry["author"]  = booksQ.value("author").toString();
            entry["endDate"] = booksQ.value("end_date").toDate().toString(Qt::ISODate);
            result.append(entry);
        }
    }
    return result;
}

// ─── Statistics ─────────────────────────────────────────────

int DatabaseManager::totalBooksRead()
{
    QSqlQuery q("SELECT COUNT(*) FROM books WHERE status = 'read'", m_db);
    return q.next() ? q.value(0).toInt() : 0;
}

int DatabaseManager::totalPagesRead()
{
    QSqlQuery q("SELECT COALESCE(SUM(page_count), 0) FROM books WHERE status = 'read'", m_db);
    return q.next() ? q.value(0).toInt() : 0;
}

double DatabaseManager::averageRating()
{
    QSqlQuery q("SELECT COALESCE(AVG(rating), 0) FROM books WHERE rating > 0", m_db);
    return q.next() ? q.value(0).toDouble() : 0.0;
}

QVariantList DatabaseManager::genreDistribution()
{
    QVariantList result;
    QSqlQuery q(
        "SELECT genre, COUNT(*) as count FROM books "
        "WHERE status = 'read' AND genre IS NOT NULL AND genre != '' "
        "GROUP BY genre ORDER BY count DESC",
        m_db
    );

    while (q.next()) {
        QVariantMap entry;
        entry["genre"] = q.value("genre").toString();
        entry["count"] = q.value("count").toInt();
        result.append(entry);
    }
    return result;
}

QVariantList DatabaseManager::booksPerMonth()
{
    QVariantList result;
    QSqlQuery q(
        "SELECT TO_CHAR(end_date, 'YYYY-MM') as month, COUNT(*) as count "
        "FROM books WHERE status = 'read' AND end_date IS NOT NULL "
        "GROUP BY month ORDER BY month DESC LIMIT 12",
        m_db
    );

    while (q.next()) {
        QVariantMap entry;
        entry["month"] = q.value("month").toString();
        entry["count"] = q.value("count").toInt();
        result.append(entry);
    }

    // Reverse so oldest is first (for charts)
    std::reverse(result.begin(), result.end());
    return result;
}
