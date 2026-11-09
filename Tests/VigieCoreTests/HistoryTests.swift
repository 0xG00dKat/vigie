import Foundation
import XCTest
@testable import VigieCore

final class HistoryTests: FrenchTestCase {
    let total: UInt64 = 500_000_000_000
    let gigabyte: UInt64 = 1_000_000_000

    func testDueEveryHourAndPruning() {
        let now = Date()
        XCTAssertTrue(HistoryStore.isDue([], now: now))
        let recent = HistoryPoint(date: now.addingTimeInterval(-1800), diskUsed: 1, diskTotal: total)
        XCTAssertFalse(HistoryStore.isDue([recent], now: now))
        XCTAssertTrue(HistoryStore.isDue([HistoryPoint(date: now.addingTimeInterval(-2 * 3600), diskUsed: 1, diskTotal: total)], now: now))
        // Une analyse ne compte pas comme mesure régulière.
        let scan = HistoryPoint(date: now, diskUsed: 1, diskTotal: total, storage: [])
        XCTAssertTrue(HistoryStore.isDue([scan], now: now))

        // 8 mesures par jour pendant 60 jours : tout sur 14 jours, une par jour avant.
        var points: [HistoryPoint] = []
        for hour in stride(from: 60 * 24, to: 0, by: -3) {
            points.append(HistoryPoint(date: now.addingTimeInterval(-Double(hour) * 3600), diskUsed: 1, diskTotal: total))
        }
        let pruned = HistoryStore.prune(points, now: now)
        let old = pruned.filter { now.timeIntervalSince($0.date) > 14 * 86_400 }
        XCTAssertLessThanOrEqual(old.count, 47)
        XCTAssertGreaterThanOrEqual(old.count, 45)
        XCTAssertEqual(pruned.count - old.count, points.filter { now.timeIntervalSince($0.date) <= 14 * 86_400 }.count)
    }

    func testDiskGrowthNamesTheCause() {
        let now = Date()
        func scan(daysAgo: Double, used: UInt64, docker: UInt64) -> HistoryPoint {
            HistoryPoint(date: now.addingTimeInterval(-daysAgo * 86_400), diskUsed: used, diskTotal: total,
                         storage: [.init(id: "docker", title: L("Docker", "Docker"), size: docker),
                                   .init(id: "npm", title: L("Cache npm", "npm cache"), size: 8 * gigabyte)])
        }
        let points = [scan(daysAgo: 29, used: 300 * gigabyte, docker: 10 * gigabyte), scan(daysAgo: 0, used: 330 * gigabyte, docker: 22 * gigabyte)]
        let insight = HistoryInsights.diskChange(points, now: now)
        XCTAssertEqual(insight?.kind, .diskGrowth)
        XCTAssertEqual(insight?.text.fr, "Ton disque a pris 30 Go ce mois-ci, dont +12 Go pour « Docker ».")
        XCTAssertEqual(insight?.isWarning, true)
    }

    func testForecastWhenFreeSpaceShrinks() {
        let now = Date()
        // 1 Go de moins par jour, 40 Go libres à la fin : plein dans environ 6 semaines.
        let points = (0...20).map { day in
            HistoryPoint(date: now.addingTimeInterval(-Double(20 - day) * 86_400), diskUsed: total - (60 - UInt64(day)) * gigabyte, diskTotal: total)
        }
        let forecast = HistoryInsights.forecast(points, now: now)
        XCTAssertEqual(forecast?.text.fr, "Au rythme actuel, ton disque sera plein dans environ 6 semaines.")
        // Disque stable : pas de prévision.
        let stable = (0...20).map { HistoryPoint(date: now.addingTimeInterval(-Double($0) * 86_400), diskUsed: 300 * gigabyte, diskTotal: total) }
        XCTAssertNil(HistoryInsights.forecast(stable, now: now))
    }

    func testHeavyAppEveryAfternoon() {
        var calendar = Calendar.current
        calendar.timeZone = .current
        let today = calendar.startOfDay(for: Date())
        var points: [HistoryPoint] = []
        for day in 1...10 {
            for hour in [9, 15, 21] {
                let date = today.addingTimeInterval(-Double(day) * 86_400 + Double(hour) * 3600)
                let slack: UInt64 = hour == 15 ? 2_400_000_000 : 1_600_000_000
                points.append(HistoryPoint(date: date, diskUsed: 1, diskTotal: total,
                                           apps: [.init(name: "Slack", memory: slack), .init(name: "Notes", memory: 200_000_000)]))
            }
        }
        let insights = HistoryInsights.appMemory(points, now: today)
        XCTAssertEqual(insights.count, 1)
        XCTAssertEqual(insights.first?.text.fr, "Slack prend environ 2,4 Go de mémoire l'après-midi.")
    }

    func testSaveAndLoad() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("vigie-historique-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let point = HistoryPoint(date: Date(timeIntervalSince1970: 1_800_000_000), diskUsed: 3, diskTotal: total, memoryUsed: 5, memoryTotal: 8,
                                 apps: [.init(name: "Safari", memory: 9)])
        HistoryStore.save([point], to: url)
        XCTAssertEqual(HistoryStore.load(from: url), [point])
    }
}

final class HeavyAppsTests: FrenchTestCase {
    func testOneCountPerMeasureAndReadableNames() {
        let now = Date()
        var points: [HistoryPoint] = []
        for index in 0..<10 {
            var apps: [HistoryPoint.AppMemory] = [.init(name: "Claude", memory: 2_000_000_000), .init(name: "Claude", memory: 500_000_000)]
            if index < 3 { apps.append(.init(name: "SimulatorTrampoline", memory: 9_000_000_000)) }
            points.append(HistoryPoint(date: now.addingTimeInterval(-Double(index) * 3 * 3600), diskUsed: 1, diskTotal: 2, apps: apps))
        }
        let apps = HistoryInsights.heavyApps(points)
        let claude = apps.first { $0.name == "Claude" }
        XCTAssertEqual(claude?.typical, 2_000_000_000)
        XCTAssertEqual(claude?.presence, .almostAlways)
        let simulator = apps.first { $0.name == "Simulateur iPhone (Xcode)" }
        XCTAssertEqual(simulator?.presence, .sometimes)
        // Trop peu de mesures : pas de fréquence.
        XCTAssertNil(HistoryInsights.heavyApps(Array(points.prefix(3))).first?.presence)
    }
}
