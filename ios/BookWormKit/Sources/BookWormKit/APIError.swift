import Foundation

public enum APIError: Error, Equatable, Sendable {
    /// The device could not reach the server at all: offline, DNS, timeout.
    /// This is the case a queued write exists for.
    case unreachable(String)
    /// Refresh failed or was impossible — the user has to sign in again.
    case notAuthenticated
    /// The server answered with a non-2xx status.
    case http(status: Int, message: String)
    case decoding(String)
    case invalidBaseURL

    /// Whether retrying later could plausibly succeed. Governs whether a failed
    /// write stays in the queue or is dropped: a 400 or a 404 will fail exactly
    /// the same way tomorrow, and a permanently stuck item is a write the user
    /// believes is pending forever.
    public var isRetryable: Bool {
        switch self {
        case .unreachable: return true
        case .http(let status, _): return status == 429 || (500...599).contains(status)
        case .notAuthenticated, .decoding, .invalidBaseURL: return false
        }
    }

    public var userFacingText: String {
        switch self {
        case .unreachable: return "No connection"
        case .notAuthenticated: return "Sign in required"
        case .http(let status, let message):
            return message.isEmpty ? "Server error \(status)" : message
        case .decoding: return "Unexpected response"
        case .invalidBaseURL: return "That server address is not a URL"
        }
    }
}

/// The server's error envelope. `message` carries the specific complaint on a
/// schema failure and `error` only the generic status name, so `message` is read
/// first — the other way round reports "Bad Request" and throws the useful half
/// away.
struct ServerErrorBody: Decodable {
    let error: String?
    let message: String?

    var best: String {
        if let message, !message.isEmpty { return message }
        if let error, !error.isEmpty { return error }
        return ""
    }
}
