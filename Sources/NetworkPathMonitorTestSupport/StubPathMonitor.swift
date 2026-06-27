import NetworkPathMonitor

/// A scriptable `PathMonitoring` for unit tests and previews — inject this
/// in place of `PathMonitor` to drive a consumer (e.g. the middleware's
/// `OnPersistentlyRejected`) through a fixed sequence of network states without a
/// real network.
///
/// ```swift
/// let monitor = StubPathMonitor([.unsatisfied, .satisfied()])
/// await sut.handlePersistentRejection(monitor: monitor)   // observes both states
/// ```
public struct StubPathMonitor: PathMonitoring {

    private let scripted: [NetworkPath]

    /// Emits each scripted path in order, then finishes.
    public init(_ scripted: [NetworkPath]) {
        self.scripted = scripted
    }

    /// Convenience for a single, steady state.
    public init(_ single: NetworkPath) {
        self.init([single])
    }

    public func paths() -> AsyncStream<NetworkPath> {
        let scripted = self.scripted
        return AsyncStream { continuation in
            for path in scripted { continuation.yield(path) }
            continuation.finish()
        }
    }
}
