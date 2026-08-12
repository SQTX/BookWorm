import Foundation
import Security
import BookWormKit

/// The token pair, in the Keychain, read off the main thread.
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
struct KeychainTokenStorage: TokenStorage {
    private let service: String
    private let account = "session"

    init(service: String = "com.sqtx.bookworm.progress.tokens") {
        self.service = service
    }

    func load() async -> TokenPair? {
        await run { query -> TokenPair? in
            var query = query
            query[kSecReturnData as String] = true
            query[kSecMatchLimit as String] = kSecMatchLimitOne

            var item: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &item)
            guard status == errSecSuccess, let data = item as? Data else { return nil }
            return try? JSONDecoder().decode(TokenPair.self, from: data)
        }
    }

    func save(_ pair: TokenPair) async {
        guard let data = try? JSONEncoder().encode(pair) else { return }
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

    func clear() async {
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
