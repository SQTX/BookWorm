#include "loanmanager.h"

#include "../database/databasemanager.h"

#include <QDebug>
#include <QSqlError>
#include <QSqlQuery>

namespace {

/** Everything a row needs to render, including the book it belongs to. */
const char *SELECT_COLUMNS =
    "SELECT l.id, l.book_id, l.direction, l.counterparty,"
    "       to_char(l.loaned_on, 'YYYY-MM-DD') AS loaned_on,"
    "       to_char(l.returned_on, 'YYYY-MM-DD') AS returned_on,"
    "       COALESCE(l.note, '') AS note,"
    // Against the return date once it is back, so a closed loan reports how
    // long it was out rather than how long ago it happened.
    "       (COALESCE(l.returned_on, CURRENT_DATE) - l.loaned_on) AS days,"
    "       b.title, b.author, COALESCE(b.cover_image_path, '') AS cover"
    "  FROM book_loans l JOIN books b ON b.id = l.book_id";

} // namespace

LoanManager::LoanManager(QObject *parent)
    : QObject(parent)
{
    ensureSchema();
    refreshOpen();
}

void LoanManager::ensureSchema()
{
    QSqlQuery q(DatabaseManager::instance().database());

    const QStringList statements = {
        QStringLiteral(
            "CREATE TABLE IF NOT EXISTS book_loans ("
            "  id SERIAL PRIMARY KEY,"
            "  book_id INTEGER NOT NULL REFERENCES books(id) ON DELETE CASCADE,"
            // Two directions rather than one table each: the rows are identical
            // in shape and the difference is only ever a filter.
            "  direction VARCHAR(16) NOT NULL CHECK (direction IN ('lent', 'borrowed')),"
            "  counterparty VARCHAR(256) NOT NULL,"
            "  loaned_on DATE NOT NULL DEFAULT CURRENT_DATE,"
            // NULL is the whole feature: it means the book is still out.
            "  returned_on DATE,"
            "  note TEXT,"
            "  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()"
            ")"),

        // One book cannot be in two places. A partial index rather than a check
        // in C++, so two windows, or a dialog left open while the book was lent
        // elsewhere, cannot both write between a read and its write.
        QStringLiteral(
            "CREATE UNIQUE INDEX IF NOT EXISTS idx_book_loans_open "
            "  ON book_loans (book_id) WHERE returned_on IS NULL"),

        QStringLiteral(
            "CREATE INDEX IF NOT EXISTS idx_book_loans_book ON book_loans (book_id)"),
    };

    for (const QString &sql : statements) {
        if (!q.exec(sql))
            qWarning() << "loans: schema:" << q.lastError().text();
    }
}

void LoanManager::refreshOpen()
{
    m_open.clear();

    QSqlQuery q(DatabaseManager::instance().database());
    if (!q.exec(QStringLiteral(
            "SELECT book_id, counterparty, direction FROM book_loans "
            " WHERE returned_on IS NULL"))) {
        qWarning() << "loans: cannot read open loans:" << q.lastError().text();
        return;
    }

    while (q.next())
        m_open.insert(q.value(0).toInt(), { q.value(1).toString(), q.value(2).toString() });
}

int LoanManager::lentOutCount() const
{
    int n = 0;
    for (const Open &loan : m_open) {
        if (loan.direction == QLatin1String("lent"))
            ++n;
    }
    return n;
}

int LoanManager::borrowedCount() const
{
    return m_open.size() - lentOutCount();
}

QString LoanManager::holderOf(int bookId) const
{
    return m_open.value(bookId).counterparty;
}

bool LoanManager::startLoan(int bookId, const QString &direction,
                            const QString &counterparty, const QString &isoDate,
                            const QString &note)
{
    const QString who = counterparty.trimmed();
    if (bookId <= 0 || who.isEmpty())
        return false;
    if (direction != QLatin1String("lent") && direction != QLatin1String("borrowed"))
        return false;

    QSqlQuery q(DatabaseManager::instance().database());
    q.prepare(QStringLiteral(
        "INSERT INTO book_loans (book_id, direction, counterparty, loaned_on, note) "
        "VALUES (:book, :direction, :who, COALESCE(NULLIF(:day, '')::date, CURRENT_DATE), "
        "        NULLIF(:note, ''))"));
    q.bindValue(QStringLiteral(":book"), bookId);
    q.bindValue(QStringLiteral(":direction"), direction);
    q.bindValue(QStringLiteral(":who"), who);
    q.bindValue(QStringLiteral(":day"), isoDate);
    q.bindValue(QStringLiteral(":note"), note.trimmed());

    if (!q.exec()) {
        // The likely failure is the partial unique index: this book is already
        // out. That is a refusal the caller can explain, not a fault.
        qWarning() << "loans: cannot open loan:" << q.lastError().text();
        return false;
    }

    refreshOpen();
    emit changed();
    return true;
}

