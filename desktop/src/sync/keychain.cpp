#include "keychain.h"

#include <QDebug>

#include <Security/Security.h>

#include <chrono>
#include <condition_variable>
#include <deque>
#include <mutex>
#include <thread>

namespace {

/**
 * The service name every entry is filed under. Combined with the account it
 * forms the primary key of a generic password item, which is why the account
 * carries both the user's email and which token this is — two accounts, or an
 * access and a refresh token, must not collide.
 */
constexpr const char *SERVICE = "com.sqtx.bookworm";

QByteArray accountKey(const QString &account, const QString &key)
{
    return QStringLiteral("%1:%2").arg(account, key).toUtf8();
}

CFDictionaryRef makeQuery(const QByteArray &account)
{
    CFStringRef service = CFStringCreateWithCString(nullptr, SERVICE, kCFStringEncodingUTF8);
    CFStringRef acct = CFStringCreateWithBytes(
        nullptr, reinterpret_cast<const UInt8 *>(account.constData()),
        account.size(), kCFStringEncodingUTF8, false);

    const void *keys[] = { kSecClass, kSecAttrService, kSecAttrAccount };
    const void *values[] = { kSecClassGenericPassword, service, acct };

    CFDictionaryRef query = CFDictionaryCreate(
        nullptr, keys, values, 3,
        &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);

    CFRelease(service);
    CFRelease(acct);
    return query;
}

/**
 * The serialised worker that every blocking Keychain call is meant to run on.
 *
 * A permission panel does not return until it is answered, and answering it may
 * take minutes or never happen at all. That is survivable on a thread nobody is
 * waiting on, and fatal on the main one. One thread rather than a pool, because
 * writes must land in the order they were issued: a rotation stores a token
 * while the previous store may still be blocked, and the older value landing
 * second leaves the item holding a token the server has already retired.
 */
class Worker
{
public:
    static Worker &instance()
    {
        static Worker worker;
        return worker;
    }

    void submit(std::function<void()> job)
    {
        {
            std::lock_guard<std::mutex> lock(m_mutex);
            m_queue.push_back(std::move(job));
            start();
        }
        m_wake.notify_one();
    }

    /** @returns false when @p timeoutMs elapsed with work still outstanding. */
    bool drain(int timeoutMs)
    {
        std::unique_lock<std::mutex> lock(m_mutex);
        return m_idle.wait_for(lock, std::chrono::milliseconds(timeoutMs),
                               [this]() { return m_queue.empty() && !m_running; });
    }

private:
    Worker() = default;

    /** Started on first use and never joined: it outlives every caller, and at
     *  shutdown it may be parked inside a panel that cannot be cancelled. */
    void start()
    {
        if (m_started)
            return;
        m_started = true;
        std::thread([this]() { loop(); }).detach();
    }

    void loop()
    {
        for (;;) {
            std::function<void()> job;
            {
                std::unique_lock<std::mutex> lock(m_mutex);
                m_wake.wait(lock, [this]() { return !m_queue.empty(); });
                job = std::move(m_queue.front());
                m_queue.pop_front();
                m_running = true;
            }

            job();

            {
                std::lock_guard<std::mutex> lock(m_mutex);
                m_running = false;
            }
            m_idle.notify_all();
        }
    }

    std::mutex m_mutex;
    std::condition_variable m_wake;
    std::condition_variable m_idle;
    std::deque<std::function<void()>> m_queue;
    bool m_started = false;
    bool m_running = false;
};

} // namespace

