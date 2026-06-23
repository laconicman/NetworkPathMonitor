// Re-export Network so callers `import NetworkObserver` and get `NWPath.Status`,
// `NWInterface.InterfaceType`, etc. directly — keeping the API "close to Network".
// (`@_exported` is an underscored attribute, but it's stable and widely used by
// packages that wrap a system framework.)
@_exported import Network

/// A `Sendable`, value-type snapshot of the decision-relevant fields of `NWPath`.
///
/// Why a mirror instead of vending `NWPath` directly: **`NWPath` has no public
/// initializer**, so it cannot be constructed in unit tests. Exposing this mirror
/// is what lets the middleware inject a `StubNetworkPathMonitor` and script
/// connectivity. The fields deliberately reuse Network's own
/// `NWPath.Status` and `NWInterface.InterfaceType`, so the vocabulary stays
/// identical to the framework. When you need fields beyond this subset
/// (`gateways`, `supportsDNS`, `unsatisfiedReason`, …), reach for the raw
/// `NWPath` stream on `NetworkPathMonitor.nwPaths()`.
public struct NetworkPath: Sendable, Equatable {

    /// Mirrors `NWPath.status` — `.satisfied`, `.unsatisfied`, `.requiresConnection`.
    public var status: NWPath.Status

    /// Mirrors `NWPath.isExpensive` — cellular or a personal hotspot.
    public var isExpensive: Bool

    /// Mirrors `NWPath.isConstrained` — user enabled Low Data Mode.
    public var isConstrained: Bool

    /// Interface types backing this path, in preference order
    /// (mirrors `NWPath.availableInterfaces.map(\.type)`).
    public var availableInterfaces: [NWInterface.InterfaceType]

    public init(
        status: NWPath.Status,
        isExpensive: Bool = false,
        isConstrained: Bool = false,
        availableInterfaces: [NWInterface.InterfaceType] = []
    ) {
        self.status = status
        self.isExpensive = isExpensive
        self.isConstrained = isConstrained
        self.availableInterfaces = availableInterfaces
    }
}

public extension NetworkPath {

    /// Maps a live `NWPath` into the mirror.
    init(_ path: NWPath) {
        self.init(
            status: path.status,
            isExpensive: path.isExpensive,
            isConstrained: path.isConstrained,
            availableInterfaces: path.availableInterfaces.map(\.type)
        )
    }

    /// A usable path exists. NOTE: `.satisfied` does NOT prove the internet is
    /// reachable — a captive portal can satisfy a path. For true reachability,
    /// make a real request and handle failure (Ross Butler, "Detecting Internet
    /// Access on iOS 12+"; see the apple-network skill's libraries reference for
    /// rwbutler/Connectivity if you need captive-portal detection systematically).
    var isSatisfied: Bool { status == .satisfied }

    /// The primary in-use interface type, if any (mirrors taking the first of
    /// `NWPath.availableInterfaces`).
    var primaryInterface: NWInterface.InterfaceType? { availableInterfaces.first }
}

// MARK: - Convenience constructors (handy for previews and tests)

public extension NetworkPath {

    /// A satisfied path. Defaults to Wi-Fi, not expensive, not constrained.
    static func satisfied(
        isExpensive: Bool = false,
        isConstrained: Bool = false,
        interfaces: [NWInterface.InterfaceType] = [.wifi]
    ) -> NetworkPath {
        NetworkPath(
            status: .satisfied,
            isExpensive: isExpensive,
            isConstrained: isConstrained,
            availableInterfaces: interfaces
        )
    }

    /// An unsatisfied (offline) path.
    static let unsatisfied = NetworkPath(status: .unsatisfied)
}
