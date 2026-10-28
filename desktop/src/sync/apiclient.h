#pragma once

#include <QDateTime>
#include <QJsonObject>
#include <QNetworkAccessManager>
#include <QObject>
#include <QString>

#include <functional>
#include <vector>

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

    /** Take tokens read elsewhere — the Keychain is read off the main thread. */
    void adoptTokens(const QString &access, const QString &refresh);

    /**
     * A session exists while a refresh token does.
     *
     * Not "while an access token does": that one lives fifteen minutes and is
     * therefore expired on nearly every launch, so asking about it answers a
     * different question than the callers mean. What decides whether this
     * machine can still reach the server without the user's password is the
     * refresh token.
     */
    bool hasSession() const { return !m_refreshToken.isEmpty() || !m_accessToken.isEmpty(); }
    QString account() const { return m_email; }

    /**
     * True while a token rotation is in flight.
     *
     * Shutdown asks, because abandoning a rotation is the one thing that can
     * cost the user their session: the server has issued a new refresh token
     * and this process is about to exit without having stored it.
     */
    bool isRefreshing() const { return m_refreshing; }

    /**
     * Authenticated request.
     *
     * The access token is refreshed *before* the request when it is about to
     * expire, rather than only after a 401. Waiting for the rejection worked,
     * but it meant every launch after a break began with a burst of failures,
     * and each of those failures is a rotation — the operation most likely to
     * lose a session if its reply goes missing. A 401 is still handled, for the
     * cases prediction cannot cover: a clock that disagrees, or a token revoked
     * on the server.
     */
    void get(const QString &path, Callback done);
    void post(const QString &path, const QJsonObject &body, Callback done);

    /**
     * Upload one file as multipart/form-data.
     *
     * Separate from post() because that one speaks JSON, and a cover is bytes.
     * Deliberately takes the content rather than a path: the caller has already
     * read the file to hash it, and reading it twice invites the two reads to
     * disagree.
     */
    void postFile(const QString &path, const QString &fileName,
                  const QByteArray &content, Callback done);

    /**
     * Fetch a response whose body is not JSON.
     *
     * @p done receives the raw bytes, empty when the request failed. The status
     * is deliberately not exposed: every caller here treats "no image" the
     * same way regardless of why.
     */
    void getBytes(const QString &path, std::function<void(const QByteArray &)> done);

signals:
    /** The refresh token was rejected. The user has to log in again — which
     *  also happens when the server detects a replayed token and revokes every
     *  session, so it is not necessarily an error on this machine.
     *
     *  Emitted only when the server actually said no. An unreachable server is
     *  not a rejection, and treating it as one signed the user out for being
     *  offline. */
    void sessionExpired();

private:
    void send(const QByteArray &verb, const QString &path, const QJsonObject &body,
              Callback done, bool allowRetry);
    /** Issue the request as it stands, with whatever token is currently held. */
    void dispatch(const QByteArray &verb, const QString &path, const QJsonObject &body,
                  Callback done, bool allowRetry);

    /** True when the held access token is missing, or close enough to expiry
     *  that a request sent now might be rejected on arrival. */
    bool tokenNeedsRefresh() const;

    /**
     * Rotate the tokens, then run @p then with whether it worked.
     *
     * Every caller goes through here, and a rotation already in flight collects
     * the later ones rather than starting its own. That matters more than it
     * looks: two requests failing at once used to mean one refreshed and the
     * other simply failed, and — worse — a second rotation racing the first
     * would present a token the server had just retired, which it reads as
     * theft and answers by revoking every session on the account.
     */
    void withFreshToken(std::function<void(bool)> then);

    void storeTokens(const QJsonObject &tokens);
    void clearTokens();

    /** Forget the session here and in the Keychain.
     *
     *  Both, always: clearing only memory left a token the server had already
     *  rejected sitting on disk, and every later launch presented it again. */
    void forgetSession();

    QNetworkAccessManager m_network;
    QString m_baseUrl;
    QString m_email;
    QString m_accessToken;
    QString m_refreshToken;
    /** When the held access token stops being accepted, read from its own `exp`
     *  claim. Invalid when unknown, which falls back to the 401 path. */
    QDateTime m_accessExpiry;
    bool m_refreshing = false;
    std::vector<std::function<void(bool)>> m_refreshWaiters;
};
