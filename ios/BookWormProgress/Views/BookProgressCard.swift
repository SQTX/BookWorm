import SwiftUI
import BookWormKit

struct BookProgressCard: View {
    let row: BookRow
    let commit: (Int) -> Void

    @State private var draggingTo: Int?
    @State private var savedTick = 0

    private var book: Book { row.book }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            statusLine
            control
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            // Starred books carry a gold edge instead of a heading: the order
            // says which ones they are, the border says why.
            if book.isPriority {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.gold, lineWidth: 2)
            }
        }
        .sensoryFeedback(.success, trigger: savedTick)
        .onChange(of: row.state) { _, state in
            if case .saved = state { savedTick += 1 }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            CoverThumbnail(hash: book.coverHash)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    if book.isPriority {
                        Image(systemName: "star.fill")
                            .font(.caption)
                            .foregroundStyle(Color.gold)
                    }
                    Text(book.title)
                        .font(.headline)
                        .lineLimit(2)      // a long title wraps once, then stops
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(book.author)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var statusLine: some View {
        HStack(spacing: 6) {
            if let draggingTo {
                Text(ProgressText.whileDragging(target: draggingTo, from: book.currentPage))
                    .foregroundStyle(Color.accentColor)
            } else {
                switch row.state {
                case .idle:
                    Text(ProgressText.summary(for: book))
                        .foregroundStyle(.secondary)
                case .saving:
                    Text(ProgressText.summary(for: book))
                        .foregroundStyle(.secondary)
                    ProgressView().controlSize(.mini)
                case .saved(let text):
                    Label(text, systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                case .queued(let reason):
                    Label("Queued · \(reason)", systemImage: "clock.arrow.circlepath")
                        .foregroundStyle(.orange)
                case .failed(let message):
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }
            }
            Spacer(minLength: 0)
        }
        .font(.subheadline.monospacedDigit())
        .lineLimit(1)
        .animation(.easeInOut(duration: 0.15), value: row.state)
    }

    @ViewBuilder
    private var control: some View {
        if let pageCount = book.pageCount, pageCount > 0 {
            PageSlider(
                pageCount: pageCount,
                page: book.currentPage ?? 0,
                onScrub: { draggingTo = $0 },
                onCommit: { page in
                    draggingTo = nil
                    commit(page)
                }
            )
        } else {
            // No page count means no range, and inventing one would write a
            // number the user never gave.
            PageNumberField(page: book.currentPage, commit: commit)
        }
    }
}

/// The fallback for a book with no `pageCount`.
private struct PageNumberField: View {
    let page: Int?
    let commit: (Int) -> Void

    @State private var text: String = ""
    @FocusState private var focused: Bool

    private var entered: Int? {
        guard let value = Int(text.trimmingCharacters(in: .whitespaces)), PageBounds.isValid(value) else { return nil }
        return value
    }

    var body: some View {
        HStack(spacing: 10) {
            TextField(page.map(String.init) ?? "Page", text: $text)
                .keyboardType(.numberPad)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .frame(maxWidth: 140)
            Button("Save") {
                guard let entered else { return }
                focused = false
                text = ""
                commit(entered)
            }
            .buttonStyle(.borderedProminent)
            .disabled(entered == nil || entered == page)
            Spacer(minLength: 0)
        }
    }
}

