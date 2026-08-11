#include "syncrepository.h"

#include <QDateTime>
#include <QDebug>
#include <QUuid>
#include <QCryptographicHash>
#include <QFile>
#include <QDir>
#include <QFileInfo>
#include <QStandardPaths>
#include <QUrl>
#include <QSqlError>
#include <QSqlQuery>
#include <QSqlRecord>

namespace {

/**
 * A UUID as the API expects it: bare hex with dashes.
 *
 * Qt maps a PostgreSQL uuid column to QUuid, whose toString() wraps the value
 * in braces — "{2108a3a4-...}". That is not what JSON Schema's `format: uuid`
 * accepts, and the server rejected the whole batch over it. Worth noting that
 * the server's validation is what caught this: without it the braced form
 * would have been stored and quietly failed to match anything ever again.
 */
QString uuidOf(const QVariant &v)
{
    if (v.userType() == QMetaType::QUuid)
        return v.toUuid().toString(QUuid::WithoutBraces);

    // A plain string column, or a driver that does not map the type.
    QString s = v.toString();
    if (s.startsWith(QLatin1Char('{')) && s.endsWith(QLatin1Char('}')))
        s = s.mid(1, s.length() - 2);
    return s;
}

/** ISO-8601 with a zone, which is what the API's schemas require. */
QString isoOrNull(const QVariant &v)
{
    if (v.isNull()) return QString();
    const QDateTime dt = v.toDateTime();
    return dt.isValid() ? dt.toUTC().toString(Qt::ISODateWithMs) : QString();
}

/** A DATE column travels as YYYY-MM-DD, never as an instant: giving a date a
 *  time and a zone is how a book finished on the 8th arrives as the 7th. */
QJsonValue dateOrNull(const QVariant &v)
{
    if (v.isNull()) return QJsonValue::Null;
    const QDate d = v.toDate();
    return d.isValid() ? QJsonValue(d.toString(Qt::ISODate)) : QJsonValue::Null;
}

QJsonValue textOrNull(const QVariant &v)
{
    if (v.isNull()) return QJsonValue::Null;
    const QString s = v.toString();
    return s.isEmpty() ? QJsonValue::Null : QJsonValue(s);
}

QJsonValue intOrNull(const QVariant &v)
{
    return v.isNull() ? QJsonValue::Null : QJsonValue(v.toInt());
}

} // namespace

SyncRepository::SyncRepository(QSqlDatabase db)
    : m_db(std::move(db))
{
}

int SyncRepository::bookCount() const
{
    QSqlQuery q(m_db);
    if (q.exec("SELECT count(*) FROM books") && q.next())
        return q.value(0).toInt();
    return 0;
}

// ─── Collect ─────────────────────────────────────────────────────────────────

QJsonObject SyncRepository::collectAll() const
{
    return collectChangedSince(QDateTime::fromSecsSinceEpoch(0));
}

QJsonObject SyncRepository::collectChangedSince(const QDateTime &since) const
{
    QJsonObject batch;

    // Books first. Quotes, highlights and sessions all reference a book UUID,
    // and the server skips a child whose parent has not arrived — within one
    // batch the parent has to land first.
    batch["books"] = collectBooks(since);
    batch["tags"] = collectTags(since);
    batch["challenges"] = collectChallenges(since);
    batch["favoriteQuotes"] = collectQuotes(since);
    batch["highlights"] = collectHighlights(since);
    batch["readingSessions"] = collectSessions(since);

    return batch;
}

