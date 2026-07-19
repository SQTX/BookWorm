#pragma once

#include <QObject>
#include <QQmlEngine>
#include <QString>
#include <QVariantList>
#include <QVariantMap>

class BackupManager : public QObject
{
    Q_OBJECT
    QML_ELEMENT

public:
    explicit BackupManager(QObject *parent = nullptr);

    // Absolute path to pg_dump, or an empty string when it cannot be found.
    // Exposed so the UI can explain why backup is unavailable instead of failing later.
    Q_INVOKABLE QString pgDumpPath() const;

    // Absolute path to psql, or empty when it cannot be found.
    Q_INVOKABLE QString psqlPath() const;

    // Directory the app writes safety backups into. Created on demand.
    Q_INVOKABLE QString safetyBackupDir() const;

    // Writes a complete archive to filePath. Emits backupFinished with a message
    // describing what happened, and returns the same success value.
    Q_INVOKABLE bool backupTo(const QString &filePath);

    // Validates an archive and trial-loads it into a scratch database to find out
    // what it holds. Never touches the live database. Returns:
    //   valid (bool), error (QString), bookCount (int), hasCovers (bool)
    Q_INVOKABLE QVariantMap inspectArchive(const QString &filePath);

signals:
    void backupFinished(bool ok, const QString &message);

private:
    QString locatePgDump() const;
    QString locatePsql() const;
    QString locateCreatedb() const;
    QString locateDropdb() const;

    bool runProcess(const QString &program, const QStringList &arguments, QString *errorOut);
    bool copyCovers(const QString &coversDir, QVariantList *entries, int *missing);
    bool writeManifest(const QString &path, const QVariantList &covers, int missing);
    bool verifyArchive(const QString &zipPath, int expectedCovers, QString *errorOut);

    // Best-effort cleanup of a scratch database created for inspection. Never fatal —
    // "--if-exists" means this is safe to call whether or not the database was ever
    // created, including on early-exit paths.
    void dropScratchDatabase(const QString &name);

    // Opens a short-lived QSqlDatabase connection under a name distinct from the
    // application's default connection, counts books, then closes and removes it.
    int scratchBookCount(const QString &name);

    QString m_pgDumpPath;
    QString m_psqlPath;
    QString m_createdbPath;
    QString m_dropdbPath;
};
