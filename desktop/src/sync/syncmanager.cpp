#include "syncmanager.h"
#include "syncrepository.h"
#include "keychain.h"
#include "../database/databasemanager.h"

#include <QFileInfo>
#include <memory>
#include <QDir>
#include <QThread>
#include <thread>
#include <QEventLoop>
#include <QFile>
#include <QJsonArray>
#include <QStandardPaths>
#include <QTextStream>
#include <QTimer>
#include <QSettings>

namespace {

constexpr const char *KEY_ENABLED = "sync/enabled";
constexpr const char *KEY_URL = "sync/serverUrl";
constexpr const char *KEY_EMAIL = "sync/email";
constexpr const char *KEY_CURSOR = "sync/cursor";

/** Held between the decision prompt and the user's answer. */
QJsonObject g_pendingServerChanges;
QString g_pendingServerTime;

/**
 * How long shutdown waits for an exchange. Long enough for a slow connection,
 * short enough that nobody wonders why the window will not close.
 */
constexpr int SHUTDOWN_SYNC_TIMEOUT_MS = 6000;

/**
 * How often the application exchanges with the server on its own.
 *
 * Two minutes is the compromise: fast enough that a page moved on the phone
 * appears here while the book is still in the reader's hand, slow enough that
 * an always-open window costs the server thirty requests an hour rather than
 * one every few seconds. Nothing is transferred when nothing changed — the
 * cursor sees to that.
 */
constexpr int AUTO_SYNC_INTERVAL_MS = 2 * 60 * 1000;

/**
 * How recent an exchange has to be for window activation to skip its own.
 * Activation fires on every alt-tab, and one request per accidental focus is
 * not a design.
 */
constexpr int ACTIVATION_QUIET_PERIOD_S = 20;

/**
 * Append a line to a log on disk.
 *
 * Launched as a bundle, the application's stderr goes somewhere nobody will
 * look — so a sync that quietly did nothing is indistinguishable from one that
 * worked, which is exactly the question being asked when something is wrong.
 *
 * WriteOnly matters: Append alone says where writes go, not that the device is
 * open for writing, and the open fails. An earlier version of this function got
 * that wrong and dropped every line, which read as "the code never ran" and
 * sent a whole afternoon in the wrong direction.
 */
void logSync(const QString &line)
{
    const QString dir = QStandardPaths::writableLocation(QStandardPaths::AppDataLocation);
    if (dir.isEmpty())
        return;
    QDir().mkpath(dir);

    QFile f(dir + QStringLiteral("/sync.log"));
    if (!f.open(QIODevice::WriteOnly | QIODevice::Append | QIODevice::Text))
        return;

    QTextStream(&f) << QDateTime::currentDateTime().toString(Qt::ISODate) << "  " << line << '\n';
}

} // namespace

SyncManager::SyncManager(QObject *parent)
    : QObject(parent)
{
    loadSettings();

    m_repo = new SyncRepository(DatabaseManager::instance().database());

    QObject::connect(&m_api, &ApiClient::sessionExpired, this, [this]() {
        setStatus(tr("Signed out — sign in again"));
    });

    m_autoSyncTimer = new QTimer(this);
    m_autoSyncTimer->setInterval(AUTO_SYNC_INTERVAL_MS);
    QObject::connect(m_autoSyncTimer, &QTimer::timeout, this, &SyncManager::autoSync);
    QObject::connect(this, &SyncManager::configChanged, this, &SyncManager::updateAutoSyncTimer);

    // Only cheap, local state here. Anything that can block — the Keychain
    // especially — waits until the interface exists.
    if (m_enabled && !m_email.isEmpty()) {
        m_api.setBaseUrl(m_serverUrl);
        setStatus(tr("Connected"));
    } else {
        setStatus(QString());
    }
    updateAutoSyncTimer();
}

SyncManager::~SyncManager()
{
    delete m_repo;
}

void SyncManager::loadSettings()
{
    QSettings s;
    m_enabled = s.value(QString::fromLatin1(KEY_ENABLED), false).toBool();
    m_serverUrl = s.value(QString::fromLatin1(KEY_URL)).toString();
    m_email = s.value(QString::fromLatin1(KEY_EMAIL)).toString();
}

void SyncManager::saveSettings()
{
    QSettings s;
    s.setValue(QString::fromLatin1(KEY_ENABLED), m_enabled);
    s.setValue(QString::fromLatin1(KEY_URL), m_serverUrl);
    // The address and the login live here; the tokens never do — QSettings on
    // macOS is a plaintext plist.
    s.setValue(QString::fromLatin1(KEY_EMAIL), m_email);
    emit configChanged();
}

