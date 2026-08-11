#pragma once

#include <QJsonObject>
#include <QNetworkAccessManager>
#include <QObject>
#include <QString>

#include <functional>

/**
 * HTTP client for the BookWorm API.
 *
 * Owns authentication and nothing else: it knows how to log in, how to attach a
 * token, and how to recover when one expires. What to send and what to do with
 * the answer belongs to the sync layer above it.
 *
 * Every call is asynchronous. Nothing here may block the UI thread — the
 * application has to stay fully usable with the server unreachable, which is
 * the entire reason the local database remains the source the views read.
 */
class ApiClient : public QObject
{
    Q_OBJECT

public:
    /** A finished request: the parsed body, or an error the caller can show. */
    struct Response {
        bool ok = false;
        int httpStatus = 0;
        QJsonObject body;
        QString error;

        /** True when the failure was reaching the server at all, rather than
         *  the server refusing. Offline is normal; a 400 is a bug. */
        bool isNetworkError = false;
    };

    using Callback = std::function<void(const Response &)>;

    explicit ApiClient(QObject *parent = nullptr);

    /** e.g. "https://57.128.199.27.nip.io". A trailing slash is tolerated. */
    void setBaseUrl(const QString &url);
    QString baseUrl() const { return m_baseUrl; }

    /**
     * Exchange credentials for tokens and remember them in the Keychain.
     *
     * The password is used for this one request and never stored — not in
     * QSettings, not in a member, not in the Keychain. Re-authenticating later
     * uses the refresh token instead.
     */
    void logIn(const QString &email, const QString &password, Callback done);

    /** Forget the tokens locally and tell the server to revoke the session. */
    void logOut(Callback done = nullptr);

    /** Load tokens saved by a previous run. @returns false when there are none. */
    bool restoreSession(const QString &email);

    bool hasSession() const { return !m_accessToken.isEmpty(); }
    QString account() const { return m_email; }

    /**
     * Authenticated request. On a 401 the access token is refreshed once and
     * the request retried, because a fifteen-minute token expiring mid-sync is
     * routine rather than exceptional — surfacing it to the caller would make
     * every call site handle it.
     */
    void get(const QString &path, Callback done);
    void post(const QString &path, const QJsonObject &body, Callback done);

signals:
    /** The refresh token was rejected. The user has to log in again — which
     *  also happens when the server detects a replayed token and revokes every
     *  session, so it is not necessarily an error on this machine. */
    void sessionExpired();

private:
    void send(const QByteArray &verb, const QString &path, const QJsonObject &body,
              Callback done, bool allowRetry);
    void refreshThenRetry(const QByteArray &verb, const QString &path,
                          const QJsonObject &body, Callback done);
    void storeTokens(const QJsonObject &tokens);
    void clearTokens();

    QNetworkAccessManager m_network;
    QString m_baseUrl;
    QString m_email;
    QString m_accessToken;
    QString m_refreshToken;
    bool m_refreshing = false;
};