QJsonArray SyncRepository::collectBooks(const QDateTime &since) const
{
    QSqlQuery q(m_db);
    q.prepare(
        "SELECT uuid, title, author, genre, page_count, start_date, end_date, rating, "
        "       status, notes, isbn, publisher, publication_year, publication_date, "
        "       language, item_type, is_non_fiction, is_priority, audio_mode, "
        "       current_page, series, summary, review, read_count, cover_hash, "
        "       client_updated_at, "
        "       COALESCE((SELECT array_agg(t.name ORDER BY t.name) FROM book_tags bt "
        "                 JOIN tags t ON t.id = bt.tag_id WHERE bt.book_id = books.id), "
        "                ARRAY[]::varchar[]) AS tag_names "
        "  FROM books WHERE client_updated_at > :since ORDER BY client_updated_at");
    q.bindValue(":since", since);

    QJsonArray rows;
    if (!q.exec()) {
        qWarning() << "collectBooks:" << q.lastError().text();
        return rows;
    }

    while (q.next()) {
        QJsonObject b;
        b["uuid"] = uuidOf(q.value("uuid"));
        b["updatedAt"] = isoOrNull(q.value("client_updated_at"));
        b["title"] = q.value("title").toString();
        b["author"] = q.value("author").toString();
        b["genre"] = textOrNull(q.value("genre"));
        b["pageCount"] = intOrNull(q.value("page_count"));
        b["startDate"] = dateOrNull(q.value("start_date"));
        b["endDate"] = dateOrNull(q.value("end_date"));
        b["rating"] = intOrNull(q.value("rating"));
        b["status"] = q.value("status").toString();
        b["notes"] = textOrNull(q.value("notes"));
        b["isbn"] = textOrNull(q.value("isbn"));
        b["publisher"] = textOrNull(q.value("publisher"));
        b["publicationYear"] = intOrNull(q.value("publication_year"));
        b["publicationDate"] = dateOrNull(q.value("publication_date"));
        b["language"] = textOrNull(q.value("language"));
        b["itemType"] = textOrNull(q.value("item_type"));
        b["isNonFiction"] = q.value("is_non_fiction").toBool();
        b["isPriority"] = q.value("is_priority").toBool();
        b["audioMode"] = textOrNull(q.value("audio_mode"));
        b["currentPage"] = intOrNull(q.value("current_page"));
        b["series"] = textOrNull(q.value("series"));
        b["summary"] = textOrNull(q.value("summary"));
        b["review"] = textOrNull(q.value("review"));
        b["readCount"] = q.value("read_count").toInt();
        b["coverHash"] = textOrNull(q.value("cover_hash"));

        // page_count and current_page are nullable and 38 of this library's
        // books have NULL in the latter. The application reads NULL and 0
        // identically, so sending 0 would look harmless — and would still be a
        // silent rewrite of the user's data on the way back down.

        // cover_image_path is deliberately absent, and cover_hash is present
        // in its place. The path names a file on this machine and means nothing
        // on another; the hash names the bytes, which mean the same everywhere.

        QJsonArray tags;
        const QString raw = q.value("tag_names").toString();
        const QString inner = raw.mid(1, raw.length() - 2);   // strip PostgreSQL's {}
        if (!inner.isEmpty())
            for (const QString &t : inner.split(QLatin1Char(',')))
                tags.append(QString(t).remove(QLatin1Char('"')));
        b["tags"] = tags;

        rows.append(b);
    }
    return rows;
}

QJsonArray SyncRepository::collectSessions(const QDateTime &since) const
{
    QSqlQuery q(m_db);
    q.prepare("SELECT s.uuid, b.uuid AS book_uuid, s.session_date, s.page_start, "
              "       s.page_end, s.source, s.client_updated_at "
              "  FROM reading_sessions s JOIN books b ON b.id = s.book_id "
              " WHERE s.client_updated_at > :since ORDER BY s.client_updated_at");
    q.bindValue(":since", since);

    QJsonArray rows;
    if (!q.exec()) { qWarning() << "collectSessions:" << q.lastError().text(); return rows; }

    while (q.next()) {
        QJsonObject s;
        s["uuid"] = uuidOf(q.value("uuid"));
        s["bookUuid"] = uuidOf(q.value("book_uuid"));
        s["updatedAt"] = isoOrNull(q.value("client_updated_at"));
        s["sessionDate"] = q.value("session_date").toDate().toString(Qt::ISODate);
        s["pageStart"] = q.value("page_start").toInt();
        s["pageEnd"] = q.value("page_end").toInt();
        s["source"] = q.value("source").toString();
        rows.append(s);
    }
    return rows;
}

