import Foundation
import Security
import BookWormKit

/// A single Keychain item, read and written off the main thread.
///
/// Two rules, both learned on the desktop side:
///
/// * Never on the main thread. A Keychain call can block for as long as it
///   likes, and the desktop once failed to draw its window at all because one
///   was waiting behind a dialog nobody could see.
/// * A missing item is an ordinary outcome, not an error. The free provisioning
///   profile lasts seven days, and re-deploying can reinstall rather than
///   re-sign — which takes the Keychain item with it. "Sign in again" is a
///   normal path here.
struct KeychainItem: Sendable {
    let service: String
    var account = "session"

    func read() async -> Data? {
        await run { query -> Data? in
            var query = query
            query[kSecReturnData as String] = true
            query[kSecMatchLimit as String] = kSecMatchLimitOne

            var item: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &item)
            guard status == errSecSuccess else { return nil }
            return item as? Data
        }
    }

    func write(_ data: Data) async {
        await run { query -> Void in
            _ = SecItemDelete(query as CFDictionary)
            var insert = query
            insert[kSecValueData as String] = data
            // AfterFirstUnlock, not WhenUnlocked: a queued write flushed by a
            // background launch needs the token, and the phone may be locked.
            insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            _ = SecItemAdd(insert as CFDictionary, nil)
        }
    }

    func delete() async {
        await run { query -> Void in
            _ = SecItemDelete(query as CFDictionary)
        }
    }

    private static func baseQuery(service: String, account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecUseDataProtectionKeychain as String: true
        ]
    }

    /// The query is built inside the detached task rather than captured, so
    /// nothing non-Sendable crosses the boundary.
    private func run<T: Sendable>(_ body: @escaping @Sendable ([String: Any]) -> T) async -> T {
        let service = self.service
        let account = self.account
        return await Task.detached(priority: .userInitiated) {
            body(Self.baseQuery(service: service, account: account))
        }.value
    }
}

/// The token pair, in the Keychain.
struct KeychainTokenStorage: TokenStorage {
    private let item: KeychainItem

    init(service: String = "com.sqtx.bookworm.progress.tokens") {
        item = KeychainItem(service: service)
    }

    func load() async -> TokenPair? {
        guard let data = await item.read() else { return nil }
        return try? JSONDecoder().decode(TokenPair.self, from: data)
    }

    func save(_ pair: TokenPair) async {
        guard let data = try? JSONEncoder().encode(pair) else { return }
        await item.write(data)
    }

    func clear() async {
        await item.delete()
    }
}

/// The email and password, kept only when the user asks for it, and only in the
/// Keychain — never `UserDefaults`, which is an unprotected plist.
///
/// This exists because tokens are the wrong thing to rely on for "do not ask me
/// again": the access token lives fifteen minutes, and the refresh token is
/// gone the moment a re-deploy replaces the Keychain item. Stored credentials
/// let the app sign itself back in instead of stopping to ask.
struct StoredCredentials: Codable, Equatable, Sendable {
    let email: String
    let password: String
}

struct CredentialStore: Sendable {
    private let item: KeychainItem

    init(service: String = "com.sqtx.bookworm.progress.credentials") {
        item = KeychainItem(service: service, account: "account")
    }

    func load() async -> StoredCredentials? {
        guard let data = await item.read() else { return nil }
        return try? JSONDecoder().decode(StoredCredentials.self, from: data)
    }

    func save(_ credentials: StoredCredentials) async {
        guard let data = try? JSONEncoder().encode(credentials) else { return }
        await item.write(data)
    }

    func clear() async {
        await item.delete()
    }
}
