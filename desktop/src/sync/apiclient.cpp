#include "apiclient.h"
#include "keychain.h"

#include <QJsonDocument>
#include <QHttpMultiPart>
#include <QNetworkReply>
#include <QTimer>

namespace {

constexpr const char *ACCESS_KEY = "accessToken";
constexpr const char *REFRESH_KEY = "refreshToken";

/** Requests carry a timeout because the default is effectively none, and a
 *  sync that hangs forever looks identical to one that is merely slow. */
constexpr int REQUEST_TIMEOUT_MS = 20000;

/** Uploads get longer: the server re-encodes the image before it replies. */
constexpr int UPLOAD_TIMEOUT_MS = 60000;

/**
 * How much of an access token's remaining life is treated as already spent.
 *
 * A token valid for another twenty seconds is not worth sending: the request
 * has to cross a network and the server compares against its own clock, so it
 * may well be expired on arrival. Refreshing slightly early costs one request
 * and removes an entire class of failure.
 *
 * Ninety seconds also absorbs a modest clock disagreement between the two
 * machines, which is the other reason a token that looks valid here is not.
 */
constexpr int TOKEN_REFRESH_MARGIN_S = 90;

/**
 * When the access token expires, read from the token itself.
 *
 * The access token is a JWT and its payload carries `exp` in the clear — it is
 * signed, not encrypted. Reading it means the expiry survives a restart without
 * being stored anywhere, and cannot drift out of step with the token it
 * describes. The signature is not checked here and must not be: this is the
 * client deciding when to refresh, not deciding whether to trust anything.
 *
 * @returns an invalid QDateTime when the token is absent or not readable, which
 *   the caller treats as "unknown" rather than as "expired" — falling back to
 *   the 401 path is correct, while refreshing on every request would not be.
 */
QDateTime expiryOf(const QString &accessToken)
{
    const QStringList parts = accessToken.split(QLatin1Char('.'));
    if (parts.size() != 3)
        return {};

    const QByteArray payload = QByteArray::fromBase64(
        parts.at(1).toUtf8(), QByteArray::Base64UrlEncoding | QByteArray::OmitTrailingEquals);
    if (payload.isEmpty())
        return {};

    const QJsonObject claims = QJsonDocument::fromJson(payload).object();
    const QJsonValue exp = claims.value(QStringLiteral("exp"));
    if (!exp.isDouble())
        return {};

    return QDateTime::fromSecsSinceEpoch(static_cast<qint64>(exp.toDouble()));
}

} // namespace

ApiClient::ApiClient(QObject *parent)
    : QObject(parent)
{
}

void ApiClient::setBaseUrl(const QString &url)
{
    m_baseUrl = url.trimmed();
    while (m_baseUrl.endsWith(QLatin1Char('/')))
        m_baseUrl.chop(1);
}

void ApiClient::logIn(const QString &email, const QString &password, Callback done)
{
    QJsonObject credentials;
    credentials["email"] = email;
    credentials["password"] = password;

    // Deliberately not stored anywhere: the password exists for this one
    // request. Everything afterwards runs on tokens.
    send("POST", QStringLiteral("/v1/auth/login"), credentials,
         [this, email, done](const Response &res) {
             if (res.ok) {
                 m_email = email;
                 storeTokens(res.body);
             }
             if (done) done(res);
         },
         /*allowRetry=*/false);
}

void ApiClient::logOut(Callback done)
{
    const QString refresh = m_refreshToken;

    forgetSession();

    if (refresh.isEmpty()) {
        if (done) done(Response{true, 0, {}, {}, false});
        return;
    }

    // Told after forgetting, not before: if the request fails the tokens are
    // still gone from this machine, which is what the user asked for.
    QJsonObject body;
    body["refreshToken"] = refresh;
    send("POST", QStringLiteral("/v1/auth/logout"), body, done, /*allowRetry=*/false);
}

void ApiClient::adoptTokens(const QString &access, const QString &refresh)
{
    m_accessToken = access;
    m_refreshToken = refresh;
    // Read from the token rather than assumed. A session restored after a day
    // holds an access token that expired long ago, and one restored after a
    // minute holds a perfectly good one; guessing either way is wrong for the
    // other case.
    m_accessExpiry = expiryOf(access);
}

