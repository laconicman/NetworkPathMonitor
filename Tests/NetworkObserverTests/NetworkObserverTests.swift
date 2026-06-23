import Testing
import Network
@testable import NetworkObserver
import NetworkObserverTestSupport

@Suite("NetworkObserver")
struct NetworkObserverTests {

    @Test("currentPath returns the first scripted path")
    func currentPathReturnsFirst() async {
        let monitor = StubNetworkPathMonitor(.satisfied(isExpensive: true))
        let path = await monitor.currentPath()
        #expect(path?.isSatisfied == true)
        #expect(path?.isExpensive == true)
        #expect(path?.primaryInterface == .wifi)
    }

    @Test("waitUntilSatisfied returns once a satisfied path arrives")
    func waitUntilSatisfiedResolves() async {
        // Offline first, then online. If `waitUntilSatisfied` were broken it would
        // hang and the test would time out rather than complete.
        let monitor = StubNetworkPathMonitor([.unsatisfied, .satisfied()])
        await monitor.waitUntilSatisfied()
    }

    @Test("paths() preserves the scripted order")
    func pathsPreserveOrder() async {
        let scripted: [NetworkPath] = [.unsatisfied, .satisfied(isConstrained: true)]
        let monitor = StubNetworkPathMonitor(scripted)

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
}
