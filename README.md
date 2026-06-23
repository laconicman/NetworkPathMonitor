# swift-network-observer

[![Swift Compatibility](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Flaconicman%2Fswift-network-observer%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/laconicman/swift-network-observer)
[![Platform Compatibility](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Flaconicman%2Fswift-network-observer%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/laconicman/swift-network-observer)

A tiny, dependency-free network-state observer for Apple platforms, built on `Network` (`NWPathMonitor`) with Swift Concurrency. It exists to feed connectivity-aware decisions — e.g. letting an auth middleware's "persistently rejected" handler pause until the network returns, surface the *right* error, or hand off to a retry policy.

- **Baseline:** iOS 15+, macOS 12+, tvOS 15+, watchOS 8+, visionOS 1+ · Swift 6 language mode.
- **API close to `Network`:** re-exports Network; reuses `NWPath.Status` and `NWInterface.InterfaceType`; the monitor is an `AsyncSequence` you iterate like `NWPathMonitor` itself.
- **Injectable + testable:** depend on the `NetworkPathMonitoring` protocol; swap `StubNetworkPathMonitor` in tests.

## Installation

### Swift Package Manager

Add the package to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/laconicman/swift-network-observer.git", from: "1.0.0")
]
```

Then depend on `NetworkObserver` in your target, and on `NetworkObserverTestSupport` in your test target:

```swift
targets: [
    .target(
        name: "YourTarget",
        dependencies: [
            .product(name: "NetworkObserver", package: "swift-network-observer")
        ]
    ),
    .testTarget(
        name: "YourTargetTests",
        dependencies: [
            .product(name: "NetworkObserver", package: "swift-network-observer"),
            .product(name: "NetworkObserverTestSupport", package: "swift-network-observer")
        ]
    )
]
```

## Usage

```swift
import NetworkObserver   // re-exports Network, so NWPath.Status etc. are in scope

let monitor = NetworkPathMonitor()

// Iterate like NWPathMonitor (works on iOS 15+; native AsyncSequence on iOS 17+):
for await path in monitor {
    if path.isSatisfied {
        // online — note: a captive portal can still report satisfied
    }
    if path.isExpensive { /* defer big downloads */ }
}

// Or the convenience primitives:
let online = await monitor.currentPath()?.isSatisfied ?? false
await monitor.waitUntilSatisfied()   // suspend until connectivity returns
```

Need fields the mirror omits (`gateways`, `supportsDNS`, `unsatisfiedReason`)? Use `monitor.nwPaths()` for the raw `NWPath` stream.

## Design

The load-bearing rationale — the `NetworkPath` mirror (why not vend `NWPath`), the iOS 15–16 `AsyncSequence` bridge, `.bufferingNewest(1)`, the injection seam, the `.satisfied` ≠ reachable caveat, and the middleware integration — lives in the DocC article [`Design`](Sources/NetworkObserver/NetworkObserver.docc/Design.md), which also renders on Swift Package Index. Milestones are in [`ROADMAP.md`](ROADMAP.md).

## Testing a consumer

```swift
import NetworkObserverTestSupport

// Drive a consumer through offline → online without a real network:
let monitor = StubNetworkPathMonitor([.unsatisfied, .satisfied()])
await sut.handlePersistentRejection(monitor: monitor)
```

## Integrating with `RefreshTokenAuthMiddleware`

[`RefreshTokenAuthMiddleware`](https://github.com/laconicman/RefreshTokenAuthMiddleware) runs on a `URLSession`-backed transport, so it opens no raw connections — it just needs path state. As of its 2.0.0 it has **no** connectivity hook, so wire one in at an adopter seam: gate the network-bound operations of your `SignInAndRefresh` conformance on a usable path (below), or gate its `credentialsProvider` closure. Surface a *network* error when offline so the middleware doesn't misread it as an auth failure — or pause until the network returns:

```swift
import NetworkObserver
import RefreshTokenAuthMiddleware

extension Client: SignInAndRefresh {
    // `monitor` is a NetworkPathMonitoring you injected at construction.
    func refreshTokenIfNeeded(with refreshToken: RefreshToken?)
        async throws -> (accessToken: Token, refreshToken: RefreshToken?) {
        await monitor.waitUntilSatisfied()        // pause while offline; resume when back
        guard let refreshToken else { throw AuthError.missingRefreshToken }
        // … your generated auth-refresh operation …
    }
}
```

The `credentialsProvider` path (consulted under `onRefreshFailure: .requestCredentials` / `onPersistentlyRejected: .signInOnSecond401`) and pairing with a retry runner such as [swift-concurrency-retry](https://github.com/laconicman/swift-concurrency-retry) are covered in [`Design` §7](Sources/NetworkObserver/NetworkObserver.docc/Design.md). This package only answers "what is the network doing right now / wake me when it's back."

## Roadmap

Milestones and the iOS 26 `NetworkConnection`-family rationale live in [`ROADMAP.md`](ROADMAP.md) and [`Design` §8](Sources/NetworkObserver/NetworkObserver.docc/Design.md).

## License

Apache-2.0 — see [`LICENSE.txt`](LICENSE.txt).
