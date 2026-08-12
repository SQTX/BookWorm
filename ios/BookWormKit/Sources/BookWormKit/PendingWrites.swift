import Foundation

/// A write the server has not confirmed yet.
public struct PendingWrite: Codable, Equatable, Sendable {
    public let bookId: Int
    public let currentPage: Int
    public let editedAt: Date

    public init(bookId: Int, currentPage: Int, editedAt: Date) {
        self.bookId = bookId
        self.currentPage = currentPage
        self.editedAt = editedAt
    }
}

/// The offline write queue: persisted, coalesced per book, and never cleared by
/// a failure.
///
/// A page number is a state, not an increment, so two queued updates for the
/// same book collapse to the later one — replaying both would just write the
/// same book twice and record a second session for a day that already has one.
public actor PendingWriteStore {
    private let fileURL: URL?
    private var writes: [Int: PendingWrite] = [:]

    /// - Parameter fileURL: nil keeps the queue in memory only (tests).
    public init(fileURL: URL?) {
        self.fileURL = fileURL
        if let fileURL,
           let data = try? Data(contentsOf: fileURL),
           let stored = try? JSONDecoder().decode([PendingWrite].self, from: data) {
            for write in stored {
                if let existing = writes[write.bookId], existing.editedAt >= write.editedAt { continue }
                writes[write.bookId] = write
            }
        }
    }

    public func enqueue(_ write: PendingWrite) {
        if let existing = writes[write.bookId], existing.editedAt > write.editedAt { return }
        writes[write.bookId] = write
        persist()
    }

    /// Removes a write only when the server has confirmed *that* write. A newer
    /// edit made while the flush was in flight stays queued — dropping it would
    /// discard the page the user is actually on.
    public func confirm(_ write: PendingWrite) {
        guard let existing = writes[write.bookId], existing == write else { return }
        writes.removeValue(forKey: write.bookId)
        persist()
    }

    /// For a write the server refused permanently (a 400 or a 404). Retrying it
    /// forever cannot succeed, and leaving it queued tells the user something is
    /// pending that never will be.
    public func discard(bookId: Int) {
        guard writes[bookId] != nil else { return }
        writes.removeValue(forKey: bookId)
        persist()
    }

    public func all() -> [PendingWrite] {
        writes.values.sorted { $0.editedAt < $1.editedAt }
    }

    public func write(for bookId: Int) -> PendingWrite? {
        writes[bookId]
    }

    public var count: Int { writes.count }

    public func removeAll() {
        writes = [:]
        persist()
    }

    private func persist() {
        guard let fileURL else { return }
        guard let data = try? JSONEncoder().encode(all()) else { return }
        // Atomic: a queue half-written by a kill at the wrong moment is a queue
        // that loses writes, which is the one thing it exists not to do.
        try? data.write(to: fileURL, options: .atomic)
    }
}
