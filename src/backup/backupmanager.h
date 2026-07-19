#pragma once

#include <QObject>
#include <QQmlEngine>
#include <QString>
#include <QVariantList>

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

signals:
    void backupFinished(bool ok, const QString &message);

private:
    QString locatePgDump() const;
    QString locatePsql() const;

    bool runProcess(const QString &program, const QStringList &arguments, QString *errorOut);
    bool copyCovers(const QString &coversDir, QVariantList *entries, int *missing);
    bool writeManifest(const QString &path, const QVariantList &covers, int missing);
    bool verifyArchive(const QString &zipPath, int expectedCovers, QString *errorOut);

    QString m_pgDumpPath;
    QString m_psqlPath;
};