QJsonArray SyncRepository::collectTags(const QDateTime &since) const
{
    QSqlQuery q(m_db);
    q.prepare("SELECT uuid, name, color, client_updated_at FROM tags "
              " WHERE client_updated_at > :since ORDER BY client_updated_at");
    q.bindValue(":since", since);

    QJsonArray rows;
    if (!q.exec()) { qWarning() << "collectTags:" << q.lastError().text(); return rows; }

    while (q.next()) {
        QJsonObject t;
        t["uuid"] = uuidOf(q.value("uuid"));
        t["updatedAt"] = isoOrNull(q.value("client_updated_at"));
        t["name"] = q.value("name").toString();
        t["color"] = textOrNull(q.value("color"));
        rows.append(t);
    }
    return rows;
}

QJsonArray SyncRepository::collectQuotes(const QDateTime &since) const
{
    QSqlQuery q(m_db);
    q.prepare("SELECT qq.uuid, b.uuid AS book_uuid, qq.quote, qq.page, qq.client_updated_at "
              "  FROM favorite_quotes qq JOIN books b ON b.id = qq.book_id "
              " WHERE qq.client_updated_at > :since ORDER BY qq.client_updated_at");
    q.bindValue(":since", since);

    QJsonArray rows;
    if (!q.exec()) { qWarning() << "collectQuotes:" << q.lastError().text(); return rows; }

    while (q.next()) {
        QJsonObject o;
        o["uuid"] = uuidOf(q.value("uuid"));
        o["bookUuid"] = uuidOf(q.value("book_uuid"));
        o["updatedAt"] = isoOrNull(q.value("client_updated_at"));
        o["quote"] = q.value("quote").toString();
        o["page"] = intOrNull(q.value("page"));
        rows.append(o);
    }
    return rows;
}

QJsonArray SyncRepository::collectHighlights(const QDateTime &since) const
{
    QSqlQuery q(m_db);
    q.prepare("SELECT h.uuid, b.uuid AS book_uuid, h.title, h.page, h.note, h.client_updated_at "
              "  FROM highlights h JOIN books b ON b.id = h.book_id "
              " WHERE h.client_updated_at > :since ORDER BY h.client_updated_at");
    q.bindValue(":since", since);

    QJsonArray rows;
    if (!q.exec()) { qWarning() << "collectHighlights:" << q.lastError().text(); return rows; }

    while (q.next()) {
        QJsonObject o;
        o["uuid"] = uuidOf(q.value("uuid"));
        o["bookUuid"] = uuidOf(q.value("book_uuid"));
        o["updatedAt"] = isoOrNull(q.value("client_updated_at"));
        o["title"] = q.value("title").toString();
        o["page"] = intOrNull(q.value("page"));
        o["note"] = textOrNull(q.value("note"));
        rows.append(o);
    }
    return rows;
}

QJsonArray SyncRepository::collectChallenges(const QDateTime &since) const
{
    QSqlQuery q(m_db);
    q.prepare("SELECT uuid, name, deadline, metric, target_value, target_books, "
              "       period_unit, period_count, client_updated_at "
              "  FROM challenges WHERE client_updated_at > :since ORDER BY client_updated_at");
    q.bindValue(":since", since);

    QJsonArray rows;
    if (!q.exec()) { qWarning() << "collectChallenges:" << q.lastError().text(); return rows; }

    while (q.next()) {
        QJsonObject c;
        c["uuid"] = uuidOf(q.value("uuid"));
        c["updatedAt"] = isoOrNull(q.value("client_updated_at"));
        c["name"] = q.value("name").toString();
        c["deadline"] = q.value("deadline").toDate().toString(Qt::ISODate);
        c["metric"] = q.value("metric").toString();
        c["targetValue"] = q.value("target_value").toInt();
        c["targetBooks"] = q.value("target_books").toInt();
        c["periodUnit"] = textOrNull(q.value("period_unit"));
        c["periodCount"] = q.value("period_count").toInt();
        rows.append(c);
    }
    return rows;
}

