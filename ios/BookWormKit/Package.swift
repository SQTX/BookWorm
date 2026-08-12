// swift-tools-version: 6.0
import PackageDescription

// The pure logic of the app — models, HTTP, the offline write queue, the log.
// It lives in a package rather than in the app target for one practical reason:
// `swift test` runs it on the Mac in a couple of seconds, with no simulator
// runtime installed and no code signing. Anything that needs UIKit, SwiftUI or
// the Keychain stays in the app target and reaches in through a protocol.
let package = Package(
    name: "BookWormKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "BookWormKit", targets: ["BookWormKit"])
    ],
    targets: [
        .target(name: "BookWormKit"),
        .testTarget(name: "BookWormKitTests", dependencies: ["BookWormKit"])
    ]
)
