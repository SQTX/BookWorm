import XCTest
@testable import BookWormKit

final class APIClientTests: XCTestCase {
    private let base = URL(string: "https://example.test")!

    private func makeClient(
        _ exchanges: [StubHTTP.Exchange],
        tokens: TokenStorage = InMemoryTokenStorage(TokenPair(accessToken: "a1", refreshToken: "r1"))
    ) -> (APIClient, StubHTTP) {
        let http = StubHTTP(exchanges)
        let client = APIClient(baseURL: base, session: http, tokens: tokens, log: AppLog(fileURL: nil))
        return (client, http)
    }

    func testReadingBooksAskesTheServerToFilter() async throws {
        let (client, http) = makeClient([
            .json(200, ["books": [Book.fixture().asJSON]])
        ])

        let books = try await client.readingBooks()

        XCTAssertEqual(books.count, 1)
        XCTAssertEqual(books[0].id, 42)
        XCTAssertEqual(books[0].currentPage, 180)
        let url = http.request(0).url!.absoluteString
        XCTAssertTrue(url.hasSuffix("/v1/books?status=reading"), url)
        XCTAssertEqual(http.request(0).value(forHTTPHeaderField: "Authorization"), "Bearer a1")
    }

    func testNullPageFieldsDecodeAsNilRatherThanZero() async throws {
        let (client, _) = makeClient([
            .json(200, ["books": [Book.fixture(pageCount: nil, currentPage: nil).asJSON]])
        ])

        let book = try await client.readingBooks()[0]

        XCTAssertNil(book.pageCount)
        XCTAssertNil(book.currentPage)
        XCTAssertTrue(book.isUnstarted)
        XCTAssertFalse(book.hasSliderRange)
    }

    func testProgressGoesToTheProgressEndpointNotAPatch() async throws {
        let saved = Book.fixture(currentPage: 212)
        let (client, http) = makeClient([
            .json(200, ["book": saved.asJSON, "pagesRead": 32])
        ])

        let response = try await client.recordProgress(bookId: 42, currentPage: 212)

        XCTAssertEqual(response.pagesRead, 32)
        XCTAssertEqual(response.book.currentPage, 212)
        XCTAssertEqual(http.request(0).httpMethod, "POST")
        XCTAssertTrue(http.request(0).url!.absoluteString.hasSuffix("/v1/books/42/progress"))
        XCTAssertEqual(http.body(0) as? [String: Int], ["currentPage": 212])
    }

    func testProgressBodyCarriesNothingTheSchemaDoesNotKnow() async throws {
        let (client, http) = makeClient([
            .json(200, ["book": Book.fixture().asJSON, "pagesRead": 0])
        ])

        _ = try await client.recordProgress(bookId: 42, currentPage: 100)

        XCTAssertEqual(Array(http.body(0).keys), ["currentPage"])
    }

    func testOutOfRangePageIsRefusedBeforeItReachesTheServer() async {
        let (client, http) = makeClient([])

        do {
            _ = try await client.recordProgress(bookId: 42, currentPage: 100_001)
            XCTFail("expected a refusal")
        } catch let error as APIError {
            guard case .http(let status, _) = error else { return XCTFail("wrong error: \(error)") }
            XCTAssertEqual(status, 400)
        } catch {
            XCTFail("wrong error: \(error)")
        }
        XCTAssertEqual(http.requestCount, 0)
    }

    func testUnauthorizedRefreshesOnceAndRetries() async throws {
        let tokens = InMemoryTokenStorage(TokenPair(accessToken: "expired", refreshToken: "r1"))
        let (client, http) = makeClient([
            .json(401, ["error": "Unauthorized"]),
            .json(200, ["accessToken": "a2", "refreshToken": "r2", "expiresIn": 900]),
            .json(200, ["books": [Book.fixture().asJSON]])
        ], tokens: tokens)

        let books = try await client.readingBooks()

        XCTAssertEqual(books.count, 1)
        XCTAssertEqual(http.requestCount, 3)
        XCTAssertTrue(http.request(1).url!.absoluteString.hasSuffix("/v1/auth/refresh"))
        XCTAssertEqual(http.body(1) as? [String: String], ["refreshToken": "r1"])
        XCTAssertEqual(http.request(2).value(forHTTPHeaderField: "Authorization"), "Bearer a2")

        let stored = await tokens.load()
        XCTAssertEqual(stored?.refreshToken, "r2", "the rotated token must be the one that is kept")
    }

    func testConcurrentUnauthorizedRequestsShareOneRefresh() async throws {
        // Two 401s, one refresh, two retries. A second refresh would replay the
        // rotating token and the server would revoke every session for it.
        let (client, http) = makeClient([
            .json(401, ["error": "Unauthorized"]),
            .json(401, ["error": "Unauthorized"]),
            .json(200, ["accessToken": "a2", "refreshToken": "r2", "expiresIn": 900]),
            .json(200, ["books": []]),
            .json(200, ["books": []])
        ])

        async let first = client.readingBooks()
        async let second = client.readingBooks()
        _ = try await (first, second)

        let refreshes = (0..<http.requestCount)
            .map { http.request($0).url!.absoluteString }
            .filter { $0.hasSuffix("/v1/auth/refresh") }
        XCTAssertEqual(refreshes.count, 1, "exactly one refresh may be spent")
    }

