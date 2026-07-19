#include "backupmanager.h"

#include <QFileInfo>
#include <QStandardPaths>

BackupManager::BackupManager(QObject *parent)
    : QObject(parent)
    , m_pgDumpPath(locatePgDump())
{
}

QString BackupManager::pgDumpPath() const
{
    return m_pgDumpPath;
}

// PATH first, then the Homebrew locations this machine actually uses. Hardcoding a
// single Cellar path is what broke plugin loading on every Qt upgrade; searching is
// deliberately more forgiving than that.
QString BackupManager::locatePgDump() const
{
    const QString fromPath = QStandardPaths::findExecutable(QStringLiteral("pg_dump"));
    if (!fromPath.isEmpty())
        return fromPath;

    const QStringList candidates = {
        QStringLiteral("/opt/homebrew/opt/postgresql@16/bin/pg_dump"),
        QStringLiteral("/opt/homebrew/bin/pg_dump"),
        QStringLiteral("/usr/local/bin/pg_dump"),
        QStringLiteral("/usr/bin/pg_dump")
    };

    for (const QString &candidate : candidates) {
        if (QFileInfo(candidate).isExecutable())
            return candidate;
    }

    return {};
}
