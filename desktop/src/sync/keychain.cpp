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

    const OSStatus status = SecItemAdd(attributes, nullptr);

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
