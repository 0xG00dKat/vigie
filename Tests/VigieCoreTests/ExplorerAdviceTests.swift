import Foundation
import XCTest
@testable import VigieCore

final class ExplorerAdviceTests: FrenchTestCase {
    let home = DemoData.home

    func testBlocksFollowTheStorageAnalysis() {
        let report = DemoData.storage()
        // Un cache connu de l'analyse : sûr, avec sa ligne (donc son nettoyage).
        let cache = ExplorerAdvice.advise(path: home + "/.npm", home: home, report: report)
        XCTAssertEqual(cache.level, .safe)
        XCTAssertEqual(cache.entry?.id, "npm")
        // Un dossier de projets : rien à dire de lui, mais ses node_modules se vident.
        let code = ExplorerAdvice.advise(path: home + "/code", home: home, report: report)
        XCTAssertEqual(code.level, .unknown)
        XCTAssertEqual(code.reclaimableInside, 4_400_000_000)
        XCTAssertEqual(code.reclaimableKind, .project)
        // La bibliothèque est à garder, mais contient des caches : chacun compté une fois.
        let library = ExplorerAdvice.advise(path: home + "/Library", home: home, report: report)
        XCTAssertEqual(library.level, .keep)
        XCTAssertEqual(library.reclaimableInside, 11_000_000_000 + 5_200_000_000 + 7_400_000_000)
        XCTAssertEqual(library.reclaimableKind, .cache)
        XCTAssertEqual(ExplorerAdvice.advise(path: home + "/Downloads", home: home, report: report).level, .review)
    }

    func testRulesWithoutAnalysis() {
        XCTAssertEqual(ExplorerAdvice.advise(path: home + "/Library/Caches", home: home, report: nil).level, .safe)
        XCTAssertEqual(ExplorerAdvice.advise(path: home + "/Documents", home: home, report: nil).level, .keep)
        XCTAssertEqual(ExplorerAdvice.advise(path: home + "/Downloads", home: home, report: nil).level, .review)
        XCTAssertEqual(ExplorerAdvice.advise(path: home + "/code/site/node_modules", home: home, report: nil).level, .safe)
        XCTAssertEqual(ExplorerAdvice.advise(path: home + "/.rustup", home: home, report: nil).level, .keep)
        XCTAssertEqual(ExplorerAdvice.advise(path: home + "/code", home: home, report: nil).level, .unknown)
        XCTAssertEqual(ExplorerAdvice.advise(path: "/Applications", home: home, report: nil).level, .unknown)
    }
}

final class ContentKindTests: FrenchTestCase {
    func testKinds() {
        let home = "/Users/test"
        XCTAssertEqual(ContentKind(path: home + "/Movies", isDirectory: true), .media)
        XCTAssertEqual(ContentKind(path: home + "/Pictures/Photos Library.photoslibrary", isDirectory: true), .media)
        XCTAssertEqual(ContentKind(path: home + "/Desktop", isDirectory: true), .documents)
        XCTAssertEqual(ContentKind(path: home + "/Downloads/Xcode.xip", isDirectory: false), .documents)
        XCTAssertEqual(ContentKind(path: home + "/Downloads/vacances.mov", isDirectory: false), .media)
        XCTAssertEqual(ContentKind(path: home + "/code", isDirectory: true), .dev)
        XCTAssertEqual(ContentKind(path: home + "/.npm", isDirectory: true), .dev)
        XCTAssertEqual(ContentKind(path: home + "/Library/Developer", isDirectory: true), .dev)
        XCTAssertEqual(ContentKind(path: home + "/.cache", isDirectory: true), .caches)
        XCTAssertEqual(ContentKind(path: home + "/Library/Caches", isDirectory: true), .caches)
        XCTAssertEqual(ContentKind(path: home + "/Applications", isDirectory: true), .apps)
        XCTAssertEqual(ContentKind(path: home + "/Library", isDirectory: true), .system)
        XCTAssertEqual(ContentKind(path: home + "/Library/Application Support", isDirectory: true), .system)
        XCTAssertEqual(ContentKind(path: home + "/.zsh_sessions", isDirectory: true), .system)
        XCTAssertEqual(ContentKind(path: home + "/Mes trucs", isDirectory: true), .other)
    }
}
