# NetworkPathMonitor

[![Swift Compatibility](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Flaconicman%2FNetworkPathMonitor%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/laconicman/NetworkPathMonitor)
[![Platform Compatibility](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Flaconicman%2FNetworkPathMonitor%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/laconicman/NetworkPathMonitor)

A tiny, dependency-free network-path observer for Apple platforms, built on `Network` (`NWPathMonitor`) with Swift Concurrency. It exists to feed connectivity-aware decisions — e.g. surfacing the *right* error when a request fails offline, driving a "waiting for network" UI, or pacing a retry policy.

- **Baseline:** iOS 15+, macOS 12+, tvOS 15+, watchOS 8+, visionOS 1+ · Swift 6 language mode.
- **API close to `Network`:** re-exports Network; reuses `NWPath.Status` and `NWInterface.InterfaceType`; the monitor is an `AsyncSequence` you iterate like `NWPathMonitor` itself.
- **Injectable + testable:** depend on the `PathMonitoring` protocol; swap `StubPathMonitor` in tests.

## Installation

### Swift Package Manager

Add the package to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/laconicman/NetworkPathMonitor.git", from: "1.0.0")
]
```

Then depend on `NetworkPathMonitor` in your target, and on `NetworkPathMonitorTestSupport` in your test target:

```swift
targets: [
    .target(
        name: "YourTarget",
        dependencies: [
            .product(name: "NetworkPathMonitor", package: "NetworkPathMonitor")
        ]
    ),
    .testTarget(
        name: "YourTargetTests",
        dependencies: [
            .product(name: "NetworkPathMonitor", package: "NetworkPathMonitor"),
            .product(name: "NetworkPathMonitorTestSupport", package: "NetworkPathMonitor")
        ]
    )
]
```

## Usage

```swift
import NetworkPathMonitor   // re-exports Network, so NWPath.Status etc. are in scope

let monitor = PathMonitor()

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

Need fields the mirror omits (`gateways`, `supportsDNS`, `unsatisfiedReason`, `isUltraConstrained`)? Use `monitor.nwPaths()` for the raw `NWPath` stream.

## Design

The load-bearing rationale — the `NetworkPath` mirror (why not vend `NWPath`), the iOS 15–16 `AsyncSequence` bridge, `.bufferingNewest(1)`, the injection seam, the `.satisfied` ≠ reachable caveat, and the middleware integration — lives in the DocC article [`Design`](Sources/NetworkPathMonitor/NetworkPathMonitor.docc/Design.md), which also renders on Swift Package Index. Milestones are in [`ROADMAP.md`](ROADMAP.md).

## Testing a consumer

```swift
import NetworkPathMonitorTestSupport

// Drive a consumer through offline → online without a real network:
let monitor = StubPathMonitor([.unsatisfied, .satisfied()])
await sut.handlePersistentRejection(monitor: monitor)
```

## Integrating with `RefreshTokenAuthMiddleware`

[`RefreshTokenAuthMiddleware`](https://github.com/laconicman/RefreshTokenAuthMiddleware) runs on a `URLSession`-backed transport. Per Apple's guidance, **don't gate the request on a connectivity pre-check** — reading "am I online?" and *then* calling is a race, and it duplicates what the OS does better. Make the *request* wait by configuring the transport's `URLSession`:

```swift
let config = URLSessionConfiguration.default
config.waitsForConnectivity = true             // wait for connectivity instead of failing fast
config.allowsConstrainedNetworkAccess = false  // e.g. don't refresh over Low Data Mode
// Build your OpenAPI URLSessionTransport from URLSession(configuration: config).
```

Use `NetworkPathMonitor` to *react to* connectivity (the middleware, as of 2.0.0, has no connectivity hook) — reaction is what path monitoring is for:

- **Surface the right error.** Have the `credentialsProvider` closure throw a *network* error when `await monitor.currentPath()?.isSatisfied != true`, so an outage surfaces as `AuthError.credentialsUnavailable` rather than a misattributed auth failure.
- **Drive UX / pace retries.** Show a "waiting for network" state, or hold a retry runner such as [swift-concurrency-retry](https://github.com/laconicman/swift-concurrency-retry) until `await monitor.waitUntilSatisfied()` returns.

See [`Design` §7](Sources/NetworkPathMonitor/NetworkPathMonitor.docc/Design.md) for the full wiring. This package only answers "what is the network doing right now / wake me when it's back."

## Roadmap

Milestones and the iOS 26 `NetworkConnection`-family rationale live in [`ROADMAP.md`](ROADMAP.md) and [`Design` §8](Sources/NetworkPathMonitor/NetworkPathMonitor.docc/Design.md).

## License

Apache-2.0 — see [`LICENSE.txt`](LICENSE.txt).
