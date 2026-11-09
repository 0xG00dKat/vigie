import Foundation
import XCTest
@testable import VigieCore

final class ToolchainsTests: FrenchTestCase {
    private var home: URL!

    override func setUpWithError() throws {
        home = FileManager.default.temporaryDirectory.appendingPathComponent("vigie-versions-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: home)
    }

    private func folder(_ relative: String) throws {
        try FileManager.default.createDirectory(at: home.appendingPathComponent(relative), withIntermediateDirectories: true)
    }

    private func write(_ relative: String, _ text: String) throws {
        let url = home.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    func testVersionsDefaultsAndProjects() throws {
        for version in ["v18.19.0", "v20.11.1", "v22.3.0"] { try folder(".nvm/versions/node/\(version)/bin") }
        try write(".nvm/alias/default", "20")
        try folder(".pyenv/versions/3.11.7")
        try folder(".pyenv/versions/3.12.2")
        try write(".pyenv/version", "3.12.2\n")
        try folder(".local/share/uv/python/cpython-3.11.15-macos-aarch64-none")
        try FileManager.default.createSymbolicLink(atPath: home.path + "/.local/share/uv/python/cpython-3.11-macos-aarch64-none",
                                                   withDestinationPath: home.path + "/.local/share/uv/python/cpython-3.11.15-macos-aarch64-none")
        try folder(".rbenv/versions/3.3.0")
        try write("code/site/.nvmrc", "18\n")

        let running = [home.path + "/.nvm/versions/node/v22.3.0/bin/node"]
        let versions = Toolchains.find(home: home.path, runningPaths: running, projects: [home.path + "/code/site"],
                                        cellars: [home.path + "/Cellar"])
        let node = versions.filter { $0.runtime == .node }
        XCTAssertEqual(node.map(\.version), ["18.19.0", "20.11.1", "22.3.0"])
        XCTAssertEqual(node.first { $0.version == "20.11.1" }?.isDefault, true)
        XCTAssertEqual(node.first { $0.version == "22.3.0" }?.inUse, true)
        XCTAssertEqual(node.first { $0.version == "18.19.0" }?.usedBy, ["site"])
        // Le lien d'uv n'est pas une version de plus.
        XCTAssertEqual(versions.filter { $0.manager == "uv" }.map(\.version), ["3.11.15"])

        let trashable = Toolchains.trashable(versions)
        // Node : 18 seulement (20 par défaut, 22 en cours). Python : pyenv 3.11.7 (3.12.2 par défaut) ; uv garde sa seule version.
        // Ruby : installé une fois, jamais proposé.
        XCTAssertEqual(Set(trashable.map(\.version)), ["18.19.0", "3.11.7"])
    }

    func testEachManagerKeepsOneVersion() {
        let versions = [
            RuntimeVersion(runtime: .python, version: "3.10.4", manager: "pyenv", path: "/h/.pyenv/versions/3.10.4"),
            RuntimeVersion(runtime: .python, version: "3.12.1", manager: "pyenv", path: "/h/.pyenv/versions/3.12.1"),
            RuntimeVersion(runtime: .python, version: "3.14.0", manager: "Homebrew", path: "/opt/homebrew/Cellar/python@3.14/3.14.0",
                           command: "brew uninstall python@3.14"),
        ]
        // Sans version par défaut, pyenv garde la plus récente ; Homebrew n'est jamais mis à la corbeille.
        XCTAssertEqual(Toolchains.trashable(versions).map(\.version), ["3.10.4"])
    }

    func testVersionMatching() {
        XCTAssertTrue(Toolchains.matches("20.11.1", "20"))
        XCTAssertTrue(Toolchains.matches("20.11.1", "v20.11"))
        XCTAssertFalse(Toolchains.matches("20.11.1", "2"))
        XCTAssertFalse(Toolchains.matches("20.11.1", "lts/*"))
        XCTAssertEqual(Toolchains.uvVersion("cpython-3.12.1-macos-aarch64-none"), "3.12.1")
    }
}

final class DevLeftoversTests: FrenchTestCase {
    func testOrphanDockerVolumes() {
        let json = """
        {"Volumes":[{"Name":"abc123","Links":"0","Size":"76.41MB","Labels":"com.docker.volume.anonymous="},
        {"Name":"shop_db","Links":"0","Size":"1.2GB","Labels":"com.docker.compose.project=shop,com.docker.compose.volume=db"},
        {"Name":"live_db","Links":"1","Size":"300MB","Labels":""}]}
        """
        let volumes = DockerReader.parseOrphanVolumes(json)
        XCTAssertEqual(volumes.map(\.name), ["shop_db", "abc123"])
        XCTAssertEqual(volumes.first?.project, "shop")
        XCTAssertEqual(volumes.last?.isAnonymous, true)
        XCTAssertEqual(volumes.first?.removeCommand, "docker volume rm shop_db")
    }

    func testGlobalPackagesSkipNpmItself() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("vigie-npm-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: home) }
        for package in ["npm", "corepack", "vercel", "@angular/cli"] {
            let url = home.appendingPathComponent(".nvm/versions/node/v20.11.1/lib/node_modules/\(package)")
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            try Data(count: 10_000).write(to: url.appendingPathComponent("index.js"))
        }
        let packages = Toolchains.globalPackages(home: home.path, cellars: []).filter { $0.path.hasPrefix(home.path) }
        XCTAssertEqual(Set(packages.map(\.name)), ["vercel", "@angular/cli"])
        XCTAssertEqual(packages.first?.owner, "nvm 20.11.1")
    }
}
