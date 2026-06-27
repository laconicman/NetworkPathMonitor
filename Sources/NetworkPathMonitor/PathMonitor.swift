import Foundation
import Network

/// The default `Network`-backed implementation of `PathMonitoring`.
///
/// It is itself an `AsyncSequence` of `NetworkPath`, so it mirrors the modern
/// `NWPathMonitor` shape — `for await path in PathMonitor() { … }` — on the
/// whole iOS 15+ range:
///
/// - **iOS 17 / macOS 14 / tvOS 17 / watchOS 10+**: delegates to `NWPathMonitor`'s
///   own `AsyncSequence` conformance (verified gate: the `NWPathMonitor.Iterator`
///   subpage, https://developer.apple.com/documentation/network/nwpathmonitor/iterator).
/// - **iOS 15–16**: that conformance does not exist, so this hand-rolls the same
///   shape by bridging `pathUpdateHandler` into an `AsyncStream`.
///
/// A fresh `NWPathMonitor` is created per iteration and cancelled on termination,
/// avoiding two framework footguns: a cancelled monitor can't be restarted, and a
/// single monitor's handler feeds only one consumer (Apple DTS, forums/124486).
public struct PathMonitor: PathMonitoring, Sendable {

    private let requiredInterfaceType: NWInterface.InterfaceType?

    /// - Parameter requiredInterfaceType: pass a type (e.g. `.wifi`) to observe
    ///   only that medium. Leave `nil` for plain "am I online?" — a monitor
    ///   *required* to use `.cellular` while on Wi-Fi reports `.unsatisfied`,
    ///   which is rarely what you want for connectivity.
    public init(requiredInterfaceType: NWInterface.InterfaceType? = nil) {
        self.requiredInterfaceType = requiredInterfaceType
    }

    /// The `NetworkPath` stream (protocol requirement).
    public func paths() -> AsyncStream<NetworkPath> {
        makeStream { NetworkPath($0) }
    }

    /// The raw `NWPath` stream, for callers needing fields the mirror omits
    /// (`gateways`, `supportsDNS`, `unsatisfiedReason`, `isUltraConstrained`, …).
    public func nwPaths() -> AsyncStream<NWPath> {
        makeStream { $0 }
    }

    // MARK: - Single source of truth for iteration

    /// Builds an `AsyncStream` of `T`, mapping each observed `NWPath` with
    /// `transform`. `paths()` and `nwPaths()` are thin specializations (DRY).
    private func makeStream<T: Sendable>(
        _ transform: @escaping @Sendable (NWPath) -> T
    ) -> AsyncStream<T> {
        let requiredInterfaceType = self.requiredInterfaceType
        return AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let monitor = Self.makeMonitor(requiredInterfaceType: requiredInterfaceType)

            if #available(iOS 17, macOS 14, tvOS 17, watchOS 10, visionOS 1, *) {
                // Use NWPathMonitor's native AsyncSequence conformance. The Task
                // owns the monitor for the stream's lifetime; cancelling the task
                // (on stream termination) tears the monitor down.
                let task = Task {
                    for await path in monitor {
                        continuation.yield(transform(path))
                    }
                    continuation.finish()
                }
                continuation.onTermination = { _ in task.cancel() }
            } else {
                // iOS 15–16: hand-roll the modern API over the callback handler.
                // The handler closure captures only the (Sendable) continuation,
                // so there is no monitor retain cycle; `onTermination` keeps the
                // monitor alive while streaming, then cancels it.
                monitor.pathUpdateHandler = { continuation.yield(transform($0)) }
                continuation.onTermination = { _ in monitor.cancel() }
                monitor.start(queue: DispatchQueue(label: "PathMonitor"))
            }
        }
    }

    private static func makeMonitor(
        requiredInterfaceType: NWInterface.InterfaceType?
    ) -> NWPathMonitor {
        if let requiredInterfaceType {
            NWPathMonitor(requiredInterfaceType: requiredInterfaceType)
        } else {
            NWPathMonitor()
        }
    }
}

// MARK: - AsyncSequence

extension PathMonitor: AsyncSequence {
    public typealias Element = NetworkPath

    public func makeAsyncIterator() -> AsyncStream<NetworkPath>.Iterator {
        paths().makeAsyncIterator()
    }
}
