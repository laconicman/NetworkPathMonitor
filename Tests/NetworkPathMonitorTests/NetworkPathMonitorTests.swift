import Testing
import Network
@testable import NetworkPathMonitor
import NetworkPathMonitorTestSupport

@Suite("NetworkPathMonitor")
struct NetworkPathMonitorTests {

    @Test("currentPath returns the first scripted path")
    func currentPathReturnsFirst() async {
        let monitor = StubPathMonitor(.satisfied(isExpensive: true))
        let path = await monitor.currentPath()
        #expect(path?.isSatisfied == true)
        #expect(path?.isExpensive == true)
        #expect(path?.primaryInterface == .wifi)
    }

    @Test("waitUntilSatisfied returns once a satisfied path arrives")
    func waitUntilSatisfiedResolves() async {
        // Offline first, then online. If `waitUntilSatisfied` were broken it would
        // hang and the test would time out rather than complete.
        let monitor = StubPathMonitor([.unsatisfied, .satisfied()])
        await monitor.waitUntilSatisfied()
    }

    @Test("paths() preserves the scripted order")
    func pathsPreserveOrder() async {
        let scripted: [NetworkPath] = [.unsatisfied, .satisfied(isConstrained: true)]
        let monitor = StubPathMonitor(scripted)

        var received: [NetworkPath] = []
        for await path in monitor.paths() { received.append(path) }

        #expect(received == scripted)
        #expect(received.last?.isConstrained == true)
    }

    @Test("NetworkPath maps NWPath.Status faithfully")
    func mirrorReusesNetworkEnums() {
        let path = NetworkPath.satisfied(interfaces: [.cellular])
        #expect(path.status == .satisfied)            // reuses NWPath.Status
        #expect(path.primaryInterface == .cellular)   // reuses NWInterface.InterfaceType
    }

    @Test("VPN-shaped path: primaryInterface masks as .other, usesInterfaceType sees the medium")
    func vpnShapedPath() {
        // Full-tunnel VPN: the preferred interface is the tunnel (typed .other),
        // while the physical medium may still carry the traffic underneath.
        let path = NetworkPath(
            status: .satisfied,
            availableInterfaces: [.other, .cellular],
            usedInterfaceTypes: [.other, .cellular]
        )
        #expect(path.primaryInterface == .other)
        #expect(path.usesInterfaceType(.cellular))
        #expect(!path.usesInterfaceType(.wifi))
    }

    @Test("usedInterfaceTypes defaults to the available interfaces")
    func usedInterfaceTypesDefault() {
        let path = NetworkPath.satisfied(interfaces: [.wifi])
        #expect(path.usedInterfaceTypes == [.wifi])
        #expect(path.usesInterfaceType(.wifi))
    }

    @Test("unsatisfiedReason mirrors NWPath.UnsatisfiedReason")
    func unsatisfiedReasonMirrors() {
        #expect(NetworkPath.unsatisfied.unsatisfiedReason == .notAvailable)
        let vpnDown = NetworkPath(status: .unsatisfied, unsatisfiedReason: .vpnInactive)
        #expect(vpnDown.isSatisfied == false)
        #expect(vpnDown.unsatisfiedReason == .vpnInactive)
    }
}