QDateTime SyncManager::cursor() const
{
    QSettings s;
    const QString iso = s.value(QString::fromLatin1(KEY_CURSOR)).toString();
    return iso.isEmpty() ? QDateTime::fromSecsSinceEpoch(0)
                         : QDateTime::fromString(iso, Qt::ISODateWithMs);
}

void SyncManager::setCursor(const QString &serverTime)
{
    // Always the server's clock. A cursor taken from this machine's would skip
    // every row written in the gap if the two disagree by even a second — and
    // skip it permanently, because the next pull starts after it.
    if (serverTime.isEmpty())
        return;
    QSettings s;
    s.setValue(QString::fromLatin1(KEY_CURSOR), serverTime);
}

void SyncManager::setStatus(const QString &status, bool busy)
{
    m_status = status;
    m_busy = busy;
    emit statusChanged();
}

int SyncManager::pendingDeletions() const
{
    return m_repo ? m_repo->pendingTombstones().size() : 0;
}

void SyncManager::connectToServer(const QString &url, const QString &email,
                                  const QString &password)
{
    m_serverUrl = url;
    m_email = email;
    m_api.setBaseUrl(url);

    setStatus(tr("Signing in…"), true);

    m_api.logIn(email, password, [this](const ApiClient::Response &res) {
        if (!res.ok) {
            setStatus(res.isNetworkError ? tr("Cannot reach the server")
                                         : tr("Sign-in failed: %1").arg(res.error));
            emit syncFinished(false, m_status);
            return;
        }

        m_enabled = true;
        saveSettings();
        decideFirstSync();
    });
}

void SyncManager::decideFirstSync()
{
    setStatus(tr("Checking the server…"), true);

    // A full pull, cursor-free. It answers both "what is there" and "what do we
    // need", so the decision costs no extra request.
    m_api.get(QStringLiteral("/v1/sync"), [this](const ApiClient::Response &res) {
        if (!res.ok) {
            setStatus(tr("Could not read the server: %1").arg(res.error));
            emit syncFinished(false, m_status);
            return;
        }

        g_pendingServerChanges = res.body.value("changes").toObject();
        g_pendingServerTime = res.body.value("serverTime").toString();

        // Live rows only. A pull returns tombstones too — that is the point of
        // them — but a server holding nothing except deletions is empty as far
        // as this decision is concerned. Counting them made a clean server look
        // populated and sent the first connection down the "ask the user" path
        // for no reason.
        int serverBooks = 0;
        for (const QJsonValue &v : g_pendingServerChanges.value("books").toArray()) {
            const QJsonObject b = v.toObject();
            if (b.value("deletedAt").isNull() || !b.contains("deletedAt"))
                ++serverBooks;
        }
        const int localBooks = m_repo->bookCount();

        if (localBooks > 0 && serverBooks == 0) {
            performUpload();
        } else if (localBooks == 0 && serverBooks > 0) {
            performDownload();
        } else if (localBooks == 0 && serverBooks == 0) {
            setCursor(g_pendingServerTime);
            setStatus(tr("Connected"));
            emit syncFinished(true, tr("Connected. Nothing to synchronise yet."));
        } else {
            // Both hold data. Books created on different machines carry
            // different UUIDs, so nothing here can tell whether these are the
            // same library twice or two different ones — and guessing wrong
            // silently doubles it.
            setStatus(tr("Waiting for a decision"));
            emit firstSyncDecisionRequired(localBooks, serverBooks);
        }
    });
}

void SyncManager::resolveFirstSync(const QString &choice)
{
    if (choice == QLatin1String("upload")) {
        performUpload();
    } else if (choice == QLatin1String("download")) {
        performDownload();
    } else {
        // Cancel leaves both sides exactly as they were. The session stays, so
        // the user can decide later without signing in again.
        setStatus(tr("Connected — not synchronised"));
        emit syncFinished(false, tr("Cancelled. Nothing was changed."));
    }
}

void SyncManager::performUpload()
{
    setStatus(tr("Uploading your library…"), true);

    // Covers first, and collectAll() only afterwards, so the hashes the upload
    // learns are already on the rows it sends. Gathering the batch first would
    // send every book with a null cover_hash and leave the images stranded
    // until some later edit happened to touch each row.
    uploadCovers([this]() { sendWholeLibrary(); });
}

