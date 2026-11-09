import Foundation
import XCTest
@testable import VigieCore

final class RulesTests: FrenchTestCase {
    private func group(_ title: String, memory: UInt64, category: ProcessCategory = .apps, protected: Bool = false, bundleID: String? = nil) -> ProcessGroup {
        var process = RawProcess(pid: 42, ppid: 1, uid: 501, name: title, path: "/Applications/\(title).app/Contents/MacOS/\(title)")
        process.memory = memory
        return ProcessGroup(id: "app:" + title, category: category, title: title, explanation: Explanation(""), bundleID: bundleID,
                            processes: [process], close: .quitApps([42]), isProtected: protected)
    }

    func testMemoryAlertOncePerCrossing() {
        let gb: UInt64 = 1_000_000_000
        let rule = VigieRule(appName: "Slack", kind: .memoryAbove(bytes: 4 * gb))
        var alerted = Set<UUID>()
        XCTAssertTrue(RuleEngine.memoryAlerts(rules: [rule], groups: [group("Slack", memory: 3 * gb)], alerted: &alerted).isEmpty)
        XCTAssertEqual(RuleEngine.memoryAlerts(rules: [rule], groups: [group("Slack", memory: 5 * gb)], alerted: &alerted).count, 1)
        // Toujours au-dessus : pas de deuxième notification.
        XCTAssertTrue(RuleEngine.memoryAlerts(rules: [rule], groups: [group("Slack", memory: 6 * gb)], alerted: &alerted).isEmpty)
        // Juste sous le seuil (plus de 90 %) : pas encore réarmée.
        XCTAssertTrue(RuleEngine.memoryAlerts(rules: [rule], groups: [group("Slack", memory: 3_800_000_000)], alerted: &alerted).isEmpty)
        XCTAssertTrue(RuleEngine.memoryAlerts(rules: [rule], groups: [group("Slack", memory: 5 * gb)], alerted: &alerted).isEmpty)
        // Redescendue nettement, puis remontée : nouvelle alerte.
        _ = RuleEngine.memoryAlerts(rules: [rule], groups: [group("Slack", memory: 2 * gb)], alerted: &alerted)
        XCTAssertEqual(RuleEngine.memoryAlerts(rules: [rule], groups: [group("Slack", memory: 5 * gb)], alerted: &alerted).count, 1)
        // Règle coupée : rien.
        var off = rule
        off.isEnabled = false
        var fresh = Set<UUID>()
        XCTAssertTrue(RuleEngine.memoryAlerts(rules: [off], groups: [group("Slack", memory: 9 * gb)], alerted: &fresh).isEmpty)
    }

    func testMatchPrefersBundleIDAndSkipsSystem() {
        let rule = VigieRule(appName: "slack", bundleID: "com.tinyspeck.slackmacgap", kind: .memoryAbove(bytes: 1))
        let groups = [group("Slack", memory: 1, category: .system), group("Slack Helper", memory: 1, bundleID: "com.tinyspeck.slackmacgap")]
        XCTAssertEqual(rule.match(in: groups)?.title, "Slack Helper")
        XCTAssertFalse(RuleEngine.canQuit(group("Finder", memory: 1, protected: true)))
        XCTAssertFalse(RuleEngine.canQuit(group("WindowServer", memory: 1, category: .system)))
        XCTAssertTrue(RuleEngine.canQuit(group("Slack", memory: 1)))
    }

    func testQuitTimeIsDueOnlyOnce() {
        let calendar = Calendar.current
        let rule = VigieRule(appName: "Slack", kind: .quitAt(hour: 19, minute: 0))
        let day = calendar.startOfDay(for: Date())
        func at(_ hour: Int, _ minute: Int) -> Date { day.addingTimeInterval(Double(hour * 3600 + minute * 60)) }
        XCTAssertFalse(RuleEngine.quitIsDue(rule, lastCheck: at(18, 58), now: at(18, 59)))
        XCTAssertTrue(RuleEngine.quitIsDue(rule, lastCheck: at(18, 59), now: at(19, 0)))
        XCTAssertFalse(RuleEngine.quitIsDue(rule, lastCheck: at(19, 0), now: at(19, 1)), "déjà passée")
        // Mac endormi de 18 h à 19 h 30 : on quitte encore ; endormi jusqu'à 22 h : trop tard, rien.
        XCTAssertTrue(RuleEngine.quitIsDue(rule, lastCheck: at(18, 0), now: at(19, 30)))
        XCTAssertFalse(RuleEngine.quitIsDue(rule, lastCheck: at(18, 0), now: at(22, 0)))
        XCTAssertEqual(RuleEngine.nextQuit(rule, after: at(20, 0)), at(19, 0).addingTimeInterval(86_400))
        XCTAssertEqual(rule.summary.fr, "Quitter Slack chaque jour à 19:00")
    }

    func testRulesAreSaved() {
        let defaults = UserDefaults(suiteName: "vigie-regles-\(UUID().uuidString)")!
        let rules = [VigieRule(appName: "Slack", kind: .quitAt(hour: 19, minute: 30)),
                     VigieRule(appName: "Chrome", kind: .memoryAbove(bytes: 3_000_000_000), isEnabled: false)]
        RuleStore.save(rules, defaults)
        XCTAssertEqual(RuleStore.load(defaults), rules)
    }
}
