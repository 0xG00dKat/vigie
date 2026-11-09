import Foundation
import XCTest
@testable import VigieCore

final class SimpleModeTests: FrenchTestCase {
    func testLeftoverNames() {
        XCTAssertEqual(LeftoverFinder.appName(fromIdentifier: "com.readdle.SparkDesktop.helper"), "Spark")
        XCTAssertEqual(LeftoverFinder.appName(fromIdentifier: "org.mozilla.firefox"), "Firefox")
        XCTAssertEqual(LeftoverFinder.appName(fromIdentifier: "com.setapp.DesktopClient.SetappAgent"), "Setapp")
        XCTAssertEqual(LeftoverFinder.appName(fromIdentifier: "com.parallels.desktop.console"), "Parallels")
        XCTAssertEqual(LeftoverFinder.appName(fromIdentifier: "com.adguard.mac.adguard"), "Adguard")
        XCTAssertEqual(LeftoverFinder.appName(fromIdentifier: "com.spotify.client"), "Spotify")
    }

    func testDeveloperCachesAreGrouped() {
        let report = DemoData.storage()
        let caches = report.cacheEntriesGroupingDeveloperTools()
        let group = caches.first { $0.id == StorageCatalog.developerCachesID }
        XCTAssertNotNil(group)
        XCTAssertTrue(caches.allSatisfy { !StorageCatalog.developerCacheIDs.contains($0.id) })
        // Même total : rien n'est caché, c'est regroupé.
        XCTAssertEqual(caches.reduce(0) { $0 + $1.size }, report.entries(of: .cache).reduce(0) { $0 + $1.size })
        // Le groupe lui-même ne se supprime jamais d'un bloc.
        XCTAssertNil(StorageCleaner.cleanup(for: group!, home: DemoData.home))
    }

    func testHiddenFoldersAreGrouped() {
        let listing = DemoData.explorer(DemoData.home)!
        let (grouped, members) = listing.groupingHiddenItems(title: "Dossiers cachés")
        XCTAssertTrue(grouped.items.allSatisfy { !$0.name.hasPrefix(".") || $0.path == listing.hiddenGroupPath })
        XCTAssertEqual(Set(members.map(\.name)), Set(listing.items.filter { $0.name.hasPrefix(".") }.map(\.name)))
        XCTAssertEqual(grouped.items.reduce(0) { $0 + $1.size }, listing.items.reduce(0) { $0 + $1.size })
        let advice = ExplorerAdvice.adviseHiddenGroup(members: members, home: DemoData.home, report: DemoData.storage())
        XCTAssertEqual(advice.level, .keep)
        XCTAssertGreaterThan(advice.reclaimableInside, 0)
    }
}