void ApiClient::get(const QString &path, Callback done)
{
    send("GET", path, {}, done, /*allowRetry=*/true);
}

void ApiClient::post(const QString &path, const QJsonObject &body, Callback done)
{
    send("POST", path, body, done, /*allowRetry=*/true);
}

void ApiClient::postFile(const QString &path, const QString &fileName,
                         const QByteArray &content, Callback done)
{
    if (m_baseUrl.isEmpty()) {
        if (done) done(Response{false, 0, {}, QStringLiteral("Not connected"), false});
        return;
    }

    // Refreshed up front, never retried after the fact: a multipart body cannot
    // be replayed once it has been consumed. That mattered more than it sounds,
    // because covers upload *before* the push, so on the first exchange after a
    // break every one of them met an expired token and failed. Each is then
    // retried on the next sync, which meant a library's covers could take
    // several syncs to arrive, or none at all if every sync started cold.
    if (tokenNeedsRefresh()) {
        withFreshToken([this, path, fileName, content, done](bool ok) {
            if (!ok) {
                // Reported as a network failure on purpose. The caller skips an
                // image the server *rejected* and never offers it again, which
                // would be the wrong answer to "we could not get a token" —
                // that one has to be retried on the next sync.
                if (done) done(Response{false, 0, {}, tr("Sign in required"), true});
                return;
            }
            postFile(path, fileName, content, done);
        });
        return;
    }

    if (m_accessToken.isEmpty()) {
        if (done) done(Response{false, 0, {}, QStringLiteral("Not connected"), false});
        return;
    }

    auto *multiPart = new QHttpMultiPart(QHttpMultiPart::FormDataType);

    QHttpPart filePart;
    filePart.setHeader(QNetworkRequest::ContentTypeHeader,
                       QVariant(QStringLiteral("application/octet-stream")));
    filePart.setHeader(QNetworkRequest::ContentDispositionHeader,
                       QVariant(QStringLiteral("form-data; name=\"file\"; filename=\"%1\"")
                                    .arg(fileName)));
    filePart.setBody(content);
    multiPart->append(filePart);

    QNetworkRequest request{QUrl(m_baseUrl + path)};
    request.setRawHeader("Authorization", "Bearer " + m_accessToken.toUtf8());
    // Longer than a JSON call: the server re-encodes the image before replying,
    // and it does so on two vCPU.
    request.setTransferTimeout(UPLOAD_TIMEOUT_MS);

    QNetworkReply *reply = m_network.post(request, multiPart);
    multiPart->setParent(reply);   // freed with the reply, not before it is sent

    QObject::connect(reply, &QNetworkReply::finished, this, [reply, done]() {
        reply->deleteLater();

        Response res;
        res.httpStatus = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();

        const QJsonDocument doc = QJsonDocument::fromJson(reply->readAll());
        if (doc.isObject())
            res.body = doc.object();

        if (reply->error() != QNetworkReply::NoError && res.httpStatus == 0) {
            res.isNetworkError = true;
            res.error = reply->errorString();
        } else {
            res.ok = res.httpStatus >= 200 && res.httpStatus < 300;
            if (!res.ok)
                res.error = res.body.value("error").toString();
        }

        // No 401 retry. An upload body cannot be replayed once the multipart
        // has been consumed, and the caller runs these in a batch that the next
        // sync repeats anyway.
        if (done) done(res);
    });
}

void ApiClient::getBytes(const QString &path, std::function<void(const QByteArray &)> done)
{
    if (m_baseUrl.isEmpty()) {
        if (done) done({});
        return;
    }

    // Same reasoning as postFile: no retry path exists here, so the token is
    // made good before the request rather than after it.
    if (tokenNeedsRefresh()) {
        withFreshToken([this, path, done](bool ok) {
            if (!ok) {
                if (done) done({});
                return;
            }
            getBytes(path, done);
        });
        return;
    }

    if (m_accessToken.isEmpty()) {
        if (done) done({});
        return;
    }

    QNetworkRequest request{QUrl(m_baseUrl + path)};
    request.setRawHeader("Authorization", "Bearer " + m_accessToken.toUtf8());
    request.setTransferTimeout(REQUEST_TIMEOUT_MS);

    QNetworkReply *reply = m_network.get(request);
    QObject::connect(reply, &QNetworkReply::finished, this, [reply, done]() {
        reply->deleteLater();
        const int status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
        const QByteArray body = reply->readAll();
        if (done) done(status == 200 ? body : QByteArray());
    });
}

