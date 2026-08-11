#pragma once

#include <QJsonArray>
#include <QJsonObject>
#include <QSqlDatabase>
#include <QString>

/**
 * Translates between the local database and the shape `/v1/sync` speaks.
 *
 * Kept out of DatabaseManager on purpose. That class is already 1400 lines and
 * is what every view reads through; sync is a second consumer with different
 * needs — it wants rows by UUID including ones the UI never shows, and it must
 * write rows the user did not create. Mixing the two would put "is this a sync
 * write or a user write?" into methods that currently do not have to care.
 *
 * Field names match the server's `books/schemas.js`, which in turn matches
 * `Book::toVariantMap()`. Three places agree by construction rather than by
 * anyone remembering.
 */
class SyncRepository
{
public:
    explicit SyncRepository(QSqlDatabase db);

    /** Everything this machine holds, in push order — books before the rows
     *  that reference them. */
    QJsonObject collectAll() const;

    /** Only what changed since the last successful sync, plus tombstones. */
    QJsonObject collectChangedSince(const QDateTime &since) const;

    /** Apply a `changes` object from the server. @returns rows written. */
    int applyChanges(const QJsonObject &changes);

    /** Deletions waiting to be told to the server. */
    QJsonArray pendingTombstones() const;

    /** Forget tombstones the server has accepted. */
    void clearTombstones(const QJsonArray &tombstones);

    int bookCount() const;

private:
    QJsonArray collectBooks(const QDateTime &since) const;
    QJsonArray collectSessions(const QDateTime &since) const;
    QJsonArray collectTags(const QDateTime &since) const;
    QJsonArray collectQuotes(const QDateTime &since) const;
    QJsonArray collectHighlights(const QDateTime &since) const;
    QJsonArray collectChallenges(const QDateTime &since) const;

    int applyBooks(const QJsonArray &rows);
    int applySessions(const QJsonArray &rows);
    int applyTags(const QJsonArray &rows);

    /** @returns the local id for a book UUID, or -1. */
    int bookIdForUuid(const QString &uuid) const;

    QSqlDatabase m_db;
};
