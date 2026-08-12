import UIKit
import BookWormKit

/// Cover thumbnails, by hash.
///
/// The HTTP caching is URLSession's — a hash always denotes the same bytes and
/// the server says so in the headers. This adds only the decoded-image cache,
/// because decoding the same WebP on every scroll is the part URLSession does
/// not do for you. In-flight requests are shared so two books with the same
/// cover (they deduplicate server-side) fetch it once.
actor CoverStore {
    private let api: APIClient
    private var images: [String: UIImage] = [:]
    private var inFlight: [String: Task<UIImage?, Never>] = [:]

    init(api: APIClient) {
        self.api = api
    }

    func thumbnail(hash: String) async -> UIImage? {
        if let cached = images[hash] { return cached }
        if let existing = inFlight[hash] { return await existing.value }

        let task = Task<UIImage?, Never> { [api] in
            guard let data = try? await api.coverData(hash: hash, thumbnail: true) else { return nil }
            return UIImage(data: data)
        }
        inFlight[hash] = task
        let image = await task.value
        inFlight[hash] = nil
        if let image { images[hash] = image }
        return image
    }
}