// ─── Tombstones ──────────────────────────────────────────────────────────────

QJsonArray SyncRepository::pendingTombstones() const
{
    QSqlQuery q(m_db);
    QJsonArray rows;
    if (!q.exec("SELECT entity, uuid, deleted_at FROM sync_tombstones ORDER BY id")) {
        qWarning() << "pendingTombstones:" << q.lastError().text();
        return rows;
    }
    while (q.next()) {
        QJsonObject t;
        t["entity"] = q.value("entity").toString();
        t["uuid"] = uuidOf(q.value("uuid"));
        t["deletedAt"] = isoOrNull(q.value("deleted_at"));
        rows.append(t);
    }
    return rows;
}

void SyncRepository::clearTombstones(const QJsonArray &tombstones)
{
    QSqlQuery q(m_db);
    for (const QJsonValue &v : tombstones) {
        q.prepare("DELETE FROM sync_tombstones WHERE entity = :entity AND uuid = :uuid");
        q.bindValue(":entity", v.toObject().value("entity").toString());
        q.bindValue(":uuid", v.toObject().value("uuid").toString());
        q.exec();
    }
}

// ─── Apply ───────────────────────────────────────────────────────────────────

int SyncRepository::bookIdForUuid(const QString &uuid) const
{
    QSqlQuery q(m_db);
    q.prepare("SELECT id FROM books WHERE uuid = :uuid");
    q.bindValue(":uuid", uuid);
    if (q.exec() && q.next())
        return q.value(0).toInt();
    return -1;
}

int SyncRepository::applyChanges(const QJsonObject &changes)
{
    int written = 0;

    // Same ordering rule as pushing: a session referencing a book that has not
    // been written yet cannot be placed.
    written += applyBooks(changes.value("books").toArray());
    written += applyTags(changes.value("tags").toArray());
    written += applySessions(changes.value("readingSessions").toArray());

    return written;
}

