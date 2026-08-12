import XCTest
@testable import BookWormKit

final class PendingWriteStoreTests: XCTestCase {
    func testTwoWritesForOneBookCollapseToTheLater() async {
        let store = PendingWriteStore(fileURL: nil)
        let earlier = PendingWrite(bookId: 42, currentPage: 200, editedAt: Date(timeIntervalSince1970: 100))
        let later = PendingWrite(bookId: 42, currentPage: 212, editedAt: Date(timeIntervalSince1970: 200))

        await store.enqueue(earlier)
        await store.enqueue(later)

        let all = await store.all()
        XCTAssertEqual(all, [later], "a page number is a state, not an increment")
    }

    func testAnOlderWriteDoesNotOverwriteANewerOne() async {
        let store = PendingWriteStore(fileURL: nil)
        let later = PendingWrite(bookId: 42, currentPage: 212, editedAt: Date(timeIntervalSince1970: 200))
        let earlier = PendingWrite(bookId: 42, currentPage: 200, editedAt: Date(timeIntervalSince1970: 100))

        await store.enqueue(later)
        await store.enqueue(earlier)

        let all = await store.all()
        XCTAssertEqual(all, [later])
    }

    func testConfirmingAnOlderWriteLeavesANewerOneQueued() async {
        let store = PendingWriteStore(fileURL: nil)
        let first = PendingWrite(bookId: 42, currentPage: 200, editedAt: Date(timeIntervalSince1970: 100))
        await store.enqueue(first)

        // The user moves the slider again while the first request is in flight.
        let second = PendingWrite(bookId: 42, currentPage: 212, editedAt: Date(timeIntervalSince1970: 200))
        await store.enqueue(second)
        await store.confirm(first)

        let all = await store.all()
        XCTAssertEqual(all, [second], "confirming the request that finished must not drop the newer edit")
    }

    func testTheQueueSurvivesRelaunch() async {
        let url = temporaryFileURL("queue.json")
        let store = PendingWriteStore(fileURL: url)
        await store.enqueue(PendingWrite(bookId: 7, currentPage: 55, editedAt: Date(timeIntervalSince1970: 10)))

        let reopened = PendingWriteStore(fileURL: url)
        let all = await reopened.all()

        XCTAssertEqual(all.map(\.bookId), [7])
        XCTAssertEqual(all.map(\.currentPage), [55])
    }
}

final class ProgressServiceTests: XCTestCase {
    private let base = URL(string: "https://example.test")!

    private func makeService(
        _ exchanges: [StubHTTP.Exchange],
        queue: PendingWriteStore = PendingWriteStore(fileURL: nil),
        cache: BooksCache = BooksCache(fileURL: nil)
    ) -> (ProgressService, StubHTTP, PendingWriteStore, BooksCache) {
        let http = StubHTTP(exchanges)
        let log = AppLog(fileURL: nil)
        let api = APIClient(
            baseURL: base,
            session: http,
            tokens: InMemoryTokenStorage(TokenPair(accessToken: "a1", refreshToken: "r1")),
            log: log
        )
        let service = ProgressService(api: api, queue: queue, cache: cache, log: log)
        return (service, http, queue, cache)
    }

    func testASuccessfulWriteLeavesNothingQueued() async {
        let saved = Book.fixture(currentPage: 212)
        let (service, _, queue, cache) = makeService([
            .json(200, ["book": saved.asJSON, "pagesRead": 32])
        ])

        let outcome = await service.submit(bookId: 42, currentPage: 212)

        XCTAssertEqual(outcome, .saved(saved))
        let pending = await queue.all()
        XCTAssertTrue(pending.isEmpty)
        let cached = await cache.load()
        XCTAssertEqual(cached.first?.currentPage, 212)
    }

    func testAnOfflineWriteStaysQueued() async {
        let (service, _, queue, _) = makeService([
            .failure(URLError(.notConnectedToInternet))
        ])

        let outcome = await service.submit(bookId: 42, currentPage: 212)

        guard case .queued = outcome else { return XCTFail("expected the write to be queued: \(outcome)") }
        let pending = await queue.all()
        XCTAssertEqual(pending.map(\.currentPage), [212])
    }

    func testARefusedWriteIsNotKeptForever() async {
        let (service, _, queue, _) = makeService([
            .json(404, ["error": "Not Found"])
        ])

        let outcome = await service.submit(bookId: 42, currentPage: 212)

        guard case .refused = outcome else { return XCTFail("expected a refusal: \(outcome)") }
        let pending = await queue.all()
        XCTAssertTrue(pending.isEmpty, "a write the server will always refuse must not sit in the queue pretending to be pending")
    }

    func testFlushSendsEverythingQueuedAndClearsWhatLands() async {
        let queue = PendingWriteStore(fileURL: nil)
        await queue.enqueue(PendingWrite(bookId: 1, currentPage: 10, editedAt: Date(timeIntervalSince1970: 1)))
        await queue.enqueue(PendingWrite(bookId: 2, currentPage: 20, editedAt: Date(timeIntervalSince1970: 2)))

        let (service, http, _, _) = makeService([
            .json(200, ["book": Book.fixture(id: 1, currentPage: 10).asJSON, "pagesRead": 3]),
            .json(200, ["book": Book.fixture(id: 2, currentPage: 20).asJSON, "pagesRead": 4])
        ], queue: queue)

        let summary = await service.flush()

        XCTAssertEqual(summary.attempted, 2)
        XCTAssertEqual(summary.confirmed.count, 2)
        XCTAssertEqual(summary.stillQueued, 0)
        XCTAssertEqual(http.requestCount, 2)
        let pending = await queue.all()
        XCTAssertTrue(pending.isEmpty)
    }

