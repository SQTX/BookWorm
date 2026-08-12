import Foundation

/// A log the user can actually read, in Settings.
///
/// "Nothing happened" and "nothing was attempted" look identical from outside,
/// and telling them apart was most of the work every time the desktop's sync
/// misbehaved. This is the cheap insurance against repeating that here.
public actor AppLog {
    private let fileURL: URL?
    private let limit: Int
    private var lines: [String] = []
    private let formatter: DateFormatter

    /// - Parameter fileURL: nil keeps the log in memory only (tests).
    public init(fileURL: URL?, limit: Int = 300) {
        self.fileURL = fileURL
        self.limit = limit
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        self.formatter = formatter
        if let fileURL, let existing = try? String(contentsOf: fileURL, encoding: .utf8) {
            lines = existing.split(separator: "\n", omittingEmptySubsequences: true).map(String.init).suffix(limit)
        }
    }

    public func write(_ message: String) {
        lines.append("\(formatter.string(from: Date()))  \(message)")
        if lines.count > limit { lines.removeFirst(lines.count - limit) }
        flush()
    }

    /// Newest first, which is the order anyone opening a log wants.
    public func recent() -> [String] {
        lines.reversed()
    }

    public func clear() {
        lines = []
        flush()
    }

    private func flush() {
        guard let fileURL else { return }
        let text = lines.joined(separator: "\n")
        try? text.write(to: fileURL, atomically: true, encoding: .utf8)
    }
}
