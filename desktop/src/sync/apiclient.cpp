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
    const QString email = m_email;

    clearTokens();
    if (!email.isEmpty()) {
        BookWorm::Keychain::remove(email, QString::fromLatin1(ACCESS_KEY));
        BookWorm::Keychain::remove(email, QString::fromLatin1(REFRESH_KEY));
    }

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

bool ApiClient::restoreSession(const QString &email)
{
    if (email.isEmpty())
        return false;

    m_email = email;
    m_accessToken = BookWorm::Keychain::retrieve(email, QString::fromLatin1(ACCESS_KEY));
    m_refreshToken = BookWorm::Keychain::retrieve(email, QString::fromLatin1(REFRESH_KEY));

    // The access token has almost certainly expired between runs; the refresh
    // token is what makes the session restorable, so that is what decides.
    return !m_refreshToken.isEmpty();
}

void ApiClient::adoptTokens(const QString &access, const QString &refresh)
{
    m_accessToken = access;
    m_refreshToken = refresh;
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
    if (m_baseUrl.isEmpty() || m_accessToken.isEmpty()) {
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
    if (m_baseUrl.isEmpty() || m_accessToken.isEmpty()) {
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

        if (res.httpStatus == 401 && allowRetry && !m_refreshToken.isEmpty() && !m_refreshing) {
            // A fifteen-minute token expiring mid-sync is routine. Handling it
            // here means no call site has to.
            refreshThenRetry(verb, path, body, done);
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

void ApiClient::refreshThenRetry(const QByteArray &verb, const QString &path,
                                 const QJsonObject &body, Callback done)
{
    m_refreshing = true;

    QJsonObject request;
    request["refreshToken"] = m_refreshToken;

    send("POST", QStringLiteral("/v1/auth/refresh"), request,
         [this, verb, path, body, done](const Response &res) {
             m_refreshing = false;

             if (!res.ok) {
                 // The refresh token was rejected. Either it expired, or the
                 // server saw it replayed and revoked every session — from
                 // here the two are indistinguishable, and the answer is the
                 // same: log in again.
                 clearTokens();
                 emit sessionExpired();
                 if (done) done(res);
                 return;
             }

             storeTokens(res.body);
             // Retry once. allowRetry is false so a second 401 surfaces rather
             // than looping.
             send(verb, path, body, done, /*allowRetry=*/false);
         },
         /*allowRetry=*/false);
}

void ApiClient::storeTokens(const QJsonObject &tokens)
{
    m_accessToken = tokens.value("accessToken").toString();
    m_refreshToken = tokens.value("refreshToken").toString();

    if (m_email.isEmpty())
        return;

    BookWorm::Keychain::store(m_email, QString::fromLatin1(ACCESS_KEY), m_accessToken);
    BookWorm::Keychain::store(m_email, QString::fromLatin1(REFRESH_KEY), m_refreshToken);
}

void ApiClient::clearTokens()
{
    m_accessToken.clear();
    m_refreshToken.clear();
}