void SyncManager::sendWholeLibrary()
{
    const QJsonObject batch = m_repo->collectAll();
    const int books = batch.value("books").toArray().size();

    // Same endpoint as an incremental push, on purpose. A separate bootstrap
    // path would run once per installation and therefore never be debugged.
    m_api.post(QStringLiteral("/v1/sync"), batch, [this, books](const ApiClient::Response &res) {
        if (!res.ok) {
            setStatus(tr("Upload failed: %1").arg(res.error));
            emit syncFinished(false, m_status);
            return;
        }

        setCursor(res.body.value("serverTime").toString());
        setStatus(tr("Connected"));
        emit syncFinished(true, tr("Sent %n book(s) to the server.", nullptr, books));
    });
}

void SyncManager::performDownload()
{
    setStatus(tr("Downloading…"), true);

    const int written = m_repo->applyChanges(g_pendingServerChanges);
    setCursor(g_pendingServerTime);
    g_pendingServerChanges = {};

    setStatus(tr("Connected"));
    emit remoteChangesApplied();
    emit syncFinished(true, tr("Received %n row(s) from the server.", nullptr, written));

    // The rows arrived naming their covers; fetch the images those names refer
    // to. Not awaited — a library is usable before its pictures are.
    downloadCovers();
}

void SyncManager::withSession(std::function<void(bool)> then)
{
    if (m_api.hasSession()) { then(true); return; }

    // A read already running: wait for it rather than starting a second one.
    // Launch fires one immediately, and the user can press Sync Now while it is
    // still going — two reads would mean two permission panels.
    if (m_sessionReading) { m_sessionWaiters.push_back(std::move(then)); return; }
    if (m_sessionChecked) { then(false); return; }

    if (!m_enabled || m_email.isEmpty()) { then(false); return; }

    m_sessionReading = true;
    m_api.setBaseUrl(m_serverUrl);
    const QString email = m_email;

    // Detached: nothing waits on it, and the result comes back by hopping to
    // the main thread, where the ApiClient lives.
    std::thread([this, email, then]() {
        const QString access = BookWorm::Keychain::retrieve(email, QStringLiteral("accessToken"));
        const QString refresh = BookWorm::Keychain::retrieve(email, QStringLiteral("refreshToken"));

        QMetaObject::invokeMethod(this, [this, access, refresh, then]() {
            m_api.adoptTokens(access, refresh);
            m_sessionReading = false;
            m_sessionChecked = true;

            const bool ok = m_api.hasSession();
            if (!ok)
                setStatus(tr("Sign in required"));

            then(ok);
            auto waiters = std::move(m_sessionWaiters);
            m_sessionWaiters.clear();
            for (const auto &waiter : waiters)
                waiter(ok);
        }, Qt::QueuedConnection);
    }).detach();
}

void SyncManager::syncOnStart()
{
    if (!m_enabled) {
        logSync(QStringLiteral("start: sync is off"));
        return;
    }
    withSession([this](bool ok) {
        if (!ok) {
            logSync(QStringLiteral("start: no session could be restored"));
            return;
        }
        logSync(QStringLiteral("start: exchanging with %1").arg(m_serverUrl));
        performIncremental();
    });
}

void SyncManager::syncOnQuit()
{
    if (!m_enabled || !m_api.hasSession()) {
        // No blocking read here: shutdown is the worst possible moment for a
        // permission panel. If launch could not restore a session, this one
        // simply does not run.
        logSync(QStringLiteral("quit: nothing to do"));
        return;
    }

    logSync(QStringLiteral("quit: exchanging before exit"));

    // The request is asynchronous and the application is leaving, so the event
    // loop has to be held open for it — briefly. A sync that cannot finish is
    // not a reason to keep a window on screen.
    QEventLoop loop;
    QTimer deadline;
    deadline.setSingleShot(true);

    QObject::connect(this, &SyncManager::syncFinished, &loop, &QEventLoop::quit);
    QObject::connect(&deadline, &QTimer::timeout, &loop, [&loop]() {
        logSync(QStringLiteral("quit: timed out; resumes next launch"));
        loop.quit();
    });

    performIncremental();

    deadline.start(SHUTDOWN_SYNC_TIMEOUT_MS);
    loop.exec();
}

void SyncManager::syncNow()
{
    if (!m_enabled) {
        emit syncFinished(false, tr("Not connected"));
        return;
    }
    withSession([this](bool ok) {
        if (!ok) { emit syncFinished(false, tr("Not connected")); return; }
        performIncremental();
    });
}

