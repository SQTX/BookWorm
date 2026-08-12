import SwiftUI
import BookWormKit

/// The server address, signing out, and the log. Nothing else belongs here —
/// everything the desktop does stays on the desktop.
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var address = ""
    @State private var addressError = false
    @State private var confirmingSignOut = false
    @State private var logLines: [String] = []

    /// Plain text rather than an inflected localisation key: the dialog takes a
    /// `String` here, and markup in a `String` is shown as markup.
    private var signOutPrompt: String {
        let count = model.unsentWriteCount
        guard count > 0 else { return "Sign out?" }
        let noun = count == 1 ? "update has" : "updates have"
        return "\(count) \(noun) not been sent. They stay queued and go out after you sign in again."
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Server") {
                    TextField("Address", text: $address)
                        .textContentType(.URL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("Use this address") {
                        Task {
                            addressError = !(await model.changeServerAddress(address))
                        }
                    }
                    .disabled(address == model.serverAddressText || address.isEmpty)
                    if addressError {
                        Text("That is not a URL")
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }

                if model.unsentWriteCount > 0 {
                    Section {
                        Label(
                            "^[\(model.unsentWriteCount) update](inflect: true) has not reached the server yet",
                            systemImage: "clock.arrow.circlepath"
                        )
                        .foregroundStyle(.orange)
                        .font(.footnote)
                    }
                }

                Section {
                    Button("Sign out", role: .destructive) {
                        confirmingSignOut = true
                    }
                }

                Section {
                    if logLines.isEmpty {
                        Text("Nothing logged yet")
                            .foregroundStyle(.secondary)
                            .font(.footnote)
                    } else {
                        ForEach(logLines.prefix(50), id: \.self) { line in
                            Text(line)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Activity")
                } footer: {
                    Text("What the app did, newest first. Kept so that \"nothing happened\" and \"nothing was attempted\" can be told apart.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .confirmationDialog(
                signOutPrompt,
                isPresented: $confirmingSignOut,
                titleVisibility: .visible
            ) {
                Button("Sign out", role: .destructive) {
                    Task {
                        await model.signOut()
                        dismiss()
                    }
                }
                Button("Cancel", role: .cancel) {}
            }
            .task {
                address = model.serverAddressText
                logLines = await model.recentLog()
            }
        }
    }
}
