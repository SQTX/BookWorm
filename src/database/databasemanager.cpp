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

    m_db = QSqlDatabase::addDatabase(BookWorm::Config::DB_DRIVER);
    m_db.setHostName(BookWorm::Config::DB_HOST);
    m_db.setPort(BookWorm::Config::DB_PORT);
    m_db.setDatabaseName(BookWorm::Config::DB_NAME);
    m_db.setUserName(BookWorm::Config::DB_USER);
    m_db.setPassword(BookWorm::Config::DB_PASSWORD);

    if (!m_db.open()) {
        qCritical() << "Database connection failed:" << m_db.lastError().text();
        return false;
    }

    qInfo() << "Connected to PostgreSQL database:" << BookWorm::Config::DB_NAME;
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
    q.exec("ALTER TABLE books ADD COLUMN IF NOT EXISTS summary TEXT");
    q.exec("ALTER TABLE books ADD COLUMN IF NOT EXISTS review TEXT");

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

    // Highlights table
    q.exec("CREATE TABLE IF NOT EXISTS highlights ("
           "  id SERIAL PRIMARY KEY,"
           "  book_id INTEGER NOT NULL REFERENCES books(id) ON DELETE CASCADE,"
           "  title VARCHAR(256) NOT NULL,"
           "  page INTEGER,"
           "  note TEXT,"
           "  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()"
           ")");

    // Indexes (safe to call multiple times)
    q.exec("CREATE INDEX IF NOT EXISTS idx_books_status ON books(status)");
    q.exec("CREATE INDEX IF NOT EXISTS idx_books_genre ON books(genre)");
    q.exec("CREATE INDEX IF NOT EXISTS idx_books_end_date ON books(end_date)");
    q.exec("CREATE INDEX IF NOT EXISTS idx_book_tags_book_id ON book_tags(book_id)");
    q.exec("CREATE INDEX IF NOT EXISTS idx_favorite_quotes_book_id ON favorite_quotes(book_id)");
    q.exec("CREATE INDEX IF NOT EXISTS idx_challenges_deadline ON challenges(deadline)");
    q.exec("CREATE INDEX IF NOT EXISTS idx_highlights_book_id ON highlights(book_id)");

    // Tags: add color column
    q.exec("ALTER TABLE tags ADD COLUMN IF NOT EXISTS color VARCHAR(9) DEFAULT '#808080'");

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
        "  cover_image_path, item_type, is_non_fiction, current_page, series, "
        "  publication_date, summary, review) "
        "VALUES (:title, :author, :genre, :pageCount, :startDate, :endDate, "
        "  :rating, :status, :notes, :isbn, :publisher, :pubYear, :language, "
        "  :coverPath, :itemType, :isNonFiction, :currentPage, :series, "
        "  :pubDate, :summary, :review) "
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
    q.bindValue(":summary",      book.summary.isEmpty() ? QVariant() : book.summary);
    q.bindValue(":review",       book.review.isEmpty() ? QVariant() : book.review);

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
        "  series = :series, publication_date = :pubDate, "
        "  summary = :summary, review = :review, updated_at = NOW() "
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
    q.bindValue(":summary",      book.summary.isEmpty() ? QVariant() : book.summary);
    q.bindValue(":review",       book.review.isEmpty() ? QVariant() : book.review);

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

QVariantList DatabaseManager::fetchAllTagsWithColors()
{
    QVariantList result;
    QSqlQuery q("SELECT id, name, color FROM tags ORDER BY name", m_db);
    while (q.next()) {
        QVariantMap entry;
        entry["id"]    = q.value("id").toInt();
        entry["name"]  = q.value("name").toString();
        entry["color"] = q.value("color").toString();
        result.append(entry);
    }
    return result;
}

bool DatabaseManager::addTagWithColor(const QString &name, const QString &color)
{
    QSqlQuery q(m_db);
    q.prepare("INSERT INTO tags (name, color) VALUES (:name, :color) ON CONFLICT (name) DO NOTHING");
    q.bindValue(":name", name.trimmed());
    q.bindValue(":color", color.isEmpty() ? "#808080" : color);

    if (!q.exec()) {
        qWarning() << "addTagWithColor error:" << q.lastError().text();
        return false;
    }
    return true;
}