void SyncManager::syncIfStale()
{
    if (!m_enabled || m_busy)
        return;
    if (m_lastExchange.isValid()
        && m_lastExchange.secsTo(QDateTime::currentDateTime()) < ACTIVATION_QUIET_PERIOD_S) {
        return;
    }
    logSync(QStringLiteral("activation: exchanging"));
    syncNow();
}

void SyncManager::autoSync()
{
    // Skipped rather than queued when one is already running: a slow exchange
    // must not accumulate a backlog of identical ones behind it.
    if (!m_enabled || m_busy || !m_api.hasSession())
        return;
    logSync(QStringLiteral("timer: exchanging"));
    performIncremental();
}

void SyncManager::updateAutoSyncTimer()
{
    if (m_enabled && !m_autoSyncTimer->isActive())
        m_autoSyncTimer->start();
    else if (!m_enabled && m_autoSyncTimer->isActive())
        m_autoSyncTimer->stop();
}

void SyncManager::performIncremental()
{
    m_lastExchange = QDateTime::currentDateTime();
    setStatus(tr("Synchronising…"), true);
    uploadCovers([this]() { pushAndPull(); });
}

void SyncManager::pushAndPull()
{
    QJsonObject batch = m_repo->collectChangedSince(cursor());
    const QJsonArray tombstones = m_repo->pendingTombstones();

    // Deletions ride along as tombstoned rows: the server's push handler reads
    // deletedAt on an ordinary row rather than taking a separate list.
    for (const QJsonValue &t : tombstones) {
        const QJsonObject o = t.toObject();
        static const QHash<QString, QString> keyFor = {
            {QStringLiteral("books"), QStringLiteral("books")},
            {QStringLiteral("tags"), QStringLiteral("tags")},
            {QStringLiteral("challenges"), QStringLiteral("challenges")},
            {QStringLiteral("favorite_quotes"), QStringLiteral("favoriteQuotes")},
            {QStringLiteral("highlights"), QStringLiteral("highlights")},
            {QStringLiteral("reading_sessions"), QStringLiteral("readingSessions")},
        };
        const QString key = keyFor.value(o.value("entity").toString());
        if (key.isEmpty())
            continue;

        QJsonObject row;
        row["uuid"] = o.value("uuid").toString();
        row["updatedAt"] = o.value("deletedAt").toString();
        row["deletedAt"] = o.value("deletedAt").toString();

        QJsonArray rows = batch.value(key).toArray();
        rows.append(row);
        batch[key] = rows;
    }

    m_api.post(QStringLiteral("/v1/sync"), batch,
               [this, tombstones](const ApiClient::Response &res) {
        if (!res.ok) {
            // The queue is deliberately not cleared: a failed push must not
            // lose the deletions it was carrying. Offline is a normal state
            // here, not an error worth shouting about.
            logSync(QStringLiteral("push failed: %1").arg(res.error));
            setStatus(res.isNetworkError ? tr("Offline — will retry")
                                         : tr("Sync failed: %1").arg(res.error));
            emit syncFinished(false, m_status);
            return;
        }

        logSync(QStringLiteral("push ok"));
        m_repo->clearTombstones(tombstones);

        const int written = m_repo->applyChanges(res.body.value("changes").toObject());
        setCursor(res.body.value("serverTime").toString());

        setStatus(tr("Connected"));
        if (written > 0)
            emit remoteChangesApplied();
        emit syncFinished(true, tr("Synchronised."));

        // After the rows, because it is the rows that say which covers exist.
        downloadCovers();
    });
}

void SyncManager::disconnectFromServer()
{
    m_api.logOut();

    m_enabled = false;
    saveSettings();

    QSettings s;
    // The cursor goes with the session: a stale one would make the next
    // connection skip everything written in the meantime. A full pull is
    // idempotent, so starting over costs nothing but time.
    s.remove(QString::fromLatin1(KEY_CURSOR));

    setStatus(QString());
    emit syncFinished(true, tr("Disconnected. Your library on this computer is unchanged."));
}

// ── Covers ───────────────────────────────────────────────────────────────────

