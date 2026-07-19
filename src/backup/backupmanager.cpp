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

    // Mirrors verifyArchive()'s standard for what a well-formed archive contains:
    // both the dump and the manifest must be present in the listing. A dump with no
    // manifest is not an archive this app ever produced.
    const QString listing = QString::fromUtf8(list.readAllStandardOutput());
    if (!listing.contains(QStringLiteral("database.sql"))
        || !listing.contains(QStringLiteral("manifest.json"))) {
        result["error"] = QStringLiteral("Archive is missing database.sql or manifest.json");
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

    // 3. Require the dump to actually hold book data before spending a trial load on
    //    it. verifyArchive() (used when writing a backup) demands a COPY block for
    //    every table that currently exists, but inspectArchive() only requires
    //    "books" — the one table that has existed since the very first backup format.
    //    An archive made before "challenges" or "reading_sessions" existed is still a
    //    legitimate, restorable BookWorm backup and must not be rejected for lacking
    //    tables its own app version never wrote. Anything lacking book data at all,
    //    though, is not a BookWorm backup regardless of vintage.
    const QString dumpPath = temp.filePath(QStringLiteral("database.sql"));
    QFile dumpFile(dumpPath);
    if (!dumpFile.open(QIODevice::ReadOnly)) {
        result["error"] = QStringLiteral("Could not read database.sql after unpacking");
        return result;
    }
    const QString dumpContents = QString::fromUtf8(dumpFile.readAll());
    dumpFile.close();
    if (!dumpContents.contains(QStringLiteral("COPY public.books "))) {
        result["error"] =
            QStringLiteral("Archive does not contain book data (no COPY public.books block)");
        return result;
    }

    // 4. Trial load into a scratch database. This is the moment a corrupt dump is
    //    caught, and it happens while the real database is still untouched.
    const QString scratch = QStringLiteral("wormbook_restore_check");
    dropScratchDatabase(scratch);   // in case a previous run died mid-way

    QString error;
    if (!runProcess(m_createdbPath, connectionArgs() << scratch, &error)) {
        result["error"] = QStringLiteral("Could not create a scratch database: ") + error;
        return result;
    }

    // --single-transaction mirrors the real load in restoreFrom(): the trial should
    // behave exactly like the load it is standing in for. It costs nothing extra
    // here either way — the scratch database is dropped a few lines down regardless
    // of whether the load fully succeeded or partially landed before an error.
    const bool loaded = runProcess(
        m_psqlPath,
        connectionArgs()
            << QStringLiteral("--quiet")
            << QStringLiteral("--single-transaction")
            << QStringLiteral("--set=ON_ERROR_STOP=1")
            << QStringLiteral("--dbname=") + scratch
            << QStringLiteral("--file=") + dumpPath,
        &error);

    if (!loaded) {
        dropScratchDatabase(scratch);
        result["error"] = QStringLiteral("Archive could not be loaded: ") + error;
        return result;
    }

    // 5. Count what arrived.
    result["bookCount"] = scratchBookCount(scratch);
    dropScratchDatabase(scratch);
    result["valid"] = true;
    result["error"] = QString();
    return result;
}

