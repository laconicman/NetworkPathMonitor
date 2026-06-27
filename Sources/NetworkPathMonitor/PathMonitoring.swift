import Network

/// The interface a consumer (e.g. `RefreshTokenAuthMiddleware`) depends on to
/// observe network state. Depend on this protocol — not the concrete monitor —
/// so you can inject `StubPathMonitor` in tests.
///
/// The shape mirrors iterating `NWPathMonitor` directly: a stream of paths,
/// beginning with the current one. The element is `NetworkPath` (a `Sendable`
/// mirror) rather than `NWPath` purely so it can be constructed in stubs — see
/// `NetworkPath` for the rationale.
public protocol PathMonitoring: Sendable {

    /// An async sequence of network paths. The first element is the current path;
    /// each subsequent element is a change. Buffering keeps only the newest value
    /// (connectivity is state, not a log), so a slow consumer never sees a backlog.
    /// Each call returns an independent, single-consumer stream — give each
    /// consumer (and each `for await`) its own rather than sharing one.
    func paths() -> AsyncStream<NetworkPath>
}

public extension PathMonitoring {

    /// The most recent path, awaiting the first update if none has arrived yet.
    /// Returns `nil` only if the stream finishes before producing a value.
    func currentPath() async -> NetworkPath? {
        for await path in paths() { return path }
        return nil
    }

    /// Suspends until a usable (`.satisfied`) path is available, then returns.
    ///
    /// Use it to *react* to connectivity — drive a "waiting for network" UI, or
    /// pace a retry loop between attempts — rather than to gate a request; make the
    /// request itself wait via `URLSession`'s `waitsForConnectivity`. (Returns
    /// immediately if already satisfied; returns when the stream ends if it never
    /// satisfies, which a real monitor won't do but a finite stub will.)
    func waitUntilSatisfied() async {
        for await path in paths() where path.isSatisfied { return }
    }
}
