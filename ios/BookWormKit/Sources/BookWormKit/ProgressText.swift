import Foundation

/// The words on the card. Pure functions, so the two cases that matter — a book
/// with no recorded page, and a correction downwards — are covered by tests
/// rather than by looking at a screen.
public enum ProgressText {
    /// The resting line: `180 / 224 · 80%`, or `Not started · 224 pages`.
    public static func summary(for book: Book) -> String {
        guard let pageCount = book.pageCount, pageCount > 0 else {
            if let current = book.currentPage {
                return "Page \(current)"
            }
            return "No page count"
        }
        guard let current = book.currentPage else {
            return "Not started · \(pageCount) pages"
        }
        let percent = Int((Double(current) / Double(pageCount) * 100).rounded())
        return "\(current) / \(pageCount) · \(percent)%"
    }

    /// The line shown while dragging: `212 · +32 pages`.
    ///
    /// A book with no recorded page has no delta to show — `null` is not zero,
    /// so it is not "+212 from page 0".
    public static func whileDragging(target: Int, from current: Int?) -> String {
        guard let current else {
            return "\(target) · first update"
        }
        let delta = target - current
        if delta == 0 { return "\(target) · no change" }
        let noun = abs(delta) == 1 ? "page" : "pages"
        let sign = delta > 0 ? "+" : "−"
        return "\(target) · \(sign)\(abs(delta)) \(noun)"
    }

    /// The brief inline confirmation after a write lands.
    public static func saved(pagesRead: Int?) -> String {
        guard let pagesRead, pagesRead > 0 else { return "Saved" }
        return pagesRead == 1 ? "Saved · 1 page read" : "Saved · \(pagesRead) pages read"
    }
}