void ApiClient::send(const QByteArray &verb, const QString &path,
                     const QJsonObject &body, Callback done, bool allowRetry)
{
    if (m_baseUrl.isEmpty()) {
        if (done) done(Response{false, 0, {}, QStringLiteral("No server address configured"), false});
        return;
    }

    // allowRetry marks the authenticated calls. The three auth endpoints pass
    // false and must never come through here, or refreshing would recurse.
    if (allowRetry && tokenNeedsRefresh()) {
        withFreshToken([this, verb, path, body, done](bool ok) {
            // A refresh that failed still lets the request go out — offline is
            // an ordinary state and the caller wants to hear about it as a
            // network error, not as a silence. allowRetry is false so a 401 is
            // reported rather than starting the cycle again.
            dispatch(verb, path, body, done, ok);
        });
        return;
    }

    dispatch(verb, path, body, done, allowRetry);
}

bool ApiClient::tokenNeedsRefresh() const
{
    if (m_refreshToken.isEmpty())
        return false;           // nothing to refresh with
    if (m_accessToken.isEmpty())
        return true;            // restored a session that had no usable token
    if (!m_accessExpiry.isValid())
        return false;           // unreadable expiry: leave it to the 401 path

    return m_accessExpiry <= QDateTime::currentDateTimeUtc().addSecs(TOKEN_REFRESH_MARGIN_S);
}

void ApiClient::dispatch(const QByteArray &verb, const QString &path,
                         const QJsonObject &body, Callback done, bool allowRetry)
{
    QNetworkRequest request{QUrl(m_baseUrl + path)};
    request.setHeader(QNetworkRequest::ContentTypeHeader, QStringLiteral("application/json"));
    request.setTransferTimeout(REQUEST_TIMEOUT_MS);

    if (!m_accessToken.isEmpty())
        request.setRawHeader("Authorization", "Bearer " + m_accessToken.toUtf8());

    const QByteArray payload =
        body.isEmpty() ? QByteArray() : QJsonDocument(body).toJson(QJsonDocument::Compact);

    QNetworkReply *reply = (verb == "GET")
        ? m_network.get(request)
        : m_network.sendCustomRequest(request, verb, payload);

    QObject::connect(reply, &QNetworkReply::finished, this,
                     [this, reply, verb, path, body, done, allowRetry]() {
        reply->deleteLater();

        Response res;
        res.httpStatus = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();

        const QByteArray raw = reply->readAll();
        if (!raw.isEmpty()) {
            const QJsonDocument doc = QJsonDocument::fromJson(raw);
            if (doc.isObject())
                res.body = doc.object();
        }

        if (reply->error() != QNetworkReply::NoError && res.httpStatus == 0) {
            // No status means the request never reached the server: offline,
            // DNS failure, timeout. That is a normal state for this app, so the
            // caller is told which kind of failure it was rather than being
            // handed a generic error to guess about.
            res.isNetworkError = true;
            res.error = reply->errorString();
            if (done) done(res);
            return;
        }

        if (res.httpStatus == 401 && allowRetry && !m_refreshToken.isEmpty()) {
            // Prediction missed — a clock disagreement, or a token the server
            // retired early. A rotation already running collects this request
            // instead of starting a second one against the same token, which is
            // what the server reads as theft.
            withFreshToken([this, verb, path, body, done](bool ok) {
                if (!ok) {
                    if (done) done(Response{false, 401, {}, tr("Sign in required"), false});
                    return;
                }
                // allowRetry false, so a second 401 surfaces rather than loops.
                dispatch(verb, path, body, done, false);
            });
            return;
        }

        res.ok = res.httpStatus >= 200 && res.httpStatus < 300;
        if (!res.ok && res.error.isEmpty()) {
            // "message" first: on a validation failure Fastify puts the useful
            // part there ("body/books/0 must have required property ...") and
            // leaves "error" as the generic status name. Reading only "error"
            // turns a precise complaint into "Bad Request".
            res.error = res.body.value("message").toString();
            if (res.error.isEmpty())
                res.error = res.body.value("error").toString();
            if (res.error.isEmpty())
                res.error = QStringLiteral("Server returned %1").arg(res.httpStatus);
        }

        if (done) done(res);
    });
}