int SyncRepository::applyBooks(const QJsonArray &rows)
{
    int written = 0;
    QSqlQuery q(m_db);

    for (const QJsonValue &v : rows) {
        const QJsonObject b = v.toObject();
        const QString uuid = b.value("uuid").toString();

        // A tombstone from the server: the row is gone elsewhere, so it goes
        // here too. Hard delete — this client keeps no tombstone for a deletion
        // it did not make.
        if (!b.value("deletedAt").isNull() && b.contains("deletedAt")) {
            q.prepare("DELETE FROM books WHERE uuid = :uuid");
            q.bindValue(":uuid", uuid);
            if (q.exec() && q.numRowsAffected() > 0) ++written;
            continue;
        }

        q.prepare(
            "INSERT INTO books (uuid, title, author, genre, page_count, start_date, end_date, "
            "                   rating, status, notes, isbn, publisher, publication_year, "
            "                   publication_date, language, item_type, is_non_fiction, "
            "                   is_priority, audio_mode, current_page, series, summary, "
            "                   review, read_count, cover_hash, client_updated_at) "
            "VALUES (:uuid, :title, :author, :genre, :page_count, :start_date, :end_date, "
            "        :rating, :status, :notes, :isbn, :publisher, :publication_year, "
            "        :publication_date, :language, :item_type, :is_non_fiction, "
            "        :is_priority, :audio_mode, :current_page, :series, :summary, "
            "        :review, :read_count, :cover_hash, :client_updated_at) "
            "ON CONFLICT (uuid) DO UPDATE SET "
            "  title = EXCLUDED.title, author = EXCLUDED.author, genre = EXCLUDED.genre, "
            "  page_count = EXCLUDED.page_count, start_date = EXCLUDED.start_date, "
            "  end_date = EXCLUDED.end_date, rating = EXCLUDED.rating, status = EXCLUDED.status, "
            "  notes = EXCLUDED.notes, isbn = EXCLUDED.isbn, publisher = EXCLUDED.publisher, "
            "  publication_year = EXCLUDED.publication_year, "
            "  publication_date = EXCLUDED.publication_date, language = EXCLUDED.language, "
            "  item_type = EXCLUDED.item_type, is_non_fiction = EXCLUDED.is_non_fiction, "
            "  is_priority = EXCLUDED.is_priority, audio_mode = EXCLUDED.audio_mode, "
            "  current_page = EXCLUDED.current_page, series = EXCLUDED.series, "
            "  summary = EXCLUDED.summary, review = EXCLUDED.review, "
            "  read_count = EXCLUDED.read_count, cover_hash = EXCLUDED.cover_hash, "
            "  client_updated_at = EXCLUDED.client_updated_at "
            // Last-write-wins, on the edit time rather than arrival order — the
            // same rule the server applies, so both sides agree on the winner.
            "WHERE EXCLUDED.client_updated_at > books.client_updated_at");

        q.bindValue(":uuid", uuid);
        q.bindValue(":cover_hash", b.value("coverHash").toVariant());
        q.bindValue(":title", b.value("title").toString());
        q.bindValue(":author", b.value("author").toString());
        q.bindValue(":genre", b.value("genre").toVariant());
        q.bindValue(":page_count", b.value("pageCount").toVariant());
        q.bindValue(":start_date", b.value("startDate").toVariant());
        q.bindValue(":end_date", b.value("endDate").toVariant());
        q.bindValue(":rating", b.value("rating").toVariant());
        q.bindValue(":status", b.value("status").toString());
        q.bindValue(":notes", b.value("notes").toVariant());
        q.bindValue(":isbn", b.value("isbn").toVariant());
        q.bindValue(":publisher", b.value("publisher").toVariant());
        q.bindValue(":publication_year", b.value("publicationYear").toVariant());
        q.bindValue(":publication_date", b.value("publicationDate").toVariant());
        q.bindValue(":language", b.value("language").toVariant());
        q.bindValue(":item_type", b.value("itemType").toVariant());
        q.bindValue(":is_non_fiction", b.value("isNonFiction").toBool());
        q.bindValue(":is_priority", b.value("isPriority").toBool());
        q.bindValue(":audio_mode", b.value("audioMode").toVariant());
        q.bindValue(":current_page", b.value("currentPage").toVariant());
        q.bindValue(":series", b.value("series").toVariant());
        q.bindValue(":summary", b.value("summary").toVariant());
        q.bindValue(":review", b.value("review").toVariant());
        q.bindValue(":read_count", b.value("readCount").toInt());
        q.bindValue(":client_updated_at", b.value("updatedAt").toString());

        if (!q.exec())
            qWarning() << "applyBooks:" << q.lastError().text();
        else if (q.numRowsAffected() > 0)
            ++written;
    }
    return written;
}

int SyncRepository::applyTags(const QJsonArray &rows)
{
    int written = 0;
    QSqlQuery q(m_db);

    for (const QJsonValue &v : rows) {
        const QJsonObject t = v.toObject();

        if (!t.value("deletedAt").isNull() && t.contains("deletedAt")) {
            q.prepare("DELETE FROM tags WHERE uuid = :uuid");
            q.bindValue(":uuid", t.value("uuid").toString());
            if (q.exec() && q.numRowsAffected() > 0) ++written;
            continue;
        }

        q.prepare("INSERT INTO tags (uuid, name, color, client_updated_at) "
                  "VALUES (:uuid, :name, :color, :updated) "
                  "ON CONFLICT (uuid) DO UPDATE SET name = EXCLUDED.name, "
                  "  color = EXCLUDED.color, client_updated_at = EXCLUDED.client_updated_at "
                  "WHERE EXCLUDED.client_updated_at > tags.client_updated_at");
        q.bindValue(":uuid", t.value("uuid").toString());
        q.bindValue(":name", t.value("name").toString());
        q.bindValue(":color", t.value("color").toVariant());
        q.bindValue(":updated", t.value("updatedAt").toString());

        if (!q.exec())
            qWarning() << "applyTags:" << q.lastError().text();
        else if (q.numRowsAffected() > 0)
            ++written;
    }
    return written;
}

