import SwiftUI
import BookWormKit

struct BookProgressCard: View {
    let row: BookRow
    let commit: (Int) -> Void
    let togglePriority: () -> Void

    @Environment(AppModel.self) private var model
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
        .animation(.snappy(duration: 0.2), value: draggingTo == nil)
        .onChange(of: row.state) { _, state in
            if case .saved = state { savedTick += 1 }
        }
        .onChange(of: draggingTo) { _, proposal in
            // Tells the model to hold the periodic refresh: a list reloading
            // under a half-made change would discard it.
            model.setEditing(row.id, proposal != nil)
        }
        .onDisappear { model.setEditing(row.id, false) }
        .onChange(of: book.currentPage) { _, _ in
            // The server (or another device) moved the page while a proposal
            // was on screen. Drop it rather than let the user confirm a delta
            // measured against a number that no longer exists.
            draggingTo = nil
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            CoverThumbnail(hash: book.coverHash)
            VStack(alignment: .leading, spacing: 3) {
                Text(book.title)
                    .font(.headline)
                    .lineLimit(2)          // a long title wraps once, then stops
                    .fixedSize(horizontal: false, vertical: true)
                Text(book.author)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            priorityButton
        }
    }

    /// Top right, away from the slider: a mis-tap here should never be a page
    /// the user did not mean to write.
    private var priorityButton: some View {
        Button(action: togglePriority) {
            Image(systemName: book.isPriority ? "star.fill" : "star")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(book.isPriority ? Color.gold : Color.secondary)
                .frame(width: 34, height: 34)
                .background(Color(.tertiarySystemFill), in: Circle())
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.impact(weight: .light), trigger: book.isPriority)
        .accessibilityLabel(book.isPriority ? "Remove from priority" : "Add to priority")
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
            VStack(spacing: 8) {
                PageSlider(
                    pageCount: pageCount,
                    page: book.currentPage ?? 0,
                    draftPage: $draggingTo
                )
                if let proposed = draggingTo, proposed != book.currentPage {
                    confirmBar(proposed)
                }
            }
        } else {
            // No page count means no range, and inventing one would write a
            // number the user never gave.
            PageNumberField(page: book.currentPage, commit: commit)
        }
    }
}

private extension BookProgressCard {
    /// Nothing reaches the server until this is tapped.
    ///
    /// The slider used to write on release, which is fine on a card sitting
    /// still and wrong in a list being scrolled: brushing a slider on the way
    /// past would silently rewrite a page. A proposal plus one deliberate tap
    /// costs a second and cannot corrupt a reading history.
    @ViewBuilder
    func confirmBar(_ proposed: Int) -> some View {
        HStack(spacing: 8) {
            Button {
                draggingTo = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .frame(width: 34, height: 34)
                    .background(Color(.tertiarySystemFill), in: Capsule())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityLabel("Discard the change")

            Button {
                let page = proposed
                draggingTo = nil
                commit(page)
            } label: {
                Label(
                    ProgressText.whileDragging(target: proposed, from: book.currentPage),
                    systemImage: "checkmark"
                )
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .frame(maxWidth: .infinity)
                .frame(height: 34)
                .background(Color.accentColor, in: Capsule())
                .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Save page \(proposed)")
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
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

