#pragma once

#include <QObject>
#include <QQmlEngine>
#include <QString>

class BackupManager : public QObject
{
    Q_OBJECT
    QML_ELEMENT

public:
    explicit BackupManager(QObject *parent = nullptr);

    // Absolute path to pg_dump, or an empty string when it cannot be found.
    // Exposed so the UI can explain why backup is unavailable instead of failing later.
    Q_INVOKABLE QString pgDumpPath() const;

signals:
    void backupFinished(bool ok, const QString &message);

private:
    QString locatePgDump() const;

    QString m_pgDumpPath;
};
