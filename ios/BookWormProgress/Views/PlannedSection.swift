import SwiftUI
import BookWormKit

/// "To read", at the bottom, collapsed.
///
/// Collapsed is not just a default — it is what keeps this from costing
/// anything: the request goes out the first time it is opened, never at launch.
/// These books are not being read, so they get no slider; the list is here to
/// be glanced at, and the desktop is where a book is started.
struct PlannedSection: View {
    @Environment(AppModel.self) private var model
    @State private var expanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            content
                .padding(.top, 8)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "bookmark")
                Text("To read")
                if case .loaded(let books) = model.planned {
                    Text("\(books.count)")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            .font(.subheadline.weight(.semibold))
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onChange(of: expanded) { _, isOpen in
            if isOpen { Task { await model.loadPlanned() } }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.planned {
        case .notLoaded, .loading:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Loading").foregroundStyle(.secondary)
            }
            .font(.footnote)
            .frame(maxWidth: .infinity, alignment: .leading)
        case .failed(let message):
            HStack(spacing: 8) {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Spacer(minLength: 0)
                Button("Retry") { Task { await model.loadPlanned(force: true) } }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
            .font(.footnote)
        case .loaded(let books):
            if books.isEmpty {
                Text("Nothing planned")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(spacing: 10) {
                    ForEach(books) { book in
                        PlannedRow(book: book)
                        if book.id != books.last?.id {
                            Divider()
                        }
                    }
                }
            }
        }
    }
}

private struct PlannedRow: View {
    let book: Book

    var body: some View {
        HStack(spacing: 10) {
            CoverThumbnail(hash: book.coverHash, width: 30, height: 45)
            VStack(alignment: .leading, spacing: 2) {
                Text(book.title)
                    .font(.subheadline)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(book.author)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if book.isPriority {
                Image(systemName: "star.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            if let pageCount = book.pageCount {
                Text("\(pageCount)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
        }
    }
}
