import Foundation

/// The part of the server's book payload this app actually uses.
///
/// The API rejects unknown fields on the way *in*, but sends the full row on the
/// way out; decoding a subset is deliberate — every field decoded here is a field
/// that can break the screen when the server adds or renames something.
///
/// `pageCount` and `currentPage` are optional and the optionality is the point:
/// `null` means "not recorded", never zero.
public struct Book: Codable, Identifiable, Equatable, Sendable {
    public let id: Int
    public let title: String
    public let author: String
    public let pageCount: Int?
    public let currentPage: Int?
    public let coverHash: String?
    public let audioMode: String?

    public init(
        id: Int,
        title: String,
        author: String,
        pageCount: Int? = nil,
        currentPage: Int? = nil,
        coverHash: String? = nil,
        audioMode: String? = nil
    ) {
        self.id = id
        self.title = title
        self.author = author
        self.pageCount = pageCount
        self.currentPage = currentPage
        self.coverHash = coverHash
        self.audioMode = audioMode
    }

    /// 0…1, or nil when either end of the fraction is unknown.
    public var progressFraction: Double? {
        guard let pageCount, pageCount > 0, let currentPage else { return nil }
        return min(1, max(0, Double(currentPage) / Double(pageCount)))
    }

    /// A book the user has not recorded a page for yet. Distinct from page 0.
    public var isUnstarted: Bool { currentPage == nil }

    /// Without a page count there is no slider range, so the card falls back to a
    /// plain number field. Inventing a range here is what would corrupt data.
    public var hasSliderRange: Bool { (pageCount ?? 0) > 0 }

    /// Returns a copy with a new current page — used to apply a queued write
    /// optimistically without waiting for the server's echo.
    public func withCurrentPage(_ page: Int?) -> Book {
        Book(
            id: id,
            title: title,
            author: author,
            pageCount: pageCount,
            currentPage: page,
            coverHash: coverHash,
            audioMode: audioMode
        )
    }
}

/// `GET /v1/books?status=reading`
public struct BooksResponse: Codable, Sendable {
    public let books: [Book]
    public init(books: [Book]) { self.books = books }
}

/// `POST /v1/books/:id/progress`
public struct ProgressResponse: Codable, Sendable {
    public let book: Book
    public let pagesRead: Int?
    public init(book: Book, pagesRead: Int?) {
        self.book = book
        self.pagesRead = pagesRead
    }
}

/// The server's bound on `currentPage`. Checked client-side so an out-of-range
/// value is refused before it becomes a 400 buried in the write queue.
public enum PageBounds {
    public static let minimum = 0
    public static let maximum = 100_000

    public static func isValid(_ page: Int) -> Bool {
        (minimum...maximum).contains(page)
    }

    public static func clamp(_ page: Int) -> Int {
        min(maximum, max(minimum, page))
    }
}
