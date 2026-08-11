#include "syncmanager.h"
#include "syncrepository.h"
#include "../database/databasemanager.h"

#include <QDir>
#include <QEventLoop>
#include <QFile>
#include <QStandardPaths>
#include <QTextStream>
#include <QJsonArray>
#include <QSettings>
#include <QTimer>

namespace {

constexpr const char *KEY_ENABLED = "sync/enabled";
constexpr const char *KEY_URL = "sync/serverUrl";
constexpr const char *KEY_EMAIL = "sync/email";
constexpr const char *KEY_CURSOR = "sync/cursor";

/**
 * How long shutdown waits for a sync.
 *
 * Long enough for a normal exchange over a slow connection, short enough that
 * nobody wonders why the window will not close. Exceeding it costs nothing: the
 * work is re-sent next time.
 */
constexpr int SHUTDOWN_SYNC_TIMEOUT_MS = 6000;

/** Held between the decision prompt and the user's answer. */
QJsonObject g_pendingServerChanges;
QString g_pendingServerTime;

/**
 * Append one line to a sync log on disk.
 *
 * qInfo() is not enough here. Launched as a bundle the application's stderr
 * goes somewhere the user will not look, so a sync that silently does nothing
 * is indistinguishable from one that worked — which is exactly the question
 * being asked when something has gone wrong.
 */
void logSync(const QString &line)
{
    const QString dir = QStandardPaths::writableLocation(QStandardPaths::AppDataLocation);
    QDir().mkpath(dir);

    QFile f(dir + QStringLiteral("/sync.log"));
    if (!f.open(QIODevice::WriteOnly | QIODevice::Append | QIODevice::Text))
        return;

    QTextStream(&f) << QDateTime::currentDateTime().toString(Qt::ISODate)
                    << "  " << line << '\n';
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

    if (m_enabled && !m_email.isEmpty()) {
        m_api.setBaseUrl(m_serverUrl);
        // Restoring only reads the Keychain; nothing touches the network until
        // the user or a timer asks for a sync.
        if (m_api.restoreSession(m_email))
            setStatus(tr("Connected"));
        else
            setStatus(tr("Sign in required"));
    } else {
        setStatus(QString());
    }
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
}

void SyncManager::syncOnStart()
{
    // Each reason is reported separately: "switched off" and "signed out" look
    // the same from outside and need different answers from the user.
    if (!m_enabled) {
        logSync(QStringLiteral("start: sync is off"));
        return;
    }
    if (!m_api.hasSession()) {
        logSync(QStringLiteral("start: enabled but no session could be restored"));
        return;
    }

    logSync(QStringLiteral("start: syncing with %1").arg(m_serverUrl));

    // Push-then-pull, which is what performIncremental already does in a single
    // request. Ordering matters on launch specifically: a previous run may have
    // been closed or killed before its own exchange finished.
    performIncremental();
}

void SyncManager::syncOnQuit()
{
    if (!m_enabled || !m_api.hasSession()) {
        logSync(QStringLiteral("quit: nothing to do (enabled=%1 session=%2)")
                    .arg(m_enabled).arg(m_api.hasSession()));
        return;
    }

    logSync(QStringLiteral("quit: syncing before exit"));

    // The request is asynchronous and the application is on its way out, so the
    // event loop has to be kept alive for it — but only briefly. A sync that
    // cannot finish is not a reason to hold a window open.
    QEventLoop loop;
    QTimer deadline;
    deadline.setSingleShot(true);

    QObject::connect(this, &SyncManager::syncFinished, &loop, &QEventLoop::quit);
    QObject::connect(&deadline, &QTimer::timeout, &loop, [&loop]() {
        logSync(QStringLiteral("quit: timed out; will resume next launch"));
        loop.quit();
    });

    performIncremental();

    deadline.start(SHUTDOWN_SYNC_TIMEOUT_MS);
    loop.exec();
}

void SyncManager::syncNow()
{
    if (!m_enabled || !m_api.hasSession()) {
        emit syncFinished(false, tr("Not connected"));
        return;
    }
    performIncremental();
}

void SyncManager::performIncremental()
{
    setStatus(tr("Synchronising…"), true);

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