// Replaces wormbook with the contents of an archive. This is the one operation in
// the app that can destroy the user's library, so the order below is deliberate and
// must not be reordered: a safety copy is on disk, verified, before anything is
// dropped, and every failure message from that point on carries its path so a bad
// run is always recoverable by hand even if the UI is gone.
bool BackupManager::restoreFrom(const QString &filePath)
{
    QString path = filePath;
    if (path.startsWith(QStringLiteral("file://")))
        path = QUrl(path).toLocalFile();

    // 0. Prove the archive loads cleanly into a scratch database before this function
    //    does anything else. The QML flow already calls inspectArchive() itself
    //    (dialog "Restore from Backup" → inspect → confirm → restoreFrom), but this
    //    function must not depend on a caller having done that — the guiding
    //    invariant is "the current database is not touched until the archive has
    //    been proven to load", and that has to hold no matter who calls restoreFrom().
    //    Calling inspectArchive() here means the dump gets loaded a third time before
    //    this is done (inspect dialog, this check, the real load below) — a few extra
    //    seconds against the guarantee that a corrupt archive can never reach the
    //    DROP SCHEMA further down. That trade is accepted.
    const QVariantMap inspection = inspectArchive(filePath);
    if (!inspection.value(QStringLiteral("valid")).toBool()) {
        emit restoreFinished(false, inspection.value(QStringLiteral("error")).toString());
        return false;
    }

    if (m_psqlPath.isEmpty()) {
        emit restoreFinished(false, QStringLiteral("psql not found — restore unavailable"));
        return false;
    }

    // 1. Safety backup FIRST. If this fails, nothing destructive has happened and we
    //    must not proceed — restoring without a fresh, verified copy of the current
    //    library would mean a bad archive could destroy data with no way back.
    const QString timestamp =
        QDateTime::currentDateTime().toString(QStringLiteral("yyyyMMdd-HHmmss"));
    const QString safetyPath =
        safetyBackupDir() + QStringLiteral("/before-restore-%1.zip").arg(timestamp);
    if (!backupTo(safetyPath)) {
        const QString message = QStringLiteral(
            "Could not create a safety backup before restoring — restore aborted, "
            "nothing was changed. (attempted: %1)").arg(safetyPath);
        emit restoreFinished(false, message);
        return false;
    }

    QString error;

    // 2. Unpack the archive.
    QTemporaryDir temp;
    if (!temp.isValid()) {
        emit restoreFinished(false, QStringLiteral(
            "Could not create a temporary directory — nothing was changed. "
            "(safety backup: %1)").arg(safetyPath));
        return false;
    }

    if (!runProcess(QStringLiteral("/usr/bin/unzip"),
                    {QStringLiteral("-q"), QStringLiteral("-o"), path,
                     QStringLiteral("-d"), temp.path()},
                    &error)) {
        emit restoreFinished(false, QStringLiteral(
            "Archive could not be unpacked — nothing was changed: %1 "
            "(safety backup: %2)").arg(error, safetyPath));
        return false;
    }

    const QString dumpFile = temp.filePath(QStringLiteral("database.sql"));
    if (!QFileInfo::exists(dumpFile)) {
        emit restoreFinished(false, QStringLiteral(
            "Archive does not contain database.sql — nothing was changed. "
            "(safety backup: %1)").arg(safetyPath));
        return false;
    }

    // 3. Drop and recreate the schema. psql sends "DROP ...; CREATE ...;" as a single
    //    simple-query message, which Postgres runs as one implicit transaction — if
    //    this fails, the drop is rolled back and wormbook is untouched.
    if (!runProcess(m_psqlPath,
                    connectionArgs()
                        << QStringLiteral("--quiet")
                        << QStringLiteral("--set=ON_ERROR_STOP=1")
                        << QStringLiteral("--dbname=") + QString::fromLatin1(BookWorm::Config::DB_NAME)
                        << QStringLiteral("--command=DROP SCHEMA public CASCADE; CREATE SCHEMA public;"),
                    &error)) {
        emit restoreFinished(false, QStringLiteral(
            "Could not reset the database schema, so nothing was changed: %1 "
            "(safety backup: %2)").arg(error, safetyPath));
        return false;
    }

    // 4. Load the dump. This is the one window where the schema has already been
    //    dropped and the new data has not yet landed, so a failure here can leave
    //    wormbook empty — the message leads with the safety backup path rather than
    //    burying it. --single-transaction wraps the whole dump in one transaction:
    //    plain-text pg_dump output is not one transaction by default, so without this
    //    flag a failure partway through leaves some tables committed and others not —
    //    an arbitrary partial state. With it, any failure rolls back to the empty
    //    schema CREATE SCHEMA left in step 3, so there is exactly one well-defined
    //    recovery state instead of an unknown mixture.
    if (!runProcess(m_psqlPath,
                    connectionArgs()
                        << QStringLiteral("--quiet")
                        << QStringLiteral("--single-transaction")
                        << QStringLiteral("--set=ON_ERROR_STOP=1")
                        << QStringLiteral("--dbname=") + QString::fromLatin1(BookWorm::Config::DB_NAME)
                        << QStringLiteral("--file=") + dumpFile,
                    &error)) {
        emit restoreFinished(false, QStringLiteral(
            "SAFETY BACKUP: %1\n\nThe archive failed to load: %2. Because the load runs "
            "as a single transaction, it was rolled back — the database is now empty "
            "(not partially restored). Restore the safety backup above by hand as soon "
            "as possible.").arg(safetyPath, error));
        return false;
    }

    // 5. The app's QSqlDatabase connection was opened before the schema was dropped
    //    and recreated underneath it. Tested against a scratch database: a plain,
    //    unprepared query on the still-open connection kept working after an
    //    external DROP/CREATE SCHEMA + reload from a second session (Postgres does
    //    not tie a simple-query-protocol SELECT to cached relation OIDs the way a
    //    server-side prepared statement can be). That doesn't cover every query this
    //    app runs — DatabaseManager also issues parameterized, prepared queries
    //    elsewhere — so rather than trust an untested case, the connection is closed
    //    and reopened here. Reconnecting was tested the same way and also worked.
    DatabaseManager::instance().disconnect();
    if (!DatabaseManager::instance().connect()) {
        emit restoreFinished(false, QStringLiteral(
            "The archive was loaded, but the app could not reconnect to the database "
            "afterwards. Restart BookWorm to continue. (safety backup: %1)").arg(safetyPath));
        return false;
    }

    // 6. Bring the schema up to date. Safe to call on a populated database — every
    //    statement in initializeSchema() is IF NOT EXISTS / IF EXISTS guarded, since
    //    it already runs unconditionally on every normal launch.
    DatabaseManager::instance().initializeSchema();

    // 7. Restore covers. Never aborts: the database itself is already fully restored
    //    by this point, so a bad cover file must only be counted, not treated as a
    //    reason to report failure.
    int coversRestored = 0;
    int coversFailed = 0;
    restoreCoversFromArchive(temp.path(), &coversRestored, &coversFailed);

    int bookCount = 0;
    {
        QSqlQuery q(DatabaseManager::instance().database());
        if (q.exec(QStringLiteral("SELECT count(*) FROM books")) && q.next())
            bookCount = q.value(0).toInt();
        else
            qWarning() << "restoreFrom: post-restore book count query failed:" << q.lastError().text();
    }

    QString message = QStringLiteral("Restored %1 books").arg(bookCount);
    if (coversRestored > 0)
        message += QStringLiteral(", %1 covers").arg(coversRestored);
    if (coversFailed > 0)
        message += QStringLiteral(" (%1 covers could not be restored)").arg(coversFailed);
    message += QStringLiteral(". Safety backup saved to %1").arg(safetyPath);

    emit restoreFinished(true, message);
    return true;
}