int SyncRepository::applySessions(const QJsonArray &rows)
{
    int written = 0;
    QSqlQuery q(m_db);

    for (const QJsonValue &v : rows) {
        const QJsonObject s = v.toObject();
        const int bookId = bookIdForUuid(s.value("bookUuid").toString());

        // A session whose book has not arrived is skipped, not an error: the
        // next sync carries it once the book exists. Failing the batch would
        // wedge two rows that merely arrived out of order.
        if (bookId < 0)
            continue;

        if (!s.value("deletedAt").isNull() && s.contains("deletedAt")) {
            q.prepare("DELETE FROM reading_sessions WHERE uuid = :uuid");
            q.bindValue(":uuid", s.value("uuid").toString());
            if (q.exec() && q.numRowsAffected() > 0) ++written;
            continue;
        }

        // LEAST/GREATEST, not last-write-wins. Two devices recording the same
        // reading day produce different UUIDs for one session, so the conflict
        // target is the day — and pages read can only widen, never be lost to a
        // timestamp race.
        q.prepare("INSERT INTO reading_sessions (uuid, book_id, session_date, page_start, "
                  "                              page_end, source, client_updated_at) "
                  "VALUES (:uuid, :book_id, :date, :start, :end, :source, :updated) "
                  "ON CONFLICT (book_id, session_date, source) DO UPDATE SET "
                  "  page_start = LEAST(reading_sessions.page_start, EXCLUDED.page_start), "
                  "  page_end = GREATEST(reading_sessions.page_end, EXCLUDED.page_end)");
        q.bindValue(":uuid", s.value("uuid").toString());
        q.bindValue(":book_id", bookId);
        q.bindValue(":date", s.value("sessionDate").toString());
        q.bindValue(":start", s.value("pageStart").toInt());
        q.bindValue(":end", s.value("pageEnd").toInt());
        q.bindValue(":source", s.value("source").toString());
        q.bindValue(":updated", s.value("updatedAt").toString());

        if (!q.exec())
            qWarning() << "applySessions:" << q.lastError().text();
        else if (q.numRowsAffected() > 0)
            ++written;
    }
    return written;
}

// ── Covers ───────────────────────────────────────────────────────────────────

QString SyncRepository::coverDir()
{
    return QStandardPaths::writableLocation(QStandardPaths::AppDataLocation)
           + QStringLiteral("/covers");
}

QString SyncRepository::hashFile(const QString &path)
{
    QFile f(path);
    if (!f.open(QIODevice::ReadOnly))
        return {};

    QCryptographicHash hash(QCryptographicHash::Sha256);
    if (!hash.addData(&f))
        return {};

    return QString::fromLatin1(hash.result().toHex());
}

QVector<SyncRepository::CoverJob> SyncRepository::coversToUpload() const
{
    QVector<CoverJob> jobs;

    QSqlQuery q(m_db);
    if (!q.exec("SELECT id, cover_image_path, cover_hash FROM books "
                " WHERE cover_image_path IS NOT NULL AND cover_image_path <> ''")) {
        qWarning() << "coversToUpload:" << q.lastError().text();
        return jobs;
    }

    while (q.next()) {
        const int id = q.value("id").toInt();
        QString path = q.value("cover_image_path").toString();
        const QString recorded = q.value("cover_hash").toString();

        // QML hands paths around as file: URLs; the database has both forms.
        if (path.startsWith(QStringLiteral("file://")))
            path = QUrl(path).toLocalFile();

        if (!QFile::exists(path))
            continue;

        // Anything living in the mirror directory is a file this machine
        // downloaded, and is never uploaded — by location, not by name.
        //
        // The name is the tempting test and it is not enough. A pull can write
        // a new cover_hash onto a book whose download then fails, leaving a
        // mirror whose name no longer matches; hashing it would find a
        // difference, upload it, and receive a third hash. That loop happened.
        // Location cannot drift: a mirror was never the user's choice, so if it
        // disagrees with the hash the answer is always to fetch, never to send.
        if (QDir(coverDir()) == QDir(QFileInfo(path).absolutePath()))
            continue;

        const QString actual = hashFile(path);
        if (actual.isEmpty() || actual == recorded)
            continue;

        jobs.append(CoverJob{id, path, actual});
    }
    return jobs;
}

