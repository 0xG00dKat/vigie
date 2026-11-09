import Foundation
import XCTest
@testable import VigieCore

final class KeepAliveTests: FrenchTestCase {
    func testKeepAliveValues() {
        XCTAssertTrue(KeepAliveJob.keepsAlive(true))
        XCTAssertFalse(KeepAliveJob.keepsAlive(false))
        XCTAssertFalse(KeepAliveJob.keepsAlive(nil))
        // Relance sous condition (« SuccessfulExit = false » : seulement après un plantage… ou un SIGTERM).
        XCTAssertTrue(KeepAliveJob.keepsAlive(["SuccessfulExit": false]))
        XCTAssertFalse(KeepAliveJob.keepsAlive([String: Any]()))
    }

    func testOnlyRunningKeepAliveAgentsAreKept() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("vigie-agents-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        func agent(_ label: String, keepAlive: Any?, throttle: Int? = nil) throws {
            var plist: [String: Any] = ["Label": label, "ProgramArguments": ["/usr/bin/true"]]
            if let keepAlive { plist["KeepAlive"] = keepAlive }
            if let throttle { plist["ThrottleInterval"] = throttle }
            let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            try data.write(to: folder.appendingPathComponent(label + ".plist"))
        }
        try agent("com.exemple.serveur", keepAlive: true, throttle: 5)
        try agent("com.exemple.unefois", keepAlive: nil)
        try agent("com.exemple.arrete", keepAlive: true)
        let running: [String: Int32?] = ["com.exemple.serveur": 4242, "com.exemple.unefois": 51, "com.exemple.arrete": nil]
        let jobs = KeepAliveJob.parse(running: running, folders: [(folder.path, true)])
        XCTAssertEqual(jobs.map(\.label), ["com.exemple.serveur"])
        XCTAssertEqual(jobs.first?.pid, 4242)
        XCTAssertEqual(jobs.first?.throttle, 5)
        XCTAssertEqual(jobs.first?.shortName, "serveur")
        XCTAssertEqual(jobs.first?.isUser, true)
    }
}