    func testRejectedRefreshEndsTheSessionAndClearsTheToken() async {
        let tokens = InMemoryTokenStorage(TokenPair(accessToken: "expired", refreshToken: "r1"))
        let (client, _) = makeClient([
            .json(401, ["error": "Unauthorized"]),
            .json(401, ["error": "Unauthorized", "message": "Refresh token revoked"])
        ], tokens: tokens)

        let lost = LostFlag()
        await client.onAuthenticationLost { lost.raise() }

        do {
            _ = try await client.readingBooks()
            XCTFail("expected notAuthenticated")
        } catch let error as APIError {
            XCTAssertEqual(error, .notAuthenticated)
        } catch {
            XCTFail("wrong error: \(error)")
        }

        let stored = await tokens.load()
        XCTAssertNil(stored, "a rejected refresh token must not be kept and never re-sent")
        XCTAssertTrue(lost.value)
    }

    func testUnreachableRefreshKeepsTheSession() async {
        // A tunnel is not a sign-out. The token was never spent, so it stays.
        let tokens = InMemoryTokenStorage(TokenPair(accessToken: "expired", refreshToken: "r1"))
        let (client, _) = makeClient([
            .json(401, ["error": "Unauthorized"]),
            .failure(URLError(.notConnectedToInternet))
        ], tokens: tokens)

        let lost = LostFlag()
        await client.onAuthenticationLost { lost.raise() }

        do {
            _ = try await client.readingBooks()
            XCTFail("expected a transport error")
        } catch let error as APIError {
            guard case .unreachable = error else { return XCTFail("wrong error: \(error)") }
        } catch {
            XCTFail("wrong error: \(error)")
        }

        let stored = await tokens.load()
        XCTAssertEqual(stored?.refreshToken, "r1")
        XCTAssertFalse(lost.value, "being offline must not present the sign-in screen")
    }

    func testValidationFailureReportsMessageRatherThanTheGenericError() async {
        let (client, _) = makeClient([
            .json(400, ["error": "Bad Request", "message": "body/currentPage must be <= 100000"])
        ])

        do {
            _ = try await client.recordProgress(bookId: 42, currentPage: 500)
            XCTFail("expected a failure")
        } catch let error as APIError {
            XCTAssertEqual(error, .http(status: 400, message: "body/currentPage must be <= 100000"))
            XCTAssertFalse(error.isRetryable)
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }

    func testRateLimitAndServerFaultsAreRetryableButBadRequestsAreNot() {
        XCTAssertTrue(APIError.http(status: 429, message: "").isRetryable)
        XCTAssertTrue(APIError.http(status: 500, message: "").isRetryable)
        XCTAssertTrue(APIError.unreachable("offline").isRetryable)
        XCTAssertFalse(APIError.http(status: 400, message: "").isRetryable)
        XCTAssertFalse(APIError.http(status: 404, message: "").isRetryable)
        XCTAssertFalse(APIError.notAuthenticated.isRetryable)
    }

    func testLoginStoresTheTokenPair() async throws {
        let tokens = InMemoryTokenStorage()
        let (client, http) = makeClient([
            .json(200, ["accessToken": "a1", "refreshToken": "r1", "expiresIn": 900])
        ], tokens: tokens)

        try await client.logIn(email: "someone@example.test", password: "secret")

        XCTAssertEqual(http.body(0) as? [String: String], ["email": "someone@example.test", "password": "secret"])
        let stored = await tokens.load()
        XCTAssertEqual(stored?.accessToken, "a1")
    }

    func testCoverRequestUsesTheThumbnailPath() async throws {
        let (client, http) = makeClient([
            Stub.image
        ])

        _ = try await client.coverData(hash: String(repeating: "a", count: 64))

        XCTAssertTrue(http.request(0).url!.absoluteString.hasSuffix("/thumb"))
    }

    private enum Stub {
        static var image: StubHTTP.Exchange {
            StubHTTP.Exchange(status: 200, body: Data([0x52, 0x49, 0x46, 0x46]), error: nil)
        }
    }
}

/// A box, because the handler is `@Sendable` and the test needs to see it fire.
final class LostFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var flag = false

    func raise() {
        lock.lock(); flag = true; lock.unlock()
    }

    var value: Bool {
        lock.lock(); defer { lock.unlock() }
        return flag
    }
}

final class ServerAddressTests: XCTestCase {
    func testWhatSomeoneTypesOnAPhoneBecomesABaseURL() {
        XCTAssertEqual(ServerAddress.normalize("57.128.199.27.nip.io")?.absoluteString, "https://57.128.199.27.nip.io")
        XCTAssertEqual(ServerAddress.normalize(" https://host.test/ ")?.absoluteString, "https://host.test")
        XCTAssertEqual(ServerAddress.normalize("https://host.test/v1")?.absoluteString, "https://host.test")
        XCTAssertEqual(ServerAddress.normalize("http://192.168.0.4:3000")?.absoluteString, "http://192.168.0.4:3000")
        XCTAssertNil(ServerAddress.normalize(""))
        XCTAssertNil(ServerAddress.normalize("   "))
    }
}
