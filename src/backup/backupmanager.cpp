#include "backupmanager.h"

#include "../database/databasemanager.h"

#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonDocument>
#include <QProcess>
#include <QSqlError>
#include <QSqlQuery>
#include <QStandardPaths>
#include <QTemporaryDir>
#include <QUrl>

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

bool BackupManager::runProcess(const QString &program, const QStringList &arguments,
                               QString *errorOut)
{
    QProcess process;
    process.start(program, arguments);

    if (!process.waitForStarted(5000)) {
        if (errorOut)
            *errorOut = QStringLiteral("Could not start %1").arg(program);
        return false;
    }

    // Generous: a dump of a large library legitimately takes a while.
    if (!process.waitForFinished(120000)) {
        process.kill();
        if (errorOut)
            *errorOut = QStringLiteral("%1 timed out").arg(program);
        return false;
    }

    if (process.exitStatus() != QProcess::NormalExit || process.exitCode() != 0) {
        if (errorOut) {
            const QString stderrText = QString::fromUtf8(process.readAllStandardError()).trimmed();
            *errorOut = QStringLiteral("%1 failed: %2").arg(program, stderrText);
        }
        return false;
    }

    return true;
}

// Covers are named by book id so per-year duplicates cannot overwrite each other.
// A missing source file is recorded, not fatal — a broken image path must not cost
// the user their database dump.
bool BackupManager::copyCovers(const QString &coversDir, QVariantList *entries, int *missing)
{
    QDir().mkpath(coversDir);
    *missing = 0;

    QSqlQuery q(DatabaseManager::instance().database());
    if (!q.exec("SELECT id, cover_image_path FROM books "
                "WHERE cover_image_path IS NOT NULL AND cover_image_path <> ''")) {
        qWarning() << "copyCovers query failed:" << q.lastError().text();
        return false;
    }

    while (q.next()) {
        const int bookId = q.value(0).toInt();
        QString sourcePath = q.value(1).toString();
        if (sourcePath.startsWith(QStringLiteral("file://")))
            sourcePath = QUrl(sourcePath).toLocalFile();

        QVariantMap entry;
        entry["bookId"]       = bookId;
        entry["originalPath"] = sourcePath;

        const QFileInfo info(sourcePath);
        if (!info.exists() || !info.isFile()) {
            entry["archived"] = false;
            ++(*missing);
            entries->append(entry);
            continue;
        }

        const QString archivedName =
            QStringLiteral("%1.%2").arg(bookId).arg(info.suffix().toLower());
        if (!QFile::copy(sourcePath, coversDir + QLatin1Char('/') + archivedName)) {
            entry["archived"] = false;
            ++(*missing);
            entries->append(entry);
            continue;
        }

        entry["archived"]     = true;
        entry["archivedName"] = archivedName;
        entries->append(entry);
    }

    return true;
}

bool BackupManager::writeManifest(const QString &path, const QVariantList &covers, int missing)
{
    QVariantMap manifest;
    manifest["app"]           = QStringLiteral("BookWorm");
    manifest["createdAt"]     = QDateTime::currentDateTime().toString(Qt::ISODate);
    manifest["database"]      = QStringLiteral("wormbook");
    manifest["coversTotal"]   = covers.size();
    manifest["coversMissing"] = missing;
    manifest["covers"]        = covers;

    QFile file(path);
    if (!file.open(QIODevice::WriteOnly)) {
        qWarning() << "writeManifest could not open" << path;
        return false;
    }

    file.write(QJsonDocument::fromVariant(manifest).toJson(QJsonDocument::Indented));
    file.close();
    return true;
}

// Restore is out of scope, so these archives are unproven until someone needs one.
// This narrows the gap: it confirms the file is well-formed, though not that it
// reconstitutes the database. Say exactly that in any message shown to the user.
bool BackupManager::verifyArchive(const QString &zipPath, int expectedCovers, QString *errorOut)
{
    QProcess unzip;
    unzip.start(QStringLiteral("/usr/bin/unzip"), {QStringLiteral("-l"), zipPath});
    if (!unzip.waitForFinished(30000) || unzip.exitCode() != 0) {
        if (errorOut)
            *errorOut = QStringLiteral("Archive could not be opened after writing");
        return false;
    }

    const QString listing = QString::fromUtf8(unzip.readAllStandardOutput());

    if (!listing.contains(QStringLiteral("database.sql"))
        || !listing.contains(QStringLiteral("manifest.json"))) {
        if (errorOut)
            *errorOut = QStringLiteral("Archive is missing database.sql or manifest.json");
        return false;
    }

    // `unzip -l` lists one line per entry, including a line for the "covers/"
    // directory itself (created because zip -r archived "." recursively). Each
    // cover file line reads "covers/<name>", so counting occurrences of "covers/"
    // over-counts by exactly one (the directory entry). Confirmed empirically by
    // building a test archive with N cover files and observing N+1 matching lines
    // (see Task 2 Step 8 in the implementation plan) — this is not a guess.
    const int archivedCovers = listing.count(QStringLiteral("covers/")) - 1;
    if (archivedCovers < expectedCovers) {
        if (errorOut) {
            *errorOut = QStringLiteral("Archive holds %1 covers, expected %2")
                            .arg(archivedCovers).arg(expectedCovers);
        }
        return false;
    }

    return true;
}