    func testAFlushThatFailsKeepsTheWrite() async {
        let queue = PendingWriteStore(fileURL: nil)
        await queue.enqueue(PendingWrite(bookId: 1, currentPage: 10, editedAt: Date(timeIntervalSince1970: 1)))

        let (service, _, _, _) = makeService([
            .failure(URLError(.timedOut))
        ], queue: queue)

        let summary = await service.flush()

        XCTAssertEqual(summary.stillQueued, 1)
        let pending = await queue.all()
        XCTAssertEqual(pending.map(\.currentPage), [10])
    }

    func testAQueuedEditWinsOverTheServersOlderValue() async {
        let queue = PendingWriteStore(fileURL: nil)
        await queue.enqueue(PendingWrite(bookId: 42, currentPage: 212, editedAt: Date(timeIntervalSince1970: 1)))

        let (service, _, _, _) = makeService([
            .json(200, ["books": [Book.fixture(currentPage: 180).asJSON]])
        ], queue: queue)

        let books = try? await service.refresh()

        XCTAssertEqual(books?.first?.currentPage, 212, "a pending edit must not flick back to the server's page")
    }

    func testTheStarIsAPatchCarryingOnlyThatField() async {
        let saved = Book.fixture(isPriority: true)
        let (service, http, queue, cache) = makeService([
            .json(200, saved.asJSON)
        ])

        let result = await service.setPriority(bookId: 42, isPriority: true)

        XCTAssertEqual(try? result.get(), saved)
        XCTAssertEqual(http.request(0).httpMethod, "PATCH")
        XCTAssertTrue(http.request(0).url!.absoluteString.hasSuffix("/v1/books/42"))
        XCTAssertEqual(http.body(0) as? [String: Bool], ["isPriority": true])

        let cached = await cache.load()
        XCTAssertEqual(cached.first?.isPriority, true)
        let pending = await queue.all()
        XCTAssertTrue(pending.isEmpty, "a star is not a write worth queueing")
    }

    func testAFailedStarIsReportedRatherThanQueued() async {
        let (service, _, queue, _) = makeService([
            .failure(URLError(.notConnectedToInternet))
        ])

        let result = await service.setPriority(bookId: 42, isPriority: true)

        XCTAssertNil(try? result.get())
        let pending = await queue.all()
        XCTAssertTrue(pending.isEmpty)
    }

    func testThePlannedListIsFetchedWithItsOwnServerSideFilter() async throws {
        let plannedCache = BooksCache(fileURL: nil)
        let http = StubHTTP([
            .json(200, ["books": [Book.fixture(id: 7, title: "Dune").asJSON]])
        ])
        let log = AppLog(fileURL: nil)
        let api = APIClient(
            baseURL: base,
            session: http,
            tokens: InMemoryTokenStorage(TokenPair(accessToken: "a1", refreshToken: "r1")),
            log: log
        )
        let service = ProgressService(
            api: api,
            queue: PendingWriteStore(fileURL: nil),
            cache: BooksCache(fileURL: nil),
            plannedCache: plannedCache,
            log: log
        )

        let books = try await service.refreshPlanned()

        XCTAssertEqual(books.map(\.id), [7])
        XCTAssertTrue(http.request(0).url!.absoluteString.hasSuffix("/v1/books?status=planned"), http.request(0).url!.absoluteString)

        // Cached, so opening the section again does not open onto a spinner.
        let cached = await service.cachedPlannedBooks()
        XCTAssertEqual(cached.map(\.id), [7])
    }

    func testTheReadingAndPlannedCachesDoNotOverwriteEachOther() async throws {
        let reading = BooksCache(fileURL: nil)
        let planned = BooksCache(fileURL: nil)
        let http = StubHTTP([
            .json(200, ["books": [Book.fixture(id: 1).asJSON]]),
            .json(200, ["books": [Book.fixture(id: 2).asJSON]])
        ])
        let log = AppLog(fileURL: nil)
        let api = APIClient(
            baseURL: base,
            session: http,
            tokens: InMemoryTokenStorage(TokenPair(accessToken: "a1", refreshToken: "r1")),
            log: log
        )
        let service = ProgressService(
            api: api,
            queue: PendingWriteStore(fileURL: nil),
            cache: reading,
            plannedCache: planned,
            log: log
        )

        _ = try await service.refresh()
        _ = try await service.refreshPlanned()

        let readingBooks = await reading.load()
        let plannedBooks = await planned.load()
        XCTAssertEqual(readingBooks.map(\.id), [1])
        XCTAssertEqual(plannedBooks.map(\.id), [2])
    }

    func testTheCachedListIsThereBeforeTheNetworkIs() async {
        let cache = BooksCache(fileURL: nil)
        await cache.store([Book.fixture()])
        let (service, http, _, _) = makeService([], cache: cache)

        let books = await service.cachedBooks()

        XCTAssertEqual(books.map(\.id), [42])
        XCTAssertEqual(http.requestCount, 0, "opening the app must not require the network")
    }

    func testAFailedRefreshDoesNotWipeTheCachedList() async {
        let cache = BooksCache(fileURL: nil)
        await cache.store([Book.fixture()])
        let (service, _, _, _) = makeService([
            .failure(URLError(.notConnectedToInternet))
        ], cache: cache)

        _ = try? await service.refresh()

        let stillCached = await cache.load()
        XCTAssertEqual(stillCached.map(\.id), [42])
    }
}
