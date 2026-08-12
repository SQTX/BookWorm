import SwiftUI
import BookWormKit

/// Asked for on first launch, and again whenever the session is gone — which,
/// on a seven-day personal provisioning profile, is a routine event rather than
/// a failure. The wording says so.
struct SignInView: View {
    let note: String?

    @Environment(AppModel.self) private var model
    @State private var address = ""
    @State private var email = ""
    @State private var password = ""
    @State private var remember = true
    @FocusState private var focus: Field?

    private enum Field { case address, email, password }

    private var canSubmit: Bool {
        !address.trimmingCharacters(in: .whitespaces).isEmpty
            && !email.trimmingCharacters(in: .whitespaces).isEmpty
            && !password.isEmpty
            && !model.isSigningIn
    }

    var body: some View {
        NavigationStack {
            Form {
                if let note {
                    Section {
                        Text(note)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Server") {
                    TextField("bookworm.example.com", text: $address)
                        .textContentType(.URL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focus, equals: .address)
                        .submitLabel(.next)
                        .onSubmit { focus = .email }
                }

                Section("Account") {
                    TextField("Email", text: $email)
                        .textContentType(.username)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focus, equals: .email)
                        .submitLabel(.next)
                        .onSubmit { focus = .password }
                    SecureField("Password", text: $password)
                        .textContentType(.password)
                        .focused($focus, equals: .password)
                        .submitLabel(.go)
                        .onSubmit { submit() }
                    // Kept in the Keychain, so the app can sign itself back in
                    // after a re-deploy takes the token with it.
                    Toggle("Stay signed in on this phone", isOn: $remember)
                }

                if let error = model.signInError {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .font(.footnote)
                    }
                }

                Section {
                    Button {
                        submit()
                    } label: {
                        HStack {
                            Text("Sign in")
                            if model.isSigningIn {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                    .disabled(!canSubmit)
                }
            }
            .navigationTitle("BookWorm")
            .onAppear {
                if address.isEmpty { address = model.serverAddressText }
                if email.isEmpty { email = model.rememberedEmail }
                if !email.isEmpty { focus = .password }
            }
        }
    }

    private func submit() {
        guard canSubmit else { return }
        focus = nil
        Task {
            await model.signIn(address: address, email: email, password: password, remember: remember)
            // Held only until the attempt is over: a wrong password should not
            // have to be retyped, a right one should not linger in view state.
            if model.signInError == nil { password = "" }
        }
    }
}