bool LoanManager::endLoan(int loanId, const QString &isoDate)
{
    QSqlQuery q(DatabaseManager::instance().database());
    q.prepare(QStringLiteral(
        "UPDATE book_loans "
        "   SET returned_on = COALESCE(NULLIF(:day, '')::date, CURRENT_DATE) "
        // Only an open one. Closing a closed loan would silently move a date
        // the user already recorded.
        " WHERE id = :id AND returned_on IS NULL"));
    q.bindValue(QStringLiteral(":id"), loanId);
    q.bindValue(QStringLiteral(":day"), isoDate);

    if (!q.exec()) {
        qWarning() << "loans: cannot close loan:" << q.lastError().text();
        return false;
    }
    if (q.numRowsAffected() == 0)
        return false;

    refreshOpen();
    emit changed();
    return true;
}

bool LoanManager::deleteLoan(int loanId)
{
    QSqlQuery q(DatabaseManager::instance().database());
    q.prepare(QStringLiteral("DELETE FROM book_loans WHERE id = :id"));
    q.bindValue(QStringLiteral(":id"), loanId);

    if (!q.exec()) {
        qWarning() << "loans: cannot delete loan:" << q.lastError().text();
        return false;
    }

    refreshOpen();
    emit changed();
    return true;
}

QVariantList LoanManager::query(const QString &where, const QString &order,
                                const QVariantList &binds) const
{
    QSqlQuery q(DatabaseManager::instance().database());
    q.prepare(QString::fromLatin1(SELECT_COLUMNS) + QStringLiteral(" WHERE ") + where
              + QStringLiteral(" ORDER BY ") + order);
    for (int i = 0; i < binds.size(); ++i)
        q.bindValue(i, binds.at(i));

    if (!q.exec()) {
        qWarning() << "loans: query failed:" << q.lastError().text();
        return {};
    }

    QVariantList out;
    while (q.next()) {
        QVariantMap row;
        row[QStringLiteral("id")] = q.value(0).toInt();
        row[QStringLiteral("bookId")] = q.value(1).toInt();
        row[QStringLiteral("direction")] = q.value(2).toString();
        row[QStringLiteral("counterparty")] = q.value(3).toString();
        row[QStringLiteral("loanedOn")] = q.value(4).toString();
        row[QStringLiteral("returnedOn")] = q.value(5).toString();
        row[QStringLiteral("note")] = q.value(6).toString();
        row[QStringLiteral("days")] = q.value(7).toInt();
        row[QStringLiteral("title")] = q.value(8).toString();
        row[QStringLiteral("author")] = q.value(9).toString();
        row[QStringLiteral("coverImagePath")] = q.value(10).toString();
        row[QStringLiteral("open")] = q.value(5).toString().isEmpty();
        out.append(row);
    }
    return out;
}

QVariantList LoanManager::openLoans() const
{
    // Longest out first: the one most likely to have been forgotten is the one
    // worth putting at the top.
    return query(QStringLiteral("l.returned_on IS NULL"),
                 QStringLiteral("l.loaned_on ASC, l.id ASC"));
}

QVariantList LoanManager::history() const
{
    return query(QStringLiteral("l.returned_on IS NOT NULL"),
                 QStringLiteral("l.returned_on DESC, l.id DESC"));
}

QVariantList LoanManager::forBook(int bookId) const
{
    return query(QStringLiteral("l.book_id = ?"),
                 QStringLiteral("l.loaned_on DESC, l.id DESC"), { bookId });
}

QVariantMap LoanManager::openLoanFor(int bookId) const
{
    const QVariantList rows = query(
        QStringLiteral("l.book_id = ? AND l.returned_on IS NULL"),
        QStringLiteral("l.id DESC"), { bookId });
    return rows.isEmpty() ? QVariantMap() : rows.first().toMap();
}

QStringList LoanManager::people() const
{
    QSqlQuery q(DatabaseManager::instance().database());
    if (!q.exec(QStringLiteral(
            "SELECT DISTINCT counterparty FROM book_loans ORDER BY counterparty"))) {
        qWarning() << "loans: cannot read names:" << q.lastError().text();
        return {};
    }

    QStringList out;
    while (q.next())
        out.append(q.value(0).toString());
    return out;
}
