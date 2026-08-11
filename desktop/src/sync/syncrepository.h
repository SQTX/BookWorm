#pragma once

#include <QJsonArray>
#include <QJsonObject>
#include <QVector>
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

    /** One cover that has to move, in either direction. */
    struct CoverJob {
        int bookId = 0;
        QString path;   ///< Where the file is, or is going.
        QString hash;   ///< Empty when uploading — that is what comes back.
        QString supersedes;   ///< Mirror file this one replaces, if any.
    };

    /**
     * Books whose cover exists here but not on the server.
     *
     * A book qualifies when its file is readable and its recorded hash does not
     * match the file's contents, which covers both "never uploaded" and
     * "replaced since". The hash is recomputed from the bytes rather than
     * trusted, because nothing stops the user swapping the image behind the
     * application's back.
     *
     * One exception, and it matters: files this machine downloaded are skipped
     * outright, recognised by living in coverDir(). The server stores the hash
     * of what was *uploaded* and serves back a re-encoded WebP, so their bytes
     * hash differently from the name they were given. Hashing them would make
     * every downloaded cover look modified, upload it, receive a third hash,
     * and go round forever.
     */
    QVector<CoverJob> coversToUpload() const;

    /** Books that name a cover this machine does not have a file for. */
    QVector<CoverJob> coversToDownload() const;

    void setCoverHash(int bookId, const QString &hash);

    /**
     * Delete a mirror file that nothing needs any more.
     *
     * Does nothing when another book still points at it. Covers are shared by
     * content, so a file being superseded for one book is routinely still the
     * cover of another; deleting it would blank that one.
     */
    void retireMirror(const QString &path, int exceptBookId);

    /** Point a book at a freshly downloaded file, hash and path together. */
    void setCoverFile(int bookId, const QString &hash, const QString &path);

    /** SHA-256 of a file's contents, hex. Empty when it cannot be read. */
    static QString hashFile(const QString &path);

    /** Where downloaded covers live: <AppDataLocation>/covers. */
    static QString coverDir();

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