QVector<SyncRepository::CoverJob> SyncRepository::coversToDownload() const
{
    QVector<CoverJob> jobs;

    QSqlQuery q(m_db);
    if (!q.exec("SELECT id, cover_hash, cover_image_path FROM books "
                " WHERE cover_hash IS NOT NULL AND cover_hash <> ''")) {
        qWarning() << "coversToDownload:" << q.lastError().text();
        return jobs;
    }

    while (q.next()) {
        QString path = q.value("cover_image_path").toString();
        if (path.startsWith(QStringLiteral("file://")))
            path = QUrl(path).toLocalFile();

        const QString hash = q.value("cover_hash").toString();
        const bool haveFile = !path.isEmpty() && QFile::exists(path);

        // A file this machine downloaded is named after the hash it came from.
        // That name is how a mirror is told apart from a choice: if the book now
        // points at a different hash, the cover was changed somewhere else, and
        // this machine — which never picked one itself — should follow.
        //
        // A file the user chose is left alone even when the hashes differ. It is
        // the one on the screen because they put it there, and a sync is not the
        // moment to overrule that.
        const bool isMirror =
            haveFile && QDir(coverDir()) == QDir(QFileInfo(path).absolutePath());
        if (haveFile && !isMirror)
            continue;
        if (haveFile && QFileInfo(path).completeBaseName() == hash)
            continue;

        CoverJob job{q.value("id").toInt(),
                     coverDir() + QStringLiteral("/") + hash + QStringLiteral(".webp"),
                     hash};
        // The superseded mirror goes with it; nothing else refers to it, and
        // leaving every past cover behind would grow without limit.
        job.supersedes = isMirror ? path : QString();
        jobs.append(job);
    }
    return jobs;
}

void SyncRepository::setCoverHash(int bookId, const QString &hash)
{
    QSqlQuery q(m_db);
    // The timestamp moves, and it has to. Both sides settle conflicts by
    // comparing client_updated_at, so a row that does not advance it is
    // rejected by the server's merge rule and the hash never lands. The row did
    // genuinely change here, so saying so is honest rather than convenient.
    //
    // In the ordinary case this costs nothing: choosing a cover is an edit to
    // the book, which has already moved the timestamp. It matters only on the
    // first sync of a library whose covers predate any of this.
    q.prepare("UPDATE books SET cover_hash = :hash, client_updated_at = NOW() WHERE id = :id");
    q.bindValue(":hash", hash);
    q.bindValue(":id", bookId);
    if (!q.exec())
        qWarning() << "setCoverHash:" << q.lastError().text();
}

void SyncRepository::setCoverFile(int bookId, const QString &hash, const QString &path)
{
    QSqlQuery q(m_db);
    // No timestamp bump here, unlike setCoverHash. Nothing the server cares
    // about changed: it already holds this hash, and cover_image_path is local
    // and never pushed. Advancing the clock would only hand this machine an
    // unearned win in the next conflict.
    q.prepare("UPDATE books SET cover_hash = :hash, cover_image_path = :path WHERE id = :id");
    q.bindValue(":hash", hash);
    q.bindValue(":path", path);
    q.bindValue(":id", bookId);
    if (!q.exec())
        qWarning() << "setCoverFile:" << q.lastError().text();
}

void SyncRepository::retireMirror(const QString &path, int exceptBookId)
{
    if (path.isEmpty())
        return;

    // Shared by another book, so not this one's to delete. Deduplication makes
    // that ordinary rather than rare: two books with the same edition point at
    // one file, and removing it for one of them would blank the other.
    QSqlQuery q(m_db);
    q.prepare("SELECT 1 FROM books WHERE cover_image_path = :path AND id <> :id LIMIT 1");
    q.bindValue(":path", path);
    q.bindValue(":id", exceptBookId);
    if (q.exec() && q.next())
        return;

    QFile::remove(path);
}
