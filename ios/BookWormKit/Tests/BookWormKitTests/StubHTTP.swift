import Foundation
@testable import BookWormKit

/// A scripted server. Each entry answers one request, in order, so a test can
/// say "401, then the refresh, then the retry" and assert on exactly what was
/// sent.
final class StubHTTP: HTTPPerforming, @unchecked Sendable {
    struct Exchange {
        var status: Int
        var body: Data
        var error: Error?

        static func json(_ status: Int, _ object: Any) -> Exchange {
            Exchange(status: status, body: try! JSONSerialization.data(withJSONObject: object), error: nil)
        }

        static func failure(_ error: Error) -> Exchange {
            Exchange(status: 0, body: Data(), error: error)
        }
    }

    private let lock = NSLock()
    private var scripted: [Exchange]
    private(set) var requests: [URLRequest] = []

    init(_ scripted: [Exchange]) {
        self.scripted = scripted
    }

    var requestCount: Int {
        lock.lock(); defer { lock.unlock() }
        return requests.count
    }

    func request(_ index: Int) -> URLRequest {
        lock.lock(); defer { lock.unlock() }
        return requests[index]
    }

    func body(_ index: Int) -> [String: Any] {
        let data = request(index).httpBody ?? Data()
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
    }

    func perform(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let next = lock.withLock { () -> Exchange? in
            requests.append(request)
            return scripted.isEmpty ? nil : scripted.removeFirst()
        }

        guard let next else {
            throw APIError.decoding("stub ran out of scripted responses")
        }
        if let error = next.error { throw error }
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: next.status,
            httpVersion: "HTTP/1.1",
            headerFields: nil
        )!
        return (next.body, response)
    }
}

extension Book {
    static func fixture(
        id: Int = 42,
        title: String = "Ubik",
        author: String = "Philip K. Dick",
        pageCount: Int? = 224,
        currentPage: Int? = 180,
        coverHash: String? = nil,
        audioMode: String? = "none"
    ) -> Book {
        Book(
            id: id,
            title: title,
            author: author,
            pageCount: pageCount,
            currentPage: currentPage,
            coverHash: coverHash,
            audioMode: audioMode
        )
    }

    var asJSON: [String: Any] {
        var json: [String: Any] = [
            "id": id,
            "title": title,
            "author": author,
            "status": "reading",
            "readCount": 0,
            "itemType": "book",
            "isNonFiction": false,
            "isPriority": false,
            "tags": [],
            "updatedAt": "2026-08-12T00:21:32.000Z",
            "coverImagePath": "/Users/somebody/Pictures/whatever.jpg"
        ]
        json["pageCount"] = pageCount ?? NSNull()
        json["currentPage"] = currentPage ?? NSNull()
        json["coverHash"] = coverHash ?? NSNull()
        json["audioMode"] = audioMode ?? NSNull()
        return json
    }
}

func temporaryFileURL(_ name: String) -> URL {
    makeTemporaryDirectory().appendingPathComponent(name)
}

func makeTemporaryDirectory() -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("bookworm-tests-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
