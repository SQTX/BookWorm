#include "keychain.h"

#include <QDebug>

#include <Security/Security.h>

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
 * Suppresses the Keychain's permission panel for as long as it is in scope.
 *
 * A stored item may normally be read without ceremony only by the binary that
 * wrote it; anyone else gets a system panel asking the user to allow it. That
 * default assumes a stable code signature, and this application has none — it
 * is built locally and unsigned, so every rebuild is a new identity and the
 * item written by the previous build is read by a stranger. The panel then
 * appears unbidden during launch or shutdown, and — worse — the read does not
 * return until somebody answers it. A stack trace caught exactly that: the
 * whole application parked inside SecItemCopyMatching.
 *
 * With interaction refused the read fails immediately instead, and the caller
 * treats it as "no stored session". The user signs in once more, the item is
 * rewritten by the current binary, and later launches are silent again. That is
 * a far better failure than an application that will not start.
 *
 * The setting is process-wide, hence the scope guard: it must not leak into the
 * next read.
 */
class NoInteraction
{
public:
    NoInteraction() { SecKeychainSetUserInteractionAllowed(false); }
    ~NoInteraction() { SecKeychainSetUserInteractionAllowed(true); }

    NoInteraction(const NoInteraction &) = delete;
    NoInteraction &operator=(const NoInteraction &) = delete;
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
        // The secret itself is never logged, only that storing it failed.
        qWarning() << "Keychain store failed for" << key << "status" << status;
        return false;
    }
    return true;
}

QString retrieve(const QString &account, const QString &key)
{
    const NoInteraction guard;

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
