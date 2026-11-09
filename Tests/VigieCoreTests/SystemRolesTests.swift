import XCTest
@testable import VigieCore

final class SystemRolesTests: FrenchTestCase {
    func testKnownServicesFindTheirRole() {
        let expected: [(String, SystemRole)] = [
            ("WindowServer", .interface), ("Dock", .interface), ("Control Centre", .interface),
            ("mds_stores", .search), ("mdworker_shared", .search), ("parsecd", .search),
            ("siriinferenced", .intelligence), ("assistantd", .intelligence),
            ("bird", .cloud), ("cloudd", .cloud), ("fileproviderd", .cloud),
            ("imagent", .communication), ("callservicesd", .communication),
            ("sharingd", .network), ("airportd", .network), ("mDNSResponder", .network),
            ("trustd", .security), ("XProtect", .security), ("fairplayd", .security),
            ("coreaudiod", .media), ("photoanalysisd", .media),
            ("softwareupdated", .updates), ("appstoreagent", .updates),
            ("Calendar", .appleApps), ("homed", .appleApps),
            ("cfprefsd", .core), ("launchd", .core), ("apfsd", .core),
            ("Virtual Machine Service for Docker", .virtualMachines),
        ]
        for (name, role) in expected {
            XCTAssertEqual(SystemRole.role(name: name), role, name)
        }
    }

    func testLookalikesAreNotConfused() {
        // « docker » contient « dock », « fairplay » contient « airplay », « simdiskimaged » contient « imd ».
        XCTAssertNotEqual(SystemRole.role(name: "com.docker.vmnetd"), .interface)
        XCTAssertNotEqual(SystemRole.role(name: "fairplayd"), .network)
        XCTAssertNotEqual(SystemRole.role(name: "simdiskimaged"), .communication)
        XCTAssertEqual(SystemRole.role(name: "quelquechose-inconnu"), .other)
    }

    func testFamiliesAreSortedHeaviestFirstWithOthersLast() {
        func group(_ title: String, _ memory: UInt64) -> ProcessGroup {
            var group = ProcessGroup(id: title, category: .system, title: title, explanation: Explanation(""),
                                     processes: [], close: .notAllowed("macOS"), isProtected: true)
            group.memory = memory
            return group
        }
        let families = SystemRoleGroup.make([
            group("inconnu-lourd", 9_000), group("WindowServer", 500), group("trustd", 100), group("tccd", 2_000),
        ])
        XCTAssertEqual(families.map(\.role), [.security, .interface, .other])
        XCTAssertEqual(families.first?.groups.map(\.title), ["tccd", "trustd"])
    }
}
