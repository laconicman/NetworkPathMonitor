// Re-export Network so callers `import NetworkPathMonitor` and get `NWPath.Status`,
// `NWInterface.InterfaceType`, etc. directly — keeping the API "close to Network".
// (`@_exported` is an underscored attribute, but it's stable and widely used by
// packages that wrap a system framework.)
@_exported import Network

/// A `Sendable`, value-type snapshot of the decision-relevant fields of `NWPath`.
///
/// Why a mirror instead of vending `NWPath` directly: **`NWPath` has no public
/// initializer**, so it cannot be constructed in unit tests. Exposing this mirror
/// is what lets the middleware inject a `StubPathMonitor` and script
/// connectivity. The fields deliberately reuse Network's own
/// `NWPath.Status`, `NWPath.UnsatisfiedReason`, and `NWInterface.InterfaceType`,
/// so the vocabulary stays identical to the framework. When you need fields
/// beyond this subset (`gateways`, `supportsDNS`, `isUltraConstrained`, …),
/// reach for the raw `NWPath` stream on `PathMonitor.nwPaths()`.
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

    /// Mirrors `NWPath.unsatisfiedReason` — why the path is unsatisfied
    /// (`.cellularDenied`, `.wifiDenied`, `.localNetworkDenied`, `.vpnInactive`);
    /// `.notAvailable` when no reason applies.
    public var unsatisfiedReason: NWPath.UnsatisfiedReason

    /// Interface types the path may send traffic over, captured from
    /// `NWPath.usesInterfaceType(_:)`. Distinct from ``availableInterfaces``
    /// under a VPN: the tunnel itself is a virtual interface typed `.other`,
    /// while the underlying physical medium (`.wifi` / `.cellular`) may still
    /// appear here — depending on the VPN configuration.
    public var usedInterfaceTypes: Set<NWInterface.InterfaceType>

    /// When `usedInterfaceTypes` is `nil` it is derived from
    /// `availableInterfaces` — the right default everywhere except VPN-shaped
    /// test fixtures, where the two deliberately differ.
    public init(
        status: NWPath.Status,
        unsatisfiedReason: NWPath.UnsatisfiedReason = .notAvailable,
        isExpensive: Bool = false,
        isConstrained: Bool = false,
        availableInterfaces: [NWInterface.InterfaceType] = [],
        usedInterfaceTypes: Set<NWInterface.InterfaceType>? = nil
    ) {
        self.status = status
        self.unsatisfiedReason = unsatisfiedReason
        self.isExpensive = isExpensive
        self.isConstrained = isConstrained
        self.availableInterfaces = availableInterfaces
        self.usedInterfaceTypes = usedInterfaceTypes ?? Set(availableInterfaces)
    }

    /// The interface types `init(_:)` probes with `NWPath.usesInterfaceType(_:)`.
    /// A fixed list on purpose — no `CaseIterable` retrofit on a frozen C enum.
    private static let knownInterfaceTypes: [NWInterface.InterfaceType] =
        [.wifi, .cellular, .wiredEthernet, .loopback, .other]
}

public extension NetworkPath {

    /// Maps a live `NWPath` into the mirror.
    init(_ path: NWPath) {
        self.init(
            status: path.status,
            unsatisfiedReason: path.unsatisfiedReason,
            isExpensive: path.isExpensive,
            isConstrained: path.isConstrained,
            availableInterfaces: path.availableInterfaces.map(\.type),
            usedInterfaceTypes: Set(Self.knownInterfaceTypes.filter { path.usesInterfaceType($0) })
        )
    }

    /// A usable path exists. NOTE: `.satisfied` does NOT prove the internet is
    /// reachable — a captive portal can satisfy a path. For true reachability,
    /// make a real request and handle failure (Ross Butler, "Detecting Internet
    /// Access on iOS 12+"); for systematic captive-portal detection, a dedicated
    /// library such as rwbutler/Connectivity is the right tool. Also `false`
    /// for `.requiresConnection` (e.g. an idle on-demand VPN, which connects
    /// only when something attempts traffic).
    var isSatisfied: Bool { status == .satisfied }

    /// The primary in-use interface type, if any (mirrors taking the first of
    /// `NWPath.availableInterfaces`).
    ///
    /// > Important: Under a system VPN the preferred interface is usually the
    /// > tunnel, and Network types tunnels as `.other` — so this reports
    /// > `.other`, not the physical medium. To ask "is Wi-Fi / cellular in
    /// > play?", use ``usesInterfaceType(_:)`` instead (see Design §6).
    var primaryInterface: NWInterface.InterfaceType? { availableInterfaces.first }

    /// Whether the path may send traffic over `type` (mirrors
    /// `NWPath.usesInterfaceType(_:)` via ``usedInterfaceTypes``). Under a VPN,
    /// prefer this over ``primaryInterface`` to detect the underlying medium.
    func usesInterfaceType(_ type: NWInterface.InterfaceType) -> Bool {
        usedInterfaceTypes.contains(type)
    }
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
