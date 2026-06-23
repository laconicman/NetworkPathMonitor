// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NetworkPathMonitor",
    platforms: [
        // iOS 15-generation baseline across all Apple platforms.
        // Note the one gotcha that shapes the implementation: NWPathMonitor's
        // native AsyncSequence (`for await path in NWPathMonitor()`) is iOS 17+,
        // so iOS 15–16 are served by a hand-rolled bridge (see NetworkPathMonitor).
        .iOS(.v15),
        .macOS(.v12),
        .tvOS(.v15),
        .watchOS(.v8),
        .visionOS(.v1),
    ],
    products: [
        // The interface + default Network-backed implementation.
        .library(name: "NetworkObserver", targets: ["NetworkObserver"]),
        // Stubs for unit-testing consumers (e.g. the middleware) without a real
        // network. Kept in a separate product so production code never ships it.
        .library(name: "NetworkObserverTestSupport", targets: ["NetworkObserverTestSupport"]),
    ],
    targets: [
        .target(name: "NetworkObserver"),
        .target(
            name: "NetworkObserverTestSupport",
            dependencies: ["NetworkObserver"]
        ),
        .testTarget(
            name: "NetworkObserverTests",
            dependencies: ["NetworkObserver", "NetworkObserverTestSupport"]
        ),
    ],
    // Build in Swift 6 language mode: the whole package is strict-concurrency clean.
    swiftLanguageModes: [.v6]
)
