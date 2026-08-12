import Foundation
import Observation
import BookWormKit

/// One book on the screen: what the server last said, plus what this app is
/// doing about it.
struct BookRow: Identifiable, Equatable {
    enum State: Equatable {
        case idle
        case saving
        case saved(String)
        /// Written down, not sent yet.
        case queued(String)
        /// The server refused it; the shown page has been put back.
        case failed(String)
    }

    var book: Book
    var state: State = .idle

    var id: Int { book.id }
}

@MainActor
@Observable
final class AppModel {
    enum Screen: Equatable {
        case launching
        case signIn(note: String?)
        case list
    }

    /// The "to read" list: fetched only when the section is opened, because a
    /// list that is collapsed by default should not cost a request at launch.
    enum PlannedState: Equatable {
        case notLoaded
        case loading
        case loaded([Book])
        case failed(String)
    }

    private(set) var screen: Screen = .launching
    private(set) var rows: [BookRow] = []
    private(set) var pendingCount = 0
    private(set) var isRefreshing = false
    private(set) var listError: String?
    private(set) var planned: PlannedState = .notLoaded

    /// Starred on the desktop, and pinned to the top here.
    var priorityRows: [BookRow] { rows.filter(\.book.isPriority) }
    var standardRows: [BookRow] { rows.filter { !$0.book.isPriority } }
    private(set) var signInError: String?
    private(set) var isSigningIn = false

    var serverAddressText: String {
        settings.baseURL?.absoluteString ?? ""
    }

    /// Prefilled on the sign-in screen; not a secret, so it lives in
    /// `UserDefaults` next to the address.
    var rememberedEmail: String { settings.email ?? "" }

    private let settings = SettingsStore()
    private let files = AppFiles()
    private let log: AppLog
    private let tokens: TokenStorage
    private let credentials = CredentialStore()
    private let session: URLSession

    private var api: APIClient?
    private var service: ProgressService?
    private var covers: CoverStore?
    private var savedBadgeTasks: [Int: Task<Void, Never>] = [:]

    init() {
        log = AppLog(fileURL: files.logFile)
        tokens = KeychainTokenStorage()

        // One session for everything, with a disk cache big enough for the
        // covers. They are served immutable with a one-year lifetime, so the
        // work here is to let URLSession do its job rather than to write a
        // cache of our own.
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = URLCache(
            memoryCapacity: 8 * 1024 * 1024,
            diskCapacity: 200 * 1024 * 1024,
            directory: files.coverCacheDirectory
        )
        configuration.requestCachePolicy = .useProtocolCachePolicy
        configuration.waitsForConnectivity = false
        session = URLSession(configuration: configuration)
    }

    // MARK: - Lifecycle

    func start() async {
        guard case .launching = screen else { return }
        await log.write("App launched")

        guard let baseURL = settings.baseURL else {
            screen = .signIn(note: nil)
            return
        }
        let services = await makeServices(baseURL: baseURL)

        // Show whatever was cached before anything touches the network.
        rows = (await services.service.cachedBooks()).map { BookRow(book: $0) }

        if await services.api.hasStoredSession() {
            screen = .list
            await flushThenRefresh()
            return
        }

        // No token, but the user asked to be remembered: sign in again without
        // stopping to ask. This is what makes a re-deploy invisible — the
        // Keychain token is the first thing a reinstall takes.
        if let stored = await credentials.load() {
            await log.write("No stored session; signing in with remembered credentials")
            do {
                try await services.api.logIn(email: stored.email, password: stored.password)
                screen = .list
                await flushThenRefresh()
                return
            } catch let error as APIError {
                await log.write("Automatic sign-in failed: \(error.userFacingText)")
                // Wrong password now means the password changed; anything else
                // is the network, and the saved credentials stay put.
                if case .http(let status, _) = error, status == 401 {
                    await credentials.clear()
                    screen = .signIn(note: "The saved password no longer works. Sign in again.")
                    return
                }
                screen = .signIn(note: "Could not reach the server to sign in. Try again when you have signal.")
                return
            } catch {
                screen = .signIn(note: nil)
                return
            }
        }

        await log.write("No stored session")
        screen = .signIn(note: Self.reinstallNote)
    }

    func onForeground() async {
        guard case .list = screen, service != nil else { return }
        await flushThenRefresh()
    }

