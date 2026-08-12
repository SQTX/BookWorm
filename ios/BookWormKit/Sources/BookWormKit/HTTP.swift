import Foundation

/// The one thing the client needs from URLSession, so the tests can hand it
/// something else without a URLProtocol stub.
public protocol HTTPPerforming: Sendable {
    func perform(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

extension URLSession: HTTPPerforming {
    public func perform(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.decoding("Response was not HTTP")
        }
        return (data, http)
    }
}

public enum ServerAddress {
    /// Turns what a person types into a base URL. `57.128.199.27.nip.io`,
    /// `https://host/`, and `https://host/v1` all have to arrive at the same
    /// place, because all three are what gets typed on a phone keyboard.
    public static func normalize(_ input: String) -> URL? {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if !text.contains("://") { text = "https://" + text }
        while text.hasSuffix("/") { text.removeLast() }
        if text.hasSuffix("/v1") { text.removeLast(3) }
        guard let url = URL(string: text), url.host != nil else { return nil }
        return url
    }
}