bool DatabaseManager::updateTag(int id, const QString &name, const QString &color)
{
    QSqlQuery q(m_db);
    q.prepare("UPDATE tags SET name = :name, color = :color WHERE id = :id");
    q.bindValue(":id", id);
    q.bindValue(":name", name.trimmed());
    q.bindValue(":color", color.isEmpty() ? "#808080" : color);

    if (!q.exec()) {
        qWarning() << "updateTag error:" << q.lastError().text();
        return false;
    }
    return true;
}

bool DatabaseManager::deleteTag(int id)
{
    QSqlQuery q(m_db);
    q.prepare("DELETE FROM tags WHERE id = :id");
    q.bindValue(":id", id);

    if (!q.exec()) {
        qWarning() << "deleteTag error:" << q.lastError().text();
        return false;
    }
    return true;
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

// ─── Highlights ─────────────────────────────────────────────

QVariantList DatabaseManager::fetchHighlightsForBook(int bookId)
{
    QVariantList list;
    QSqlQuery q(m_db);
    q.prepare("SELECT id, title, page, note FROM highlights WHERE book_id = :bookId ORDER BY page, id");
    q.bindValue(":bookId", bookId);

    if (q.exec()) {
        while (q.next()) {
            QVariantMap entry;
            entry["id"]    = q.value("id").toInt();
            entry["title"] = q.value("title").toString();
            entry["page"]  = q.value("page").toInt();
            entry["note"]  = q.value("note").toString();
            list.append(entry);
        }
    }
    return list;
}

bool DatabaseManager::addHighlight(int bookId, const QString &title, int page, const QString &note)
{
    QSqlQuery q(m_db);
    q.prepare("INSERT INTO highlights (book_id, title, page, note) VALUES (:bookId, :title, :page, :note)");
    q.bindValue(":bookId", bookId);
    q.bindValue(":title",  title);
    q.bindValue(":page",   page > 0 ? page : QVariant());
    q.bindValue(":note",   note.isEmpty() ? QVariant() : note);

    if (!q.exec()) {
        qWarning() << "addHighlight error:" << q.lastError().text();
        return false;
    }
    return true;
}

bool DatabaseManager::removeHighlight(int highlightId)
{
    QSqlQuery q(m_db);
    q.prepare("DELETE FROM highlights WHERE id = :id");
    q.bindValue(":id", highlightId);

    if (!q.exec()) {
        qWarning() << "removeHighlight error:" << q.lastError().text();
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

// ─── Reset ──────────────────────────────────────────────────

bool DatabaseManager::resetAllData()
{
    QSqlQuery q(m_db);
    // Order matters for foreign keys
    bool ok = true;
    ok = q.exec("DELETE FROM favorite_quotes") && ok;
    ok = q.exec("DELETE FROM highlights") && ok;
    ok = q.exec("DELETE FROM book_tags") && ok;
    ok = q.exec("DELETE FROM challenges") && ok;
    ok = q.exec("DELETE FROM books") && ok;
    ok = q.exec("DELETE FROM tags") && ok;

    if (!ok)
        qWarning() << "resetAllData error:" << q.lastError().text();

    return ok;
}

// ─── Statistics ─────────────────────────────────────────────

int DatabaseManager::totalBooksRead(int year)
{
    QSqlQuery q(m_db);
    if (year > 0) {
        q.prepare("SELECT COUNT(*) FROM books WHERE status = 'read'"
                  " AND EXTRACT(YEAR FROM end_date) = :year");
        q.bindValue(":year", year);
        q.exec();
    } else {
        q.exec("SELECT COUNT(*) FROM books WHERE status = 'read'");
    }
    return q.next() ? q.value(0).toInt() : 0;
}

int DatabaseManager::totalPagesRead(int year)
{
    QSqlQuery q(m_db);
    if (year > 0) {
        q.prepare("SELECT COALESCE(SUM(page_count), 0) FROM books WHERE status = 'read'"
                  " AND EXTRACT(YEAR FROM end_date) = :year");
        q.bindValue(":year", year);
        q.exec();
    } else {
        q.exec("SELECT COALESCE(SUM(page_count), 0) FROM books WHERE status = 'read'");
    }
    return q.next() ? q.value(0).toInt() : 0;
}

double DatabaseManager::averageRating(int year)
{
    QSqlQuery q(m_db);
    if (year > 0) {
        q.prepare("SELECT COALESCE(AVG(rating), 0) FROM books WHERE rating > 0"
                  " AND EXTRACT(YEAR FROM COALESCE(end_date, start_date)) = :year");
        q.bindValue(":year", year);
        q.exec();
    } else {
        q.exec("SELECT COALESCE(AVG(rating), 0) FROM books WHERE rating > 0");
    }
    return q.next() ? q.value(0).toDouble() : 0.0;
}

QVariantList DatabaseManager::genreDistribution(int year)
{
    QVariantList result;
    QSqlQuery q(m_db);
    if (year > 0) {
        q.prepare("SELECT genre, COUNT(*) as count FROM books "
                  "WHERE status = 'read' AND genre IS NOT NULL AND genre != '' "
                  "AND EXTRACT(YEAR FROM end_date) = :year "
                  "GROUP BY genre ORDER BY count DESC");
        q.bindValue(":year", year);
        q.exec();
    } else {
        q.exec("SELECT genre, COUNT(*) as count FROM books "
               "WHERE status = 'read' AND genre IS NOT NULL AND genre != '' "
               "GROUP BY genre ORDER BY count DESC");
    }

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

// ─── Statistics (extended) ──────────────────────────────────

int DatabaseManager::totalBooks(int year)
{
    QSqlQuery q(m_db);
    if (year > 0) {
        q.prepare("SELECT COUNT(*) FROM books"
                  " WHERE EXTRACT(YEAR FROM COALESCE(end_date, start_date)) = :year");
        q.bindValue(":year", year);
        q.exec();
    } else {
        q.exec("SELECT COUNT(*) FROM books");
    }
    return q.next() ? q.value(0).toInt() : 0;
}

double DatabaseManager::averagePagesPerBook(int year)
{
    QSqlQuery q(m_db);
    if (year > 0) {
        q.prepare("SELECT COALESCE(AVG(page_count), 0) FROM books "
                  "WHERE status IN ('read', 'reading') AND page_count > 0"
                  " AND EXTRACT(YEAR FROM COALESCE(end_date, start_date)) = :year");
        q.bindValue(":year", year);
    } else {
        q.prepare("SELECT COALESCE(AVG(page_count), 0) FROM books "
                  "WHERE status IN ('read', 'reading') AND page_count > 0");
    }
    if (q.exec() && q.next())
        return q.value(0).toDouble();
    return 0.0;
}

double DatabaseManager::averageCompletionPercent(int year)
{
    QSqlQuery q(m_db);
    QString sql =
        "SELECT COALESCE(AVG("
        "  CASE "
        "    WHEN status = 'read' THEN 100.0 "
        "    WHEN status = 'reading' AND page_count > 0 THEN (current_page::FLOAT / page_count) * 100.0 "
        "    ELSE NULL "
        "  END"
        "), 0) FROM books WHERE status IN ('read', 'reading')";
    if (year > 0) {
        sql += " AND EXTRACT(YEAR FROM COALESCE(end_date, start_date)) = :year";
        q.prepare(sql);
        q.bindValue(":year", year);
    } else {
        q.prepare(sql);
    }
    if (q.exec() && q.next())
        return q.value(0).toDouble();
    return 0.0;
}

QVariantList DatabaseManager::booksPerYear()
{
    QVariantList result;
    QSqlQuery q(m_db);
    q.prepare(
        "SELECT "
        "  EXTRACT(YEAR FROM end_date)::INT AS year, "
        "  COUNT(*) AS count, "
        "  COALESCE(SUM(page_count), 0) AS total_pages, "
        "  COALESCE(AVG(page_count), 0)::INT AS avg_pages, "
        "  COALESCE(AVG(NULLIF(rating, 0)), 0) AS avg_rating "
        "FROM books "
        "WHERE status = 'read' AND end_date IS NOT NULL "
        "GROUP BY year ORDER BY year DESC"
    );

    if (!q.exec()) {
        qWarning() << "booksPerYear error:" << q.lastError().text();
        return result;
    }

    while (q.next()) {
        QVariantMap entry;
        entry["year"]       = q.value("year").toInt();
        entry["count"]      = q.value("count").toInt();
        entry["totalPages"] = q.value("total_pages").toInt();
        entry["avgPages"]   = q.value("avg_pages").toInt();
        entry["avgRating"]  = q.value("avg_rating").toDouble();
        result.append(entry);
    }
    return result;
}

QVariantList DatabaseManager::booksPerMonthForYear(int year)
{
    QVariantList result;
    QSqlQuery q(m_db);
    q.prepare(
        "SELECT m.month_num, COALESCE(b.count, 0) AS count "
        "FROM generate_series(1, 12) AS m(month_num) "
        "LEFT JOIN ("
        "  SELECT EXTRACT(MONTH FROM end_date)::INT AS month_num, COUNT(*) AS count "
        "  FROM books "
        "  WHERE status = 'read' AND end_date IS NOT NULL "
        "    AND EXTRACT(YEAR FROM end_date) = :year "
        "  GROUP BY month_num"
        ") b ON m.month_num = b.month_num "
        "ORDER BY m.month_num"
    );
    q.bindValue(":year", year);

    if (!q.exec()) {
        qWarning() << "booksPerMonthForYear error:" << q.lastError().text();
        // Return 12 zero entries as fallback
        for (int i = 1; i <= 12; ++i) {
            QVariantMap entry;
            entry["month"] = i;
            entry["count"] = 0;
            result.append(entry);
        }
        return result;
    }

    while (q.next()) {
        QVariantMap entry;
        entry["month"] = q.value("month_num").toInt();
        entry["count"] = q.value("count").toInt();
        result.append(entry);
    }

    // Ensure exactly 12 entries
    if (result.size() < 12) {
        result.clear();
        for (int i = 1; i <= 12; ++i) {
            QVariantMap entry;
            entry["month"] = i;
            entry["count"] = 0;
            result.append(entry);
        }
    }

    return result;
}

QVariantMap DatabaseManager::statusDistribution(int year)
{
    QVariantMap result;
    result["reading"]   = 0;
    result["read"]      = 0;
    result["planned"]   = 0;

    QSqlQuery q(m_db);
    if (year > 0) {
        q.prepare("SELECT status, COUNT(*) AS count FROM books"
                  " WHERE EXTRACT(YEAR FROM COALESCE(end_date, start_date)) = :year"
                  " GROUP BY status");
        q.bindValue(":year", year);
        q.exec();
    } else {
        q.exec("SELECT status, COUNT(*) AS count FROM books GROUP BY status");
    }
    while (q.next()) {
        result[q.value("status").toString()] = q.value("count").toInt();
    }
    return result;
}

QVariantList DatabaseManager::getAvailableYears()
{
    QVariantList result;
    QSqlQuery q(m_db);
    q.prepare(
        "SELECT DISTINCT y FROM ("
        "  SELECT EXTRACT(YEAR FROM start_date)::INT AS y FROM books WHERE start_date IS NOT NULL "
        "  UNION "
        "  SELECT EXTRACT(YEAR FROM end_date)::INT AS y FROM books WHERE end_date IS NOT NULL"
        ") sub ORDER BY y DESC"
    );

    if (q.exec()) {
        while (q.next())
            result.append(q.value(0).toInt());
    }
    return result;
}