    /// The seven-day free provisioning profile means reinstalling is routine,
    /// and a reinstall takes the Keychain item with it. That is an ordinary
    /// path, so it gets ordinary words rather than an error.
    private static let reinstallNote =
        "No stored session. That is normal after the app is re-deployed from Xcode — sign in again."

    // MARK: - Sign in and out

    func signIn(address: String, email: String, password: String, remember: Bool = true) async {
        signInError = nil

        guard let baseURL = ServerAddress.normalize(address) else {
            signInError = APIError.invalidBaseURL.userFacingText
            return
        }
        isSigningIn = true
        defer { isSigningIn = false }

        let services = await makeServices(baseURL: baseURL)
        do {
            try await services.api.logIn(email: email, password: password)
            settings.baseURL = baseURL
            settings.email = email
            if remember {
                await credentials.save(StoredCredentials(email: email, password: password))
            } else {
                await credentials.clear()
            }
            screen = .list
            rows = (await services.service.cachedBooks()).map { BookRow(book: $0) }
            await flushThenRefresh()
        } catch let error as APIError {
            // 401 here is a wrong password, not an expired session.
            if case .http(let status, _) = error, status == 401 {
                signInError = "Wrong email or password"
            } else {
                signInError = error.userFacingText
            }
            await log.write("Sign-in failed: \(error.userFacingText)")
        } catch {
            signInError = error.localizedDescription
        }
    }

    func signOut() async {
        // One last flush before the token goes: an update made seconds ago
        // still gets its chance. Whatever does not land stays in the queue —
        // signing out is not a reason to delete the user's unsent writes.
        if let service { _ = await service.flush() }
        await api?.logOut()
        // Signing out has to mean it: otherwise the next launch signs straight
        // back in with the remembered password.
        await credentials.clear()
        pendingCount = await service?.pendingCount() ?? 0
        rows = []
        listError = nil
        screen = .signIn(note: nil)
    }

    /// Signing out throws away anything not yet sent, so the user is told how
    /// much that is before being asked.
    var unsentWriteCount: Int { pendingCount }

    // MARK: - The list

    func refresh() async {
        guard let service else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let books = try await service.refresh()
            merge(books)
            listError = nil
        } catch let error as APIError {
            listError = error.userFacingText
        } catch {
            listError = error.localizedDescription
        }
        pendingCount = await service.pendingCount()

