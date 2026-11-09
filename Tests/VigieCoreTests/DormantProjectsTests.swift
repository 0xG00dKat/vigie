import Foundation
import XCTest
@testable import VigieCore

final class DormantProjectsTests: FrenchTestCase {
    private var home: URL!

    override func setUpWithError() throws {
        home = FileManager.default.temporaryDirectory.appendingPathComponent("vigie-endormis-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: home)
    }

    private func make(_ relative: String, size: Int = 0, modified: Date? = nil) throws {
        let url = home.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(count: size).write(to: url)
        if let modified { try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path) }
    }

    private func age(_ path: String, _ date: Date) throws {
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: home.appendingPathComponent(path).path)
    }

    func testOldProjectProposesDependenciesAndBuildsOnly() throws {
        let old = Date().addingTimeInterval(-400 * 86_400)
        try make("code/vieux/package.json", modified: old)
        try make("code/vieux/src/index.js", size: 100, modified: old)
        try make("code/vieux/node_modules/react/index.js", size: 2_000_000)
        try make("code/vieux/.next/cache/a", size: 1_000_000)
        try make("code/vieux/dist/main.js", size: 500_000) // pas de Git : « dist » n'est pas proposé
        try age("code/vieux/src", old)
        // Le dossier du projet lui-même vient d'être rangé ailleurs : ça ne compte pas comme une activité.
        try make("code/actif/package.json")
        try make("code/actif/src/app.js", modified: old)
        try make("code/actif/node_modules/x/index.js", size: 1_000_000)

        let modules = ["vieux", "actif"].map { name in
            StorageEntry(id: "project:x", title: L(name, name), explanation: L("", ""), kind: .project,
                         path: home.path + "/code/\(name)/node_modules", size: 2_000_000)
        }
        let dormant = DormantProjects.find(in: StorageReport(entries: modules, localSnapshots: 0))
        XCTAssertEqual(dormant.map(\.title.fr), ["vieux"])
        let project = try XCTUnwrap(dormant.first)
        XCTAssertEqual(Set(project.children.map { PathRules.lastComponent($0.path) }), ["node_modules", ".next"])
        // Corbeille : dépendances et compilation, jamais le code.
        guard case .trashAll(let paths)? = StorageCleaner.cleanup(for: project, home: home.path) else { return XCTFail("corbeille attendue") }
        XCTAssertFalse(paths.contains { $0.hasSuffix("/src") || $0 == project.path })
        XCTAssertEqual(paths.count, 2)
    }
}
