import SwiftUI
import BookWormKit

/// The app. One screen, a card per book being read, a slider on each.
struct ReadingListView: View {
    @Environment(AppModel.self) private var model
    @State private var showingSettings = false

    var body: some View {
        NavigationStack {
            Group {
                if model.rows.isEmpty {
                    emptyState
                } else {
                    list
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Reading")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                }
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
        }
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                if let listError = model.listError {
                    banner(listError)
                }
                ForEach(model.rows) { row in
                    BookProgressCard(row: row) { page in
                        model.commit(bookId: row.id, page: page)
                    }
                }
                if model.pendingCount > 0 {
                    Text("^[\(model.pendingCount) update](inflect: true) waiting to be sent")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }
            }
            .padding(16)
        }
        .refreshable { await model.refresh() }
    }

    private var emptyState: some View {
        ScrollView {
            ContentUnavailableView {
                Label("Nothing being read", systemImage: "books.vertical")
            } description: {
                Text("Books set to *reading* on the Mac show up here.")
            } actions: {
                Button("Check again") {
                    Task { await model.refresh() }
                }
                .buttonStyle(.bordered)
            }
            .padding(.top, 60)
        }
        .refreshable { await model.refresh() }
    }

    private func banner(_ text: String) -> some View {
        Label(text, systemImage: "wifi.slash")
            .font(.footnote)
            .foregroundStyle(.orange)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
