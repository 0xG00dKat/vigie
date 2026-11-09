import Darwin
import Foundation
import XCTest
@testable import VigieCore

final class PortsTests: FrenchTestCase {
    func testLoopbackAndExposedAddresses() {
        XCTAssertTrue(ListeningSocket(port: 3000, address: "127.0.0.1").isLoopback)
        XCTAssertTrue(ListeningSocket(port: 3000, address: "::1").isLoopback)
        XCTAssertTrue(ListeningSocket(port: 3000, address: "0.0.0.0").isExposed)
        XCTAssertTrue(ListeningSocket(port: 3000, address: "::").isExposed)
        XCTAssertTrue(ListeningSocket(port: 3000, address: "192.168.1.20").isExposed)
    }

    func testPortsAreAttachedToGroupsAndContainers() {
        let server = RawProcess(pid: 10, ppid: 1, uid: 501, name: "node", path: "/opt/homebrew/bin/node")
        let docker = RawProcess(pid: 20, ppid: 1, uid: 501, name: "com.docker.backend", path: "/Applications/Docker.app/x")
        let groups = [
            ProcessGroup(id: "dev:shop", category: .dev, title: "shop", location: "~/code/shop", explanation: Explanation(""),
                         processes: [server], close: .signal([10]), isProtected: false),
            ProcessGroup(id: "app:docker", category: .apps, title: "Docker", explanation: Explanation(""),
                         processes: [docker], close: .quitApps([20]), isProtected: false),
        ]
        let containers = [DockerContainer(id: "c1", name: "db-1", image: "postgres", project: "shop", ports: [5432])]
        let entries = PortMap.build(groups: groups, containers: containers) { process in
            process.pid == 10 ? [ListeningSocket(port: 3000, address: "0.0.0.0"), ListeningSocket(port: 3000, address: "::")]
                              : [ListeningSocket(port: 5432, address: "127.0.0.1")]
        }
        XCTAssertEqual(entries.map(\.port), [3000, 5432])
        XCTAssertEqual(entries[0].groupTitle, "shop")
        XCTAssertTrue(entries[0].isExposed)
        XCTAssertEqual(entries[1].container, "db-1 (shop)")
        XCTAssertEqual(entries[1].containerID, "c1")
        XCTAssertFalse(entries[1].isExposed)
    }

    func testAirPlayIsExplained() {
        XCTAssertNotNil(PortMap.knownUse(port: 5000, processName: "ControlCenter"))
        XCTAssertNil(PortMap.knownUse(port: 3000, processName: "node"))
    }

    func testRealListeningSocketIsReadWithItsAddress() throws {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        defer { close(fd) }
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        address.sin_port = 0
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        XCTAssertEqual(bound, 0)
        XCTAssertEqual(Darwin.listen(fd, 1), 0)
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        withUnsafeMutablePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { _ = getsockname(fd, $0, &length) }
        }
        let port = Int(UInt16(bigEndian: address.sin_port))
        let found = ProcessSampler.listeningSockets(getpid()).first { $0.port == port }
        XCTAssertEqual(found?.address, "127.0.0.1")
        XCTAssertEqual(found?.isLoopback, true)
    }
}
