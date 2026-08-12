// swift-tools-version:5.10
import PackageDescription

// DeckKit is the shared, platform-free core of NosoDeck (PRD §5): models, protocol
// messages and framing, and the pairing/session state machines. It must stay free of
// Apple-only frameworks so it builds and tests on Linux (D12).
let package = Package(
    name: "DeckKit",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "DeckKit", targets: ["DeckKit"])
    ],
    targets: [
        .target(name: "DeckKit"),
        .testTarget(name: "DeckKitTests", dependencies: ["DeckKit"])
    ]
)
