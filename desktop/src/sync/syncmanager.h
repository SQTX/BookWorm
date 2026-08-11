#pragma once

#include <QDateTime>
#include <QObject>
#include <QString>

#include "apiclient.h"

class SyncRepository;

/**
 * Orchestrates synchronisation, and is the only sync type QML talks to.
 *
 * Off by default and silent about it (D8). Nothing here runs, connects or warns
 * until the user turns it on in Settings — "not configured" is the normal
 * state, not a fault to report.
 */
class SyncManager : public QObject
{
    Q_OBJECT

    Q_PROPERTY(bool enabled READ enabled NOTIFY configChanged)
    Q_PROPERTY(QString serverUrl READ serverUrl NOTIFY configChanged)
    Q_PROPERTY(QString email READ email NOTIFY configChanged)
    Q_PROPERTY(QString status READ status NOTIFY statusChanged)
    Q_PROPERTY(bool busy READ busy NOTIFY statusChanged)
    Q_PROPERTY(int pendingDeletions READ pendingDeletions NOTIFY statusChanged)

public:
    /** What the first exchange with a server should do with the two libraries. */
    enum class FirstSync {
        Nothing,        ///< Both sides empty.
        Upload,         ///< This machine has books, the server has none.
        Download,       ///< The server has books, this machine has none.
        Ambiguous       ///< Both hold data; only the user can say which wins.
    };
    Q_ENUM(FirstSync)

    explicit SyncManager(QObject *parent = nullptr);
    ~SyncManager() override;

    bool enabled() const { return m_enabled; }
    QString serverUrl() const { return m_serverUrl; }
    QString email() const { return m_email; }
    QString status() const { return m_status; }
    bool busy() const { return m_busy; }
    int pendingDeletions() const;

    /**
     * Log in and, if that works, decide what the first exchange should do.
     *
     * Emits firstSyncDecisionRequired when both sides hold data — the one case
     * a program must not decide alone, because UUIDs are minted per machine and
     * "upload everything" would duplicate a library rather than merge it.
     */
    Q_INVOKABLE void connectToServer(const QString &url, const QString &email,
                                     const QString &password);

    /** Answer to firstSyncDecisionRequired: "upload", "download" or "cancel". */
    Q_INVOKABLE void resolveFirstSync(const QString &choice);

    /** Forget the session. Leaves both libraries alone. */
    Q_INVOKABLE void disconnectFromServer();

    /** Push what changed here, then take what changed there. */
    Q_INVOKABLE void syncNow();

    /**
     * Exchange on launch, once the session has been restored.
     *
     * Pushes before pulling rather than only pulling. A pull alone would strand
     * anything edited while the last run was offline — or after it crashed
     * without a final sync — and that work would sit locally until something
     * else happened to touch the same row. Pushing first cannot damage the
     * server: a row older than the server's copy is rejected by the merge rule,
     * not applied.
     */
    void syncOnStart();

    /**
     * Exchange during shutdown, bounded by a deadline.
     *
     * Quitting must never hang on the network. If the exchange does not finish
     * in time the application exits anyway and nothing is lost: the cursor only
     * advances on success and the deletion queue is only cleared on success, so
     * the next launch simply sends it again.
     */
    void syncOnQuit();

signals:
    void configChanged();
    void statusChanged();

    /** Both libraries hold data and cannot be matched automatically. */
    void firstSyncDecisionRequired(int localBooks, int serverBooks);

    void syncFinished(bool ok, const QString &message);

    /** Rows arrived from the server, so the views need rebuilding. */
    void remoteChangesApplied();

private:
    void loadSettings();
    void saveSettings();
    void setStatus(const QString &status, bool busy = false);

    void decideFirstSync();
    void performUpload();
    void performDownload();
    void performIncremental();

    QDateTime cursor() const;
    void setCursor(const QString &serverTime);

    ApiClient m_api;
    SyncRepository *m_repo = nullptr;

    bool m_enabled = false;
    QString m_serverUrl;
    QString m_email;
    QString m_status;
    bool m_busy = false;
};