namespace BookWorm::Keychain {

bool store(const QString &account, const QString &key, const QString &secret)
{
    const QByteArray acct = accountKey(account, key);
    const QByteArray data = secret.toUtf8();

    // Replacing means deleting first: SecItemAdd fails with errSecDuplicateItem
    // rather than overwriting, and SecItemUpdate fails when nothing is there.
    // Delete-then-add handles both without having to know which case this is.
    CFDictionaryRef existing = makeQuery(acct);
    SecItemDelete(existing);
    CFRelease(existing);

    CFStringRef service = CFStringCreateWithCString(nullptr, SERVICE, kCFStringEncodingUTF8);
    CFStringRef acctRef = CFStringCreateWithBytes(
        nullptr, reinterpret_cast<const UInt8 *>(acct.constData()),
        acct.size(), kCFStringEncodingUTF8, false);
    CFDataRef payload = CFDataCreate(
        nullptr, reinterpret_cast<const UInt8 *>(data.constData()), data.size());

    const void *keys[] = { kSecClass, kSecAttrService, kSecAttrAccount, kSecValueData,
                           kSecAttrAccessible };
    const void *values[] = { kSecClassGenericPassword, service, acctRef, payload,
                             // Readable only once the device has been unlocked
                             // after boot, and never copied to another machine
                             // by a backup.
                             kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly };

    CFDictionaryRef attributes = CFDictionaryCreate(
        nullptr, keys, values, 5,
        &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);

    OSStatus status = SecItemAdd(attributes, nullptr);

    if (status == errSecDuplicateItem) {
        // The delete above did not remove it, but the item is there. That
        // happens when the existing entry was written by a different binary:
        // the Keychain's access control hides it from the delete while the
        // uniqueness check still sees it. Update in place instead of reporting
        // a failure the caller cannot act on.
        CFDictionaryRef query = makeQuery(acct);

        const void *updateKeys[] = { kSecValueData };
        const void *updateValues[] = { payload };
        CFDictionaryRef update = CFDictionaryCreate(
            nullptr, updateKeys, updateValues, 1,
            &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);

        status = SecItemUpdate(query, update);

        CFRelease(update);
        CFRelease(query);
    }

    CFRelease(attributes);
    CFRelease(payload);
    CFRelease(acctRef);
    CFRelease(service);

    if (status != errSecSuccess) {
        // The secret itself is never logged, only that storing it failed. This
        // is the quiet catastrophe: the session works for the rest of the run
        // and is gone by the next launch, so it must not pass in silence.
        qWarning() << "Keychain store failed for" << key << "status" << status;
        return false;
    }
    return true;
}

void runSerial(std::function<void()> job)
{
    Worker::instance().submit(std::move(job));
}

bool flush(int timeoutMs)
{
    return Worker::instance().drain(timeoutMs);
}

QString retrieve(const QString &account, const QString &key)
{
    const QByteArray acct = accountKey(account, key);

    CFStringRef service = CFStringCreateWithCString(nullptr, SERVICE, kCFStringEncodingUTF8);
    CFStringRef acctRef = CFStringCreateWithBytes(
        nullptr, reinterpret_cast<const UInt8 *>(acct.constData()),
        acct.size(), kCFStringEncodingUTF8, false);

    const void *keys[] = { kSecClass, kSecAttrService, kSecAttrAccount,
                           kSecReturnData, kSecMatchLimit };
    const void *values[] = { kSecClassGenericPassword, service, acctRef,
                             kCFBooleanTrue, kSecMatchLimitOne };

    CFDictionaryRef query = CFDictionaryCreate(
        nullptr, keys, values, 5,
        &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);

    CFTypeRef result = nullptr;
    const OSStatus status = SecItemCopyMatching(query, &result);

    CFRelease(query);
    CFRelease(acctRef);
    CFRelease(service);

    if (status != errSecSuccess || result == nullptr) {
        // errSecItemNotFound is the ordinary "not configured" case, not a fault,
        // so it is not logged.
        // errSecItemNotFound is the ordinary "not configured" case. Anything
        // else means the item is there and this build was not allowed to read
        // it — -25293 (errSecAuthFailed) and -25308 (errSecInteractionNotAllowed)
        // both present to the user as being signed out for no reason.
        if (status != errSecItemNotFound)
            qWarning() << "Keychain read failed for" << key << "status" << status;
        return QString();
    }

    CFDataRef data = static_cast<CFDataRef>(result);
    const QString secret = QString::fromUtf8(
        reinterpret_cast<const char *>(CFDataGetBytePtr(data)),
        static_cast<int>(CFDataGetLength(data)));
    CFRelease(result);

    return secret;
}

bool remove(const QString &account, const QString &key)
{
    CFDictionaryRef query = makeQuery(accountKey(account, key));
    const OSStatus status = SecItemDelete(query);
    CFRelease(query);

    // Nothing there is the outcome the caller wanted.
    return status == errSecSuccess || status == errSecItemNotFound;
}

} // namespace BookWorm::Keychain
