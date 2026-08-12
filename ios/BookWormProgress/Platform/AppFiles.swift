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
    var logFile: URL { directory.appendingPathComponent("activity.log") }

    var coverCacheDirectory: URL {
        let url = directory.appendingPathComponent("covers", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

/// The server address, and nothing else. Tokens go in the Keychain.
struct SettingsStore {
    private let defaults = UserDefaults.standard
    private let key = "serverBaseURL"

    var baseURL: URL? {
        get {
            guard let text = defaults.string(forKey: key) else { return nil }
            return URL(string: text)
        }
        nonmutating set {
            guard let newValue else {
                defaults.removeObject(forKey: key)
                return
            }
            defaults.set(newValue.absoluteString, forKey: key)
        }
    }
}
