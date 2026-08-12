import Foundation

public struct TokenPair: Codable, Equatable, Sendable {
    public let accessToken: String
    public let refreshToken: String
    /// Seconds, as the server sends it.
    public let expiresIn: Int?

    public init(accessToken: String, refreshToken: String, expiresIn: Int? = nil) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresIn = expiresIn
    }
}

/// Where the token pair lives. The app implements this over the Keychain; the
/// tests over a dictionary. The protocol is async because a Keychain read can
/// block for as long as it likes, and the interface must never wait on it.
public protocol TokenStorage: Sendable {
    func load() async -> TokenPair?
    func save(_ pair: TokenPair) async
    func clear() async
}

/// Used by the tests, and as a safe stand-in before the Keychain answers.
public actor InMemoryTokenStorage: TokenStorage {
    private var pair: TokenPair?

    public init(_ pair: TokenPair? = nil) { self.pair = pair }

    public func load() async -> TokenPair? { pair }
    public func save(_ pair: TokenPair) async { self.pair = pair }
    public func clear() async { pair = nil }
}
