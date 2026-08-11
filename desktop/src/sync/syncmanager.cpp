#include "syncmanager.h"
#include "syncrepository.h"
#include "../database/databasemanager.h"

#include <QJsonArray>
#include <QSettings>

namespace {

constexpr const char *KEY_ENABLED = "sync/enabled";
constexpr const char *KEY_URL = "sync/serverUrl";
constexpr const char *KEY_EMAIL = "sync/email";
constexpr const char *KEY_CURSOR = "sync/cursor";

/** Held between the decision prompt and the user's answer. */
QJsonObject g_pendingServerChanges;
QString g_pendingServerTime;

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

SyncManager *SyncManager::create(QQmlEngine *, QJSEngine *)
{
    return new SyncManager;
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
            setStatus(res.isNetworkError ? tr("Offline — will retry")
                                         : tr("Sync failed: %1").arg(res.error));
            emit syncFinished(false, m_status);
            return;
        }

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
