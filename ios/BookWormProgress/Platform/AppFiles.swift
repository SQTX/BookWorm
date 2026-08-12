import Foundation

/// Where the queue, the cache and the log live. Application Support, not
/// Documents: none of it is a user-visible file.
struct AppFiles {
    let directory: URL

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        directory = base.appendingPathComponent("BookWormProgress", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    var queueFile: URL { directory.appendingPathComponent("pending-writes.json") }
    var booksCacheFile: URL { directory.appendingPathComponent("reading.json") }
    var plannedCacheFile: URL { directory.appendingPathComponent("planned.json") }
    var logFile: URL { directory.appendingPathComponent("activity.log") }

    var coverCacheDirectory: URL {
        let url = directory.appendingPathComponent("covers", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

/// The server address and the email — the two things that are not secrets.
/// Tokens and the password go in the Keychain, never here: this is a plist.
struct SettingsStore {
    private let defaults = UserDefaults.standard
    private let urlKey = "serverBaseURL"
    private let emailKey = "accountEmail"

    var baseURL: URL? {
        get {
            guard let text = defaults.string(forKey: urlKey) else { return nil }
            return URL(string: text)
        }
        nonmutating set {
            guard let newValue else {
                defaults.removeObject(forKey: urlKey)
                return
            }
            defaults.set(newValue.absoluteString, forKey: urlKey)
        }
    }

    /// Remembered so that a sign-in after a re-deploy is one field, not three.
    var email: String? {
        get { defaults.string(forKey: emailKey) }
        nonmutating set {
            guard let newValue, !newValue.isEmpty else {
                defaults.removeObject(forKey: emailKey)
                return
            }
            defaults.set(newValue, forKey: emailKey)
        }
    }
}
