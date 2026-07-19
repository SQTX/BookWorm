#include "backupmanager.h"

#include "../constants.h"
#include "../database/databasemanager.h"

#include <filesystem>
#include <system_error>

#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonDocument>
#include <QProcess>
#include <QSqlDatabase>
#include <QSqlError>
#include <QSqlQuery>
#include <QStandardPaths>
#include <QTemporaryDir>
#include <QUrl>

BackupManager::BackupManager(QObject *parent)
    : QObject(parent)
    , m_pgDumpPath(locatePgDump())
    , m_psqlPath(locatePsql())
    , m_createdbPath(locateCreatedb())
    , m_dropdbPath(locateDropdb())
{
}

QString BackupManager::pgDumpPath() const
{
    return m_pgDumpPath;
}

QString BackupManager::psqlPath() const
{
    return m_psqlPath;
}

// <AppDataLocation>/safety-backups. Created on demand so a fresh install has
// somewhere to put the pre-restore safety copy without a separate setup step.
QString BackupManager::safetyBackupDir() const
{
    const QString base =
        QStandardPaths::writableLocation(QStandardPaths::AppDataLocation);
    const QString dir = base + QStringLiteral("/safety-backups");
    QDir().mkpath(dir);
    return dir;
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

// Mirrors locatePgDump(): PATH first, then the same Homebrew locations pg_dump is
// found at, since all four postgresql@16 client binaries live side by side.
QString BackupManager::locatePsql() const
{
    const QString fromPath = QStandardPaths::findExecutable(QStringLiteral("psql"));
    if (!fromPath.isEmpty())
        return fromPath;

    const QStringList candidates = {
        QStringLiteral("/opt/homebrew/opt/postgresql@16/bin/psql"),
        QStringLiteral("/opt/homebrew/bin/psql"),
        QStringLiteral("/usr/local/bin/psql"),
        QStringLiteral("/usr/bin/psql")
    };

    for (const QString &candidate : candidates) {
        if (QFileInfo(candidate).isExecutable())
            return candidate;
    }

    return {};
}

// Mirrors locatePgDump(). createdb is used (rather than
// "psql --command=CREATE DATABASE ... postgres") so scratch-database creation goes
// through the same discovery/runProcess pattern as every other tool call here,
// instead of introducing a special-cased connection to the "postgres" database.
QString BackupManager::locateCreatedb() const
{
    const QString fromPath = QStandardPaths::findExecutable(QStringLiteral("createdb"));
    if (!fromPath.isEmpty())
        return fromPath;

    const QStringList candidates = {
        QStringLiteral("/opt/homebrew/opt/postgresql@16/bin/createdb"),
        QStringLiteral("/opt/homebrew/bin/createdb"),
        QStringLiteral("/usr/local/bin/createdb"),
        QStringLiteral("/usr/bin/createdb")
    };

    for (const QString &candidate : candidates) {
        if (QFileInfo(candidate).isExecutable())
            return candidate;
    }

    return {};
}

// Mirrors locatePgDump(). dropdb is needed alongside createdb to clean up the
// scratch database inspectArchive() creates.
QString BackupManager::locateDropdb() const
{
    const QString fromPath = QStandardPaths::findExecutable(QStringLiteral("dropdb"));
    if (!fromPath.isEmpty())
        return fromPath;

    const QStringList candidates = {
        QStringLiteral("/opt/homebrew/opt/postgresql@16/bin/dropdb"),
        QStringLiteral("/opt/homebrew/bin/dropdb"),
        QStringLiteral("/usr/local/bin/dropdb"),
        QStringLiteral("/usr/bin/dropdb")
    };

    for (const QString &candidate : candidates) {
        if (QFileInfo(candidate).isExecutable())
            return candidate;
    }

    return {};
}

QStringList BackupManager::connectionArgs() const
{
    return {
        QStringLiteral("--host=%1").arg(QString::fromLatin1(BookWorm::Config::DB_HOST)),
        QStringLiteral("--port=%1").arg(BookWorm::Config::DB_PORT),
        QStringLiteral("--username=%1").arg(QString::fromLatin1(BookWorm::Config::DB_USER))
    };
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
    if (!QDir().mkpath(coversDir)) {
        // Without this check every copy below fails and all covers get reported as
        // "missing", which reads like broken image paths rather than the real cause.
        qWarning() << "copyCovers could not create" << coversDir;
        return false;
    }
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

        const QString suffix = info.suffix().toLower();
        const QString archivedName = suffix.isEmpty()
            ? QString::number(bookId)
            : QStringLiteral("%1.%2").arg(bookId).arg(suffix);
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

    // Checking only that the name appears would pass an archive holding an empty or
    // wrong dump — pg_dump can exit 0 and still produce nothing useful if it were
    // ever pointed at the wrong database. Read the dump back out and require a COPY
    // block for every table, so "verified" means the data is actually in there.
    QProcess extract;
    extract.start(QStringLiteral("/usr/bin/unzip"),
                  {QStringLiteral("-p"), zipPath, QStringLiteral("database.sql")});
    if (!extract.waitForFinished(60000) || extract.exitCode() != 0) {
        if (errorOut)
            *errorOut = QStringLiteral("database.sql could not be read back from the archive");
        return false;
    }

    const QString dump = QString::fromUtf8(extract.readAllStandardOutput());
    if (dump.trimmed().isEmpty()) {
        if (errorOut)
            *errorOut = QStringLiteral("database.sql in the archive is empty");
        return false;
    }

    const QStringList expectedTables = {
        QStringLiteral("books"),
        QStringLiteral("tags"),
        QStringLiteral("book_tags"),
        QStringLiteral("favorite_quotes"),
        QStringLiteral("challenges"),
        QStringLiteral("highlights"),
        QStringLiteral("reading_sessions")
    };

    for (const QString &table : expectedTables) {
        if (!dump.contains(QStringLiteral("COPY public.%1 ").arg(table))) {
            if (errorOut)
                *errorOut = QStringLiteral("Archive is missing table data for %1").arg(table);
            return false;
        }
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
    // Taken from the same config the app connects with, so the two cannot drift.
    // Hardcoding them here would let the backup keep dumping the old database after
    // a connection change, and nothing would say so.
    const QStringList dumpArgs = {
        QStringLiteral("--host=%1").arg(QString::fromLatin1(BookWorm::Config::DB_HOST)),
        QStringLiteral("--port=%1").arg(BookWorm::Config::DB_PORT),
        QStringLiteral("--username=%1").arg(QString::fromLatin1(BookWorm::Config::DB_USER)),
        QStringLiteral("--no-owner"),
        QStringLiteral("--no-privileges"),
        QStringLiteral("--file=") + stagingDir + QStringLiteral("/database.sql"),
        QString::fromLatin1(BookWorm::Config::DB_NAME)
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

    // std::filesystem::rename replaces the destination atomically. QFile::rename
    // refuses to overwrite, which would force a remove() first — and if the rename
    // then failed, the previous good backup would already be gone.
    std::error_code renameError;
    std::filesystem::rename(std::filesystem::path(partPath.toStdString()),
                            std::filesystem::path(destination.toStdString()),
                            renameError);
    if (renameError) {
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

void BackupManager::dropScratchDatabase(const QString &name)
{
    if (m_dropdbPath.isEmpty()) {
        qWarning() << "dropScratchDatabase: dropdb not found, cannot drop" << name;
        return;
    }

    QString error;
    if (!runProcess(m_dropdbPath, connectionArgs() << QStringLiteral("--if-exists") << name, &error))
        qWarning() << "dropScratchDatabase failed for" << name << ":" << error;
}

// Opens a throwaway QSqlDatabase connection under a name distinct from the
// application's default connection ("qt_sql_default_connection"), so this can never
// displace DatabaseManager's live connection to wormbook. The QSqlDatabase value
// itself must go out of scope before removeDatabase() is called, or Qt warns that
// the connection is still in use — hence the inner block.
int BackupManager::scratchBookCount(const QString &name)
{
    const QString connectionName = QStringLiteral("restore_check");
    int count = 0;

    {
        QSqlDatabase db = QSqlDatabase::addDatabase(
            QString::fromLatin1(BookWorm::Config::DB_DRIVER), connectionName);
        db.setHostName(QString::fromLatin1(BookWorm::Config::DB_HOST));
        db.setPort(BookWorm::Config::DB_PORT);
        db.setDatabaseName(name);
        db.setUserName(QString::fromLatin1(BookWorm::Config::DB_USER));
        db.setPassword(QString::fromLatin1(BookWorm::Config::DB_PASSWORD));

        if (db.open()) {
            QSqlQuery q(db);
            if (q.exec(QStringLiteral("SELECT count(*) FROM books")) && q.next())
                count = q.value(0).toInt();
            else
                qWarning() << "scratchBookCount query failed:" << q.lastError().text();
        } else {
            qWarning() << "scratchBookCount could not open" << name << ":" << db.lastError().text();
        }
    }

    QSqlDatabase::removeDatabase(connectionName);
    return count;
}

// Validates an archive and trial-loads it into a scratch database purely to find out
// what it holds. Every exit path — including every failure — drops the scratch
// database before returning, so this never leaves state behind and never touches
// wormbook.
QVariantMap BackupManager::inspectArchive(const QString &filePath)
{
    QVariantMap result;
    result["valid"]     = false;
    result["bookCount"] = 0;
    result["hasCovers"] = false;

    QString path = filePath;
    if (path.startsWith(QStringLiteral("file://")))
        path = QUrl(path).toLocalFile();

    if (m_psqlPath.isEmpty()) {
        result["error"] = QStringLiteral("psql not found — restore unavailable");
        return result;
    }
    if (m_createdbPath.isEmpty()) {
        result["error"] = QStringLiteral("createdb not found — restore unavailable");
        return result;
    }

    // 1. The archive opens and holds what it must.
    QProcess list;
    list.start(QStringLiteral("/usr/bin/unzip"), {QStringLiteral("-l"), path});
    if (!list.waitForFinished(30000) || list.exitCode() != 0) {
        result["error"] = QStringLiteral("File is not a readable ZIP archive");
        return result;
    }

    const QString listing = QString::fromUtf8(list.readAllStandardOutput());
    if (!listing.contains(QStringLiteral("database.sql"))) {
        result["error"] = QStringLiteral("Archive does not contain database.sql");
        return result;
    }
    result["hasCovers"] = listing.contains(QStringLiteral("covers/"));

    // 2. Unpack to a temporary directory.
    QTemporaryDir temp;
    if (!temp.isValid()) {
        result["error"] = QStringLiteral("Could not create a temporary directory");
        return result;
    }

    QString unpackError;
    if (!runProcess(QStringLiteral("/usr/bin/unzip"),
                    {QStringLiteral("-q"), QStringLiteral("-o"), path,
                     QStringLiteral("-d"), temp.path()},
                    &unpackError)) {
        result["error"] = QStringLiteral("Archive could not be unpacked");
        return result;
    }

    // 3. Trial load into a scratch database. This is the moment a corrupt dump is
    //    caught, and it happens while the real database is still untouched.
    const QString scratch = QStringLiteral("wormbook_restore_check");
    dropScratchDatabase(scratch);   // in case a previous run died mid-way

    QString error;
    if (!runProcess(m_createdbPath, connectionArgs() << scratch, &error)) {
        result["error"] = QStringLiteral("Could not create a scratch database: ") + error;
        return result;
    }

    const bool loaded = runProcess(
        m_psqlPath,
        connectionArgs()
            << QStringLiteral("--quiet")
            << QStringLiteral("--set=ON_ERROR_STOP=1")
            << QStringLiteral("--dbname=") + scratch
            << QStringLiteral("--file=") + temp.filePath(QStringLiteral("database.sql")),
        &error);

    if (!loaded) {
        dropScratchDatabase(scratch);
        result["error"] = QStringLiteral("Archive could not be loaded: ") + error;
        return result;
    }

    // 4. Count what arrived.
    result["bookCount"] = scratchBookCount(scratch);
    dropScratchDatabase(scratch);
    result["valid"] = true;
    result["error"] = QString();
    return result;
}