bool BackupManager::backupTo(const QString &filePath)
{
    QString destination = filePath;
    if (destination.startsWith(QStringLiteral("file://")))
        destination = QUrl(destination).toLocalFile();

    if (m_pgDumpPath.isEmpty()) {
        const QString message =
            QStringLiteral("pg_dump not found — cannot create a backup");
        emit backupFinished(false, message);
        return false;
    }

    QTemporaryDir temp;
    if (!temp.isValid()) {
        emit backupFinished(false, QStringLiteral("Could not create a temporary directory"));
        return false;
    }

    const QString stagingDir = temp.filePath(QStringLiteral("bookworm-backup"));
    QDir().mkpath(stagingDir);

    // 1. Database dump
    QString error;
    const QStringList dumpArgs = {
        QStringLiteral("--host=localhost"),
        QStringLiteral("--port=5432"),
        QStringLiteral("--username=sqtx"),
        QStringLiteral("--no-owner"),
        QStringLiteral("--no-privileges"),
        QStringLiteral("--file=") + stagingDir + QStringLiteral("/database.sql"),
        QStringLiteral("wormbook")
    };
    if (!runProcess(m_pgDumpPath, dumpArgs, &error)) {
        emit backupFinished(false, error);
        return false;
    }

    // 2. Covers
    QVariantList coverEntries;
    int missingCovers = 0;
    if (!copyCovers(stagingDir + QStringLiteral("/covers"), &coverEntries, &missingCovers)) {
        emit backupFinished(false, QStringLiteral("Could not read cover paths"));
        return false;
    }

    // 3. Manifest
    if (!writeManifest(stagingDir + QStringLiteral("/manifest.json"), coverEntries, missingCovers)) {
        emit backupFinished(false, QStringLiteral("Could not write the manifest"));
        return false;
    }

    // 4. Zip. Run from inside the staging directory so archive paths stay relative.
    const QString stagedZip = temp.filePath(QStringLiteral("backup.zip"));
    QProcess zip;
    zip.setWorkingDirectory(stagingDir);
    zip.start(QStringLiteral("/usr/bin/zip"),
              {QStringLiteral("-r"), QStringLiteral("-q"), stagedZip, QStringLiteral(".")});
    if (!zip.waitForFinished(120000) || zip.exitCode() != 0) {
        emit backupFinished(false, QStringLiteral("Could not create the archive"));
        return false;
    }

    // 5. Verify before it reaches the destination
    const int expectedCovers = coverEntries.size() - missingCovers;
    if (!verifyArchive(stagedZip, expectedCovers, &error)) {
        emit backupFinished(false, error);
        return false;
    }

    // 6. Move into place, replacing any existing file at that path.
    //
    // Copy to a ".part" file next to the destination first, then rename over the
    // destination only once that copy has fully succeeded. This does two things:
    // it avoids QFile::rename across filesystems (the temp dir is often on a
    // different one than the destination — QFile::rename fails in that case), and
    // it means a failed or partial copy never touches the destination path, so an
    // existing good backup is never destroyed by a subsequent failed one.
    const QString partPath = destination + QStringLiteral(".part");
    QFile::remove(partPath);
    if (!QFile::copy(stagedZip, partPath)) {
        QFile::remove(partPath);
        emit backupFinished(false, QStringLiteral("Could not write to ") + destination);
        return false;
    }

    QFile::remove(destination);
    if (!QFile::rename(partPath, destination)) {
        QFile::remove(partPath);
        emit backupFinished(false, QStringLiteral("Could not write to ") + destination);
        return false;
    }

    QString message = QStringLiteral("Backup saved: %1 covers").arg(expectedCovers);
    if (missingCovers > 0)
        message += QStringLiteral(", %1 missing").arg(missingCovers);

    emit backupFinished(true, message);
    return true;
}