// Archived covers are named "<bookId>.<ext>" by copyCovers() in backupTo(), so the
// book id can be recovered from the file name alone without reading the manifest.
void BackupManager::restoreCoversFromArchive(const QString &unpackedDir, int *restored, int *failed)
{
    *restored = 0;
    *failed = 0;

    const QString coversSrcDir = unpackedDir + QStringLiteral("/covers");
    QDir srcDir(coversSrcDir);
    if (!srcDir.exists())
        return; // Archive had no covers section; that is not a failure.

    const QString coversDestDir =
        QStandardPaths::writableLocation(QStandardPaths::AppDataLocation)
        + QStringLiteral("/covers");
    if (!QDir().mkpath(coversDestDir)) {
        qWarning() << "restoreCoversFromArchive could not create" << coversDestDir;
        *failed = srcDir.entryList(QDir::Files).size();
        return;
    }

    const QSqlDatabase db = DatabaseManager::instance().database();
    const QStringList entries = srcDir.entryList(QDir::Files, QDir::Name);

    for (const QString &fileName : entries) {
        const int dot = fileName.lastIndexOf(QLatin1Char('.'));
        const QString stem = dot >= 0 ? fileName.left(dot) : fileName;

        bool ok = false;
        const int bookId = stem.toInt(&ok);
        if (!ok) {
            qWarning() << "restoreCoversFromArchive: unexpected file name" << fileName;
            ++(*failed);
            continue;
        }

        const QString destPath = coversDestDir + QLatin1Char('/') + fileName;
        QFile::remove(destPath); // Overwrite anything left behind by a previous restore.
        if (!QFile::copy(coversSrcDir + QLatin1Char('/') + fileName, destPath)) {
            qWarning() << "restoreCoversFromArchive could not copy" << fileName;
            ++(*failed);
            continue;
        }

        QSqlQuery q(db);
        q.prepare(QStringLiteral("UPDATE books SET cover_image_path = :path WHERE id = :id"));
        q.bindValue(QStringLiteral(":path"), destPath);
        q.bindValue(QStringLiteral(":id"), bookId);
        if (!q.exec()) {
            qWarning() << "restoreCoversFromArchive UPDATE failed for book" << bookId
                       << ":" << q.lastError().text();
            ++(*failed);
            continue;
        }

        ++(*restored);
    }
}
