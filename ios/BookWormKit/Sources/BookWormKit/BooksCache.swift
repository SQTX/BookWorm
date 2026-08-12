import Foundation

/// The last successful `GET /books?status=reading`, on disk, so the app opens to
/// the user's books rather than to a spinner.
public actor BooksCache {
    private let fileURL: URL?
    private var books: [Book] = []

    public init(fileURL: URL?) {
        self.fileURL = fileURL
        if let fileURL,
           let data = try? Data(contentsOf: fileURL),
           let stored = try? JSONDecoder().decode([Book].self, from: data) {
            books = stored
        }
    }

    public func load() -> [Book] { books }

    public func store(_ books: [Book]) {
        self.books = books
        guard let fileURL, let data = try? JSONEncoder().encode(books) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    public func clear() {
        books = []
        guard let fileURL else { return }
        try? FileManager.default.removeItem(at: fileURL)
    }
}
