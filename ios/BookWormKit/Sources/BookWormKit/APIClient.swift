import Foundation

/// Everything this app says to the server.
///
/// An actor because two things need serialising: the cached token pair, and the
/// refresh. Refresh tokens rotate and a replayed one is treated as theft — the
/// server revokes every session for the account — so exactly one refresh may be
/// in flight, and a refresh that fails must never be retried with the same
/// token.
public actor APIClient {
    private let session: HTTPPerforming
    private let tokens: TokenStorage
    private let log: AppLog

    private var baseURL: URL
    private var cached: TokenPair?
    private var didLoadFromStorage = false
    private var refreshInFlight: Task<TokenPair, Error>?
    private var authenticationLost: (@Sendable () -> Void)?

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        return decoder
    }()

    public init(
        baseURL: URL,
        session: HTTPPerforming,
        tokens: TokenStorage,
        log: AppLog
    ) {
        self.baseURL = baseURL
        self.session = session
        self.tokens = tokens
        self.log = log
    }

    public func setBaseURL(_ url: URL) {
        baseURL = url
    }

    /// Called when the session is gone for good and the sign-in screen has to
    /// come back. Not called for a network failure — being on a train is not
    /// being signed out.
    public func onAuthenticationLost(_ handler: @escaping @Sendable () -> Void) {
        authenticationLost = handler
    }

    /// True when a token pair was found in storage. The Keychain read happens
    /// here, off the main actor, so a slow or blocked read delays nothing but
    /// this call.
    public func hasStoredSession() async -> Bool {
        await currentTokens() != nil
    }

    // MARK: - Endpoints

    public func logIn(email: String, password: String) async throws {
        let pair: TokenPair = try await unauthenticated(
            path: "/v1/auth/login",
            body: ["email": email, "password": password]
        )
        cached = pair
        didLoadFromStorage = true
        await tokens.save(pair)
        await log.write("Signed in")
    }

    /// Best-effort: the local session is discarded whether or not the server is
    /// reachable, because the user asked to be signed out.
    public func logOut() async {
        let pair = await currentTokens()
        cached = nil
        await tokens.clear()
        if let pair {
            _ = try? await unauthenticatedData(
                path: "/v1/auth/logout",
                body: ["refreshToken": pair.refreshToken]
            )
        }
        await log.write("Signed out")
    }

    public func readingBooks() async throws -> [Book] {
        try await books(status: "reading")
    }

    public func plannedBooks() async throws -> [Book] {
        try await books(status: "planned")
    }

    /// The filter is the server's job — fetching the whole library and sifting
    /// it on the phone is both slower and a lie about what this app holds.
    private func books(status: String) async throws -> [Book] {
        let response: BooksResponse = try await authorized(
            method: "GET",
            path: "/v1/books",
            query: [URLQueryItem(name: "status", value: status)]
        )
        return response.books
    }

    /// The only write this app makes. `POST /progress` — never `PATCH
    /// currentPage` — because this endpoint also records the reading session the
    /// desktop's streaks and heatmap are built from, and a PATCH would return
    /// 200 while quietly leaving those wrong.
    @discardableResult
    public func recordProgress(bookId: Int, currentPage: Int) async throws -> ProgressResponse {
        guard PageBounds.isValid(currentPage) else {
            throw APIError.http(status: 400, message: "Page must be between 0 and 100000")
        }
        let response: ProgressResponse = try await authorized(
            method: "POST",
            path: "/v1/books/\(bookId)/progress",
            body: ["currentPage": currentPage]
        )
        await log.write("Progress written: book \(bookId) → page \(currentPage)")
        return response
    }

    /// The star. A `PATCH` is right here and wrong for `currentPage`: the
    /// progress endpoint exists because moving the page must also record a
    /// session, and a flag has nothing to record. The body carries the one
    /// field — anything the schema does not know is a 400, not a shrug.
    @discardableResult
    public func setPriority(bookId: Int, isPriority: Bool) async throws -> Book {
        let book: Book = try await authorized(
            method: "PATCH",
            path: "/v1/books/\(bookId)",
            body: ["isPriority": isPriority]
        )
        await log.write("Book \(bookId) priority \(isPriority ? "set" : "cleared")")
        return book
    }

    /// Covers are immutable per hash and served with a one-year cache, so the
    /// caching is URLSession's job — this just adds the bearer token.
    public func coverData(hash: String, thumbnail: Bool = true) async throws -> Data {
        try await authorizedData(
            method: "GET",
            path: thumbnail ? "/v1/covers/\(hash)/thumb" : "/v1/covers/\(hash)",
            query: [],
            body: nil
        )
    }

    // MARK: - Request plumbing

    private func authorized<T: Decodable>(
        method: String,
        path: String,
        query: [URLQueryItem] = [],
        body: [String: any Sendable]? = nil
    ) async throws -> T {
        let data = try await authorizedData(method: method, path: path, query: query, body: body)
        return try decode(T.self, from: data)
    }

    /// Runs the request, and on a 401 refreshes once and runs it again. No call
    /// site knows this happens.
    private func authorizedData(
        method: String,
        path: String,
        query: [URLQueryItem],
        body: [String: any Sendable]?
    ) async throws -> Data {
        guard let pair = await currentTokens() else {
            throw APIError.notAuthenticated
        }

        var request = try makeRequest(method: method, path: path, query: query, body: body)
        request.setValue("Bearer \(pair.accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await send(request)
        if response.statusCode != 401 {
            return try validate(data: data, response: response)
        }

        let refreshed = try await refreshedTokens(replacing: pair)
        var retry = try makeRequest(method: method, path: path, query: query, body: body)
        retry.setValue("Bearer \(refreshed.accessToken)", forHTTPHeaderField: "Authorization")

        let (retryData, retryResponse) = try await send(retry)
        if retryResponse.statusCode == 401 {
            await discardSession(reason: "the server rejected a freshly refreshed token")
            throw APIError.notAuthenticated
        }
        return try validate(data: retryData, response: retryResponse)
    }

    private func unauthenticated<T: Decodable>(
        path: String,
        body: [String: any Sendable]
    ) async throws -> T {
        let data = try await unauthenticatedData(path: path, body: body)
        return try decode(T.self, from: data)
    }

    @discardableResult
    private func unauthenticatedData(path: String, body: [String: any Sendable]) async throws -> Data {
        let request = try makeRequest(method: "POST", path: path, query: [], body: body)
        let (data, response) = try await send(request)
        return try validate(data: data, response: response)
    }

    private func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            return try await session.perform(request)
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.unreachable((error as NSError).localizedDescription)
        }
    }

    private func makeRequest(
        method: String,
        path: String,
        query: [URLQueryItem],
        body: [String: any Sendable]?
    ) throws -> URLRequest {
        guard var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false) else {
            throw APIError.invalidBaseURL
        }
        if !query.isEmpty { components.queryItems = query }
        guard let url = components.url else { throw APIError.invalidBaseURL }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 20
        // Covers are immutable per hash and worth caching forever; the library
        // is the opposite. Without this a pull-to-refresh can be answered from
        // URLSession's heuristic cache — the request never leaves the phone and
        // the user is shown yesterday's page count as if it were fresh.
        if !path.contains("/covers/") {
            request.cachePolicy = .reloadIgnoringLocalCacheData
        }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        return request
    }

    private func validate(data: Data, response: HTTPURLResponse) throws -> Data {
        guard (200...299).contains(response.statusCode) else {
            let body = try? decoder.decode(ServerErrorBody.self, from: data)
            throw APIError.http(status: response.statusCode, message: body?.best ?? "")
        }
        return data
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try decoder.decode(type, from: data)
        } catch {
            throw APIError.decoding(String(describing: error))
        }
    }

    // MARK: - Tokens

    private func currentTokens() async -> TokenPair? {
        if !didLoadFromStorage {
            cached = await tokens.load()
            didLoadFromStorage = true
        }
        return cached
    }

    /// Single-flight. Concurrent 401s wait on the one refresh rather than each
    /// spending the rotating token.
    private func refreshedTokens(replacing stale: TokenPair) async throws -> TokenPair {
        if let refreshInFlight {
            return try await refreshInFlight.value
        }
        // Somebody already rotated while this request was in the air.
        if let cached, cached.refreshToken != stale.refreshToken {
            return cached
        }

        let session = self.session
        let baseURL = self.baseURL
        let task = Task<TokenPair, Error> {
            var request = URLRequest(url: baseURL.appendingPathComponent("/v1/auth/refresh"))
            request.httpMethod = "POST"
            request.timeoutInterval = 20
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(
                withJSONObject: ["refreshToken": stale.refreshToken]
            )

            let (data, response): (Data, HTTPURLResponse)
            do {
                (data, response) = try await session.perform(request)
            } catch let error as APIError {
                throw error
            } catch {
                throw APIError.unreachable((error as NSError).localizedDescription)
            }

            guard (200...299).contains(response.statusCode) else {
                let body = try? JSONDecoder().decode(ServerErrorBody.self, from: data)
                throw APIError.http(status: response.statusCode, message: body?.best ?? "")
            }
            do {
                return try JSONDecoder().decode(TokenPair.self, from: data)
            } catch {
                throw APIError.decoding(String(describing: error))
            }
        }
        refreshInFlight = task

        do {
            let pair = try await task.value
            refreshInFlight = nil
            cached = pair
            await tokens.save(pair)
            await log.write("Access token refreshed")
            return pair
        } catch let error as APIError {
            refreshInFlight = nil
            if case .unreachable(let detail) = error {
                // Keep the token: an unsent request has not rotated anything, and
                // signing the user out because a tunnel went by is worse than
                // trying the same token when there is signal again.
                await log.write("Refresh could not reach the server (\(detail)); keeping the session")
                throw error
            }
            await discardSession(reason: "refresh was rejected (\(error.userFacingText))")
            throw APIError.notAuthenticated
        } catch {
            refreshInFlight = nil
            await discardSession(reason: "refresh failed unexpectedly")
            throw APIError.notAuthenticated
        }
    }

    private func discardSession(reason: String) async {
        cached = nil
        didLoadFromStorage = true
        await tokens.clear()
        await log.write("Session ended: \(reason)")
        authenticationLost?()
    }
}
