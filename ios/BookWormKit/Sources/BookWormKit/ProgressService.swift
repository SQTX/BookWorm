import Foundation

public enum SubmitOutcome: Sendable, Equatable {
    /// The server took it and this is what it now holds.
    case saved(Book)
    /// Could not reach the server, or the server asked to be tried later. The
    /// write is on disk and will go out on the next flush.
    case queued(String)
    /// The server refused it and always will. Nothing stays queued; the user is
    /// told. A refused write beats a wrong one.
    case refused(APIError)
}

public struct FlushSummary: Sendable, Equatable {
    public var confirmed: [Book] = []
    public var stillQueued: Int = 0
    public var refused: [Int: APIError] = [:]
    public var attempted: Int = 0
}

/// Ties the three pieces together: the API, the write queue and the on-disk
/// cache. Kept out of the views so it can be tested without a simulator.
public actor ProgressService {
    private let api: APIClient
    private let queue: PendingWriteStore
    private let cache: BooksCache
    private let log: AppLog
    private let now: @Sendable () -> Date

    public init(
        api: APIClient,
        queue: PendingWriteStore,
        cache: BooksCache,
        log: AppLog,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.api = api
        self.queue = queue
        self.cache = cache
        self.log = log
        self.now = now
    }

    /// What to show before the network has answered anything.
    public func cachedBooks() async -> [Book] {
        await overlayPending(on: cache.load())
    }

    public func pendingCount() async -> Int {
        await queue.count
    }

    public func pendingWrite(for bookId: Int) async -> PendingWrite? {
        await queue.write(for: bookId)
    }

    /// Fetches the reading list, filtered server-side, and caches it. Queued
    /// writes are laid over the result so a book never flicks back to the
    /// server's older page while an edit is still pending.
    public func refresh() async throws -> [Book] {
        do {
            let books = try await api.readingBooks()
            await cache.store(books)
            await log.write("Fetched \(books.count) book(s) being read")
            return await overlayPending(on: books)
        } catch let error as APIError {
            await log.write("Fetch failed: \(error.userFacingText)")
            throw error
        }
    }

    /// Records a page. The write is persisted *before* it is attempted, so a
    /// crash between the tap and the response cannot lose it.
    public func submit(bookId: Int, currentPage: Int) async -> SubmitOutcome {
        let write = PendingWrite(bookId: bookId, currentPage: currentPage, editedAt: now())
        await queue.enqueue(write)
        await log.write("Queued: book \(bookId) → page \(currentPage)")
        return await send(write)
    }

    /// Called on launch and every time the app comes to the foreground.
    @discardableResult
    public func flush() async -> FlushSummary {
        var summary = FlushSummary()
        let pending = await queue.all()
        guard !pending.isEmpty else { return summary }

        await log.write("Flushing \(pending.count) queued write(s)")
        summary.attempted = pending.count

        for write in pending {
            switch await send(write) {
            case .saved(let book):
                summary.confirmed.append(book)
            case .queued:
                summary.stillQueued += 1
            case .refused(let error):
                summary.refused[write.bookId] = error
            }
        }

        if summary.stillQueued > 0 {
            await log.write("\(summary.stillQueued) write(s) still queued")
        }
        return summary
    }

    // MARK: -

    private func send(_ write: PendingWrite) async -> SubmitOutcome {
        do {
            let response = try await api.recordProgress(bookId: write.bookId, currentPage: write.currentPage)
            await queue.confirm(write)
            await updateCache(with: response.book)
            return .saved(response.book)
        } catch let error as APIError {
            if error.isRetryable {
                await log.write("Write for book \(write.bookId) stays queued: \(error.userFacingText)")
                return .queued(error.userFacingText)
            }
            await queue.discard(bookId: write.bookId)
            await log.write("Write for book \(write.bookId) refused and dropped: \(error.userFacingText)")
            return .refused(error)
        } catch {
            await log.write("Write for book \(write.bookId) stays queued: \(error.localizedDescription)")
            return .queued(error.localizedDescription)
        }
    }

    private func updateCache(with book: Book) async {
        var books = await cache.load()
        if let index = books.firstIndex(where: { $0.id == book.id }) {
            books[index] = book
        } else {
            books.append(book)
        }
        await cache.store(books)
    }

    private func overlayPending(on books: [Book]) async -> [Book] {
        let pending = await queue.all()
        guard !pending.isEmpty else { return books }
        let byBook = Dictionary(uniqueKeysWithValues: pending.map { ($0.bookId, $0) })
        return books.map { book in
            guard let write = byBook[book.id] else { return book }
            return book.withCurrentPage(write.currentPage)
        }
    }
}