void SyncManager::uploadCovers(std::function<void()> then)
{
    auto jobs = std::make_shared<QVector<SyncRepository::CoverJob>>(m_repo->coversToUpload());
    if (jobs->isEmpty()) {
        then();
        return;
    }

    logSync(QStringLiteral("covers: %1 to upload").arg(jobs->size()));

    auto index = std::make_shared<int>(0);
    auto sent = std::make_shared<int>(0);

    // std::function holding itself, via a shared_ptr, so each reply can start
    // the next request. A plain loop cannot: these complete asynchronously.
    auto step = std::make_shared<std::function<void()>>();
    *step = [this, jobs, index, sent, then, step]() {
        if (*index >= jobs->size()) {
            if (*sent > 0)
                logSync(QStringLiteral("covers: uploaded %1").arg(*sent));
            then();
            return;
        }

        const SyncRepository::CoverJob job = jobs->at((*index)++);

        QFile file(job.path);
        if (!file.open(QIODevice::ReadOnly)) {
            (*step)();
            return;
        }
        const QByteArray content = file.readAll();

        m_api.postFile(QStringLiteral("/v1/covers"), QFileInfo(job.path).fileName(), content,
                       [this, job, sent, then, step](const ApiClient::Response &res) {
            if (res.ok) {
                // Trust the server's hash over the one computed here. They
                // agree today; if they ever stop, the one that can find the
                // image again is the server's.
                m_repo->setCoverHash(job.bookId, res.body.value("hash").toString());
                ++(*sent);
                (*step)();
                return;
            }

            if (res.isNetworkError || res.httpStatus == 429) {
                // Offline, or asked to slow down. Both mean stop trying now and
                // leave the rest for the next sync, which will find them again.
                logSync(QStringLiteral("covers: stopping after %1 (%2)")
                            .arg(*sent).arg(res.httpStatus == 429 ? QStringLiteral("rate limited")
                                                                  : res.error));
                then();
                return;
            }

            // A rejection specific to this image — too large, or not an image
            // the server will take. Skipping it is right; retrying it forever
            // would not make it acceptable.
            logSync(QStringLiteral("covers: %1 rejected: %2")
                        .arg(QFileInfo(job.path).fileName(), res.error));
            (*step)();
        });
    };

    (*step)();
}

void SyncManager::downloadCovers()
{
    auto jobs = std::make_shared<QVector<SyncRepository::CoverJob>>(m_repo->coversToDownload());
    if (jobs->isEmpty())
        return;

    if (!QDir().mkpath(SyncRepository::coverDir())) {
        logSync(QStringLiteral("covers: cannot create %1").arg(SyncRepository::coverDir()));
        return;
    }

    logSync(QStringLiteral("covers: %1 to download").arg(jobs->size()));

    auto index = std::make_shared<int>(0);
    auto got = std::make_shared<int>(0);

    auto step = std::make_shared<std::function<void()>>();
    *step = [this, jobs, index, got, step]() {
        if (*index >= jobs->size()) {
            if (*got > 0) {
                logSync(QStringLiteral("covers: downloaded %1").arg(*got));
                emit remoteChangesApplied();   // the grid is showing placeholders
            }
            return;
        }

        const SyncRepository::CoverJob job = jobs->at((*index)++);

        // Already here, under another book. Covers are stored by content hash
        // and the server deduplicates, so two books sharing an edition share
        // one file — the second one needs the pointer, not the download.
        if (QFile::exists(job.path)) {
            m_repo->retireMirror(job.supersedes, job.bookId);
            m_repo->setCoverFile(job.bookId, job.hash, job.path);
            ++(*got);
            (*step)();
            return;
        }

        m_api.getBytes(QStringLiteral("/v1/covers/%1").arg(job.hash),
                       [this, job, got, step](const QByteArray &bytes) {
            if (bytes.isEmpty()) {
                // Gone from the server, or unreachable. Either way the book
                // keeps its hash and the next sync asks again.
                (*step)();
                return;
            }

            // Written whole and then renamed: a half-written file would be a
            // readable path pointing at a broken image, and coversToDownload()
            // decides purely on whether the path exists.
            const QString partial = job.path + QStringLiteral(".part");
            QFile out(partial);
            if (!out.open(QIODevice::WriteOnly)) { (*step)(); return; }
            const bool written = out.write(bytes) == bytes.size();
            out.close();

            // rename() will not replace an existing file, and by the time this
            // reply landed another book's download may have put one there.
            QFile::remove(job.path);
            if (!written || !QFile::rename(partial, job.path)) {
                QFile::remove(partial);
                (*step)();
                return;
            }

            m_repo->retireMirror(job.supersedes, job.bookId);
            m_repo->setCoverFile(job.bookId, job.hash, job.path);
            ++(*got);
            (*step)();
        });
    };

    (*step)();
}