void ApiClient::withFreshToken(std::function<void(bool)> then)
{
    m_refreshWaiters.push_back(std::move(then));

    // Already rotating: the waiter above will be run with the outcome. Starting
    // a second rotation would present the token the first one is retiring, and
    // the server cannot tell that from a stolen copy.
    if (m_refreshing)
        return;

    m_refreshing = true;

    QJsonObject request;
    request["refreshToken"] = m_refreshToken;

    send("POST", QStringLiteral("/v1/auth/refresh"), request,
         [this](const Response &res) {
             m_refreshing = false;

             if (res.ok) {
                 storeTokens(res.body);
             } else if (res.isNetworkError) {
                 // Unreachable, not rejected. The session is intact and the
                 // tokens must stay: treating this as expiry signed the user
                 // out for being offline, and the log shows it happening.
             } else {
                 // The server said no. Either the token expired, or it was
                 // replayed and every session was revoked — indistinguishable
                 // from here, and the answer is the same. Forgetting it in the
                 // Keychain as well matters: a rejected token left on disk is
                 // presented again on every later launch, and each attempt is
                 // read as another replay.
                 forgetSession();
                 emit sessionExpired();
             }

             const bool ok = res.ok;
             auto waiters = std::move(m_refreshWaiters);
             m_refreshWaiters.clear();
             for (const auto &waiter : waiters)
                 waiter(ok);
         },
         /*allowRetry=*/false);
}

void ApiClient::storeTokens(const QJsonObject &tokens)
{
    m_accessToken = tokens.value("accessToken").toString();
    m_refreshToken = tokens.value("refreshToken").toString();
    m_accessExpiry = expiryOf(m_accessToken);

    if (m_email.isEmpty())
        return;

    // Off this thread. Writing to the Keychain can raise a permission panel and
    // then block until it is answered, and this runs inside a network callback
    // on the main thread — where blocking freezes the window. The queue is
    // serialised, so successive rotations are written in the order they
    // happened; a later token overtaking an earlier one would leave the item
    // holding a value the server has already retired.
    //
    // The refresh token is written first. Rotation retires the previous one the
    // moment the server answers, so from here until the next launch this write
    // is the only record of the session.
    const QString email = m_email;
    const QString access = m_accessToken;
    const QString refresh = m_refreshToken;

    BookWorm::Keychain::runSerial([email, access, refresh]() {
        if (!BookWorm::Keychain::store(email, QString::fromLatin1(REFRESH_KEY), refresh)) {
            // Nothing here can repair it, but it must not pass quietly: a
            // session about to be lost looks exactly like one that is working.
            qWarning() << "Could not store the rotated refresh token; this "
                          "session will not survive a restart";
        }
        BookWorm::Keychain::store(email, QString::fromLatin1(ACCESS_KEY), access);
    });
}

void ApiClient::clearTokens()
{
    m_accessToken.clear();
    m_refreshToken.clear();
    m_accessExpiry = QDateTime();
}

void ApiClient::forgetSession()
{
    const QString email = m_email;
    clearTokens();

    if (email.isEmpty())
        return;

    // Queued behind any pending write, so a store still waiting on a panel
    // cannot resurrect the session this is deleting.
    BookWorm::Keychain::runSerial([email]() {
        BookWorm::Keychain::remove(email, QString::fromLatin1(ACCESS_KEY));
        BookWorm::Keychain::remove(email, QString::fromLatin1(REFRESH_KEY));
    });
}