        // Only if it has already been opened: a collapsed section stays unfetched.
        if case .loaded = planned { await loadPlanned(force: true) }
    }

    /// Called when the "to read" section is opened, and again by a pull to
    /// refresh once it has been opened at least once.
    func loadPlanned(force: Bool = false) async {
        guard let service else { return }
        if case .loading = planned { return }
        if case .loaded = planned, !force { return }

        let cached = await service.cachedPlannedBooks()
        if !cached.isEmpty {
            planned = .loaded(cached)
        } else if !force {
            planned = .loading
        }

        do {
            planned = .loaded(try await service.refreshPlanned())
        } catch let error as APIError {
            // A cached list beats an error message: the books have not changed
            // just because the phone cannot reach the server.
            if cached.isEmpty { planned = .failed(error.userFacingText) }
        } catch {
            if cached.isEmpty { planned = .failed(error.localizedDescription) }
        }
    }

    private func flushThenRefresh() async {
        guard let service else { return }
        let summary = await service.flush()
        if !summary.confirmed.isEmpty || !summary.refused.isEmpty {
            for book in summary.confirmed { apply(book: book, state: .saved(ProgressText.saved(pagesRead: nil))) }
            for (bookId, error) in summary.refused {
                setState(.failed(error.userFacingText), for: bookId)
            }
        }
        await refresh()
    }

    // MARK: - Writing

    /// Called once, on release of the slider — never while dragging.
    func commit(bookId: Int, page: Int) {
        guard let service, let index = rows.firstIndex(where: { $0.id == bookId }) else { return }
        let previous = rows[index].book

        // Optimistic: the card shows the new page immediately. The user finds
        // out what they did by looking at the card, not at a spinner.
        rows[index].book = previous.withCurrentPage(page)
        rows[index].state = .saving
        cancelSavedBadge(for: bookId)

        Task { [weak self] in
            let outcome = await service.submit(bookId: bookId, currentPage: page)
            guard let self else { return }
            switch outcome {
            case .saved(let book):
                let pagesRead = previous.currentPage.map { max(0, page - $0) }
                self.apply(book: book, state: .saved(ProgressText.saved(pagesRead: pagesRead)))
                self.scheduleSavedBadgeClear(for: bookId)
            case .queued(let reason):
                self.setState(.queued(reason), for: bookId)
            case .refused(let error):
                // Put the shown value back: a page the server refused is not
                // the page the book is on, and pretending otherwise is the
                // wrong write this app is built to avoid.
                self.restore(previous, state: .failed(error.userFacingText))
            }
            self.pendingCount = await service.pendingCount()
        }
    }

    /// The star, from the card. Flips immediately — the list reorders under the
    /// thumb — and goes back if the server refuses, because a star that lies is
    /// worse than a star that bounces.
    func togglePriority(bookId: Int) {
        guard let service, let index = rows.firstIndex(where: { $0.id == bookId }) else { return }
        let previous = rows[index].book
        let wanted = !previous.isPriority

        rows[index].book = previous.withPriority(wanted)

        Task { [weak self] in
            let result = await service.setPriority(bookId: bookId, isPriority: wanted)
            guard let self else { return }
            switch result {
            case .success(let book):
                self.apply(book: book, state: self.rows.first { $0.id == bookId }?.state ?? .idle)
            case .failure(let error):
                self.apply(book: previous, state: .failed(error.userFacingText))
            }
        }
    }

    private func merge(_ books: [Book]) {
        var updated: [BookRow] = []
        updated.reserveCapacity(books.count)
        for book in books {
            if let existing = rows.first(where: { $0.id == book.id }) {
                var row = existing
                row.book = book
                switch existing.state {
                case .saving, .saved, .queued:
                    // A card mid-save, just saved, or still holding an unsent
                    // write keeps saying so.
                    row.state = existing.state
                case .idle, .failed:
                    row.state = .idle
                }
                updated.append(row)
            } else {
                updated.append(BookRow(book: book))
            }
        }
        rows = updated
    }

    private func apply(book: Book, state: BookRow.State) {
        guard let index = rows.firstIndex(where: { $0.id == book.id }) else {
            rows.append(BookRow(book: book, state: state))
            return
        }
        rows[index].book = book
        rows[index].state = state
    }

    private func restore(_ book: Book, state: BookRow.State) {
        apply(book: book, state: state)
    }

    private func setState(_ state: BookRow.State, for bookId: Int) {
        guard let index = rows.firstIndex(where: { $0.id == bookId }) else { return }
        rows[index].state = state
    }

    private func scheduleSavedBadgeClear(for bookId: Int) {
        savedBadgeTasks[bookId]?.cancel()
        savedBadgeTasks[bookId] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled, let self else { return }
            if let index = self.rows.firstIndex(where: { $0.id == bookId }),
               case .saved = self.rows[index].state {
                self.rows[index].state = .idle
            }
        }
    }

    private func cancelSavedBadge(for bookId: Int) {
        savedBadgeTasks[bookId]?.cancel()
        savedBadgeTasks[bookId] = nil
    }

    // MARK: - Settings surface

    func coverLoader() -> CoverStore? { covers }

    func recentLog() async -> [String] { await log.recent() }

    func changeServerAddress(_ address: String) async -> Bool {
        guard let url = ServerAddress.normalize(address) else { return false }
        settings.baseURL = url
        await api?.setBaseURL(url)
        await log.write("Server address changed to \(url.absoluteString)")
        await refresh()
        return true
    }

    // MARK: -

    private func makeServices(baseURL: URL) async -> (api: APIClient, service: ProgressService) {
        if let api, let service {
            await api.setBaseURL(baseURL)
            return (api, service)
        }

        let api = APIClient(baseURL: baseURL, session: session, tokens: tokens, log: log)
        let service = ProgressService(
            api: api,
            queue: PendingWriteStore(fileURL: files.queueFile),
            cache: BooksCache(fileURL: files.booksCacheFile),
            plannedCache: BooksCache(fileURL: files.plannedCacheFile),
            log: log
        )
        self.api = api
        self.service = service
        self.covers = CoverStore(api: api)

        await api.onAuthenticationLost {
            Task { @MainActor [weak self] in
                self?.screen = .signIn(note: "The session ended. Sign in again.")
            }
        }
        return (api, service)
    }
}
