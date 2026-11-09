import Foundation

/// L'historique : quelques mesures par jour, gardées sur le Mac (`~/Library/Application Support/Vigie/historique.json`),
/// pour dire ce qui change dans le temps (« ton disque a pris 30 Go ce mois-ci, surtout à cause de Docker »).
/// Rien ne quitte le Mac.
///
/// Une mesure par heure (place utilisée, mémoire, apps qui en prennent le plus), plus le détail du disque
/// à chaque analyse du stockage. Au-delà de 14 jours, une mesure par jour ; au-delà de 400 jours, plus rien.
public struct HistoryPoint: Codable, Sendable, Equatable {
    public struct AppMemory: Codable, Sendable, Equatable {
        public var name: String
        public var memory: UInt64

        public init(name: String, memory: UInt64) {
            self.name = name
            self.memory = memory
        }
    }

    /// Une ligne de l'analyse du stockage (les plus grosses), pour savoir ce qui a grossi.
    public struct StorageMark: Codable, Sendable, Equatable {
        public var id: String
        public var title: L
        public var size: UInt64

        public init(id: String, title: L, size: UInt64) {
            self.id = id
            self.title = title
            self.size = size
        }
    }

    public var date: Date
    public var diskUsed: UInt64
    public var diskTotal: UInt64
    public var memoryUsed: UInt64?
    public var memoryTotal: UInt64?
    public var apps: [AppMemory]?
    /// Présent seulement pour une mesure prise à la fin d'une analyse du stockage.
    public var storage: [StorageMark]?

    public init(date: Date, diskUsed: UInt64, diskTotal: UInt64, memoryUsed: UInt64? = nil, memoryTotal: UInt64? = nil,
                apps: [AppMemory]? = nil, storage: [StorageMark]? = nil) {
        self.date = date
        self.diskUsed = diskUsed
        self.diskTotal = diskTotal
        self.memoryUsed = memoryUsed
        self.memoryTotal = memoryTotal
        self.apps = apps
        self.storage = storage
    }

    public var diskFree: UInt64 { diskTotal > diskUsed ? diskTotal - diskUsed : 0 }

    /// Mesure régulière (toutes les 3 heures), à partir d'un instantané des processus.
    public static func regular(disk: DiskStatus, snapshot: Snapshot?, date: Date = Date()) -> HistoryPoint {
        let apps = snapshot.map { snapshot in
            snapshot.groups.filter { $0.category == .apps || $0.category == .background }
                .sorted { $0.memory > $1.memory }
                .prefix(6)
                .map { AppMemory(name: $0.title, memory: $0.memory) }
        }
        return HistoryPoint(date: date, diskUsed: disk.total - min(disk.total, disk.available), diskTotal: disk.total,
                            memoryUsed: snapshot?.memoryUsed, memoryTotal: snapshot?.memoryTotal, apps: apps)
    }

    /// Mesure à la fin d'une analyse : les 40 plus grosses lignes (les gros fichiers ne comptent pas, déjà dans leurs dossiers).
    public static func scan(disk: DiskStatus, report: StorageReport, date: Date = Date()) -> HistoryPoint {
        let marks = report.entries.filter { $0.kind != .largeFile }
            .sorted { $0.size > $1.size }
            .prefix(40)
            .map { StorageMark(id: $0.id, title: $0.title, size: $0.size) }
        return HistoryPoint(date: date, diskUsed: disk.total - min(disk.total, disk.available), diskTotal: disk.total, storage: marks)
    }
}

public enum HistoryStore {
    public static let interval: TimeInterval = 3600
    static let detailedDays: TimeInterval = 14 * 86_400
    static let keptDays: TimeInterval = 400 * 86_400

    public static var defaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Vigie/historique.json")
    }

    private struct Saved: Codable {
        var version: Int
        var points: [HistoryPoint]
    }

    public static func load(from url: URL = defaultURL) -> [HistoryPoint] {
        guard let data = try? Data(contentsOf: url), let saved = try? JSONDecoder().decode(Saved.self, from: data) else { return [] }
        return saved.points.sorted { $0.date < $1.date }
    }

    public static func save(_ points: [HistoryPoint], to url: URL = defaultURL) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(Saved(version: 1, points: points)) { try? data.write(to: url, options: .atomic) }
    }

    /// Une mesure régulière est due : la dernière a plus d'une heure.
    public static func isDue(_ points: [HistoryPoint], now: Date = Date()) -> Bool {
        guard let last = points.last(where: { $0.storage == nil }) else { return true }
        return now.timeIntervalSince(last.date) >= interval
    }

    public static func appending(_ point: HistoryPoint, to points: [HistoryPoint], now: Date = Date()) -> [HistoryPoint] {
        prune((points + [point]).sorted { $0.date < $1.date }, now: now)
    }

    /// Tout sur 14 jours ; au-delà, la dernière mesure de chaque jour (et la dernière analyse du jour) ; rien après 400 jours.
    public static func prune(_ points: [HistoryPoint], now: Date = Date()) -> [HistoryPoint] {
        let calendar = Calendar.current
        var keptOld: [String: HistoryPoint] = [:]
        var recent: [HistoryPoint] = []
        for point in points {
            let age = now.timeIntervalSince(point.date)
            if age > keptDays { continue }
            if age <= detailedDays { recent.append(point); continue }
            let day = calendar.startOfDay(for: point.date).timeIntervalSince1970
            let key = "\(day)-\(point.storage == nil ? "m" : "s")"
            if let existing = keptOld[key], existing.date > point.date { continue }
            keptOld[key] = point
        }
        return (Array(keptOld.values) + recent).sorted { $0.date < $1.date }
    }
}

extension HistoryStore {
    /// Une mesure par jour (la moyenne du jour) : des courbes lisibles sur un mois ou un an.
    public static func dailyAverages(_ points: [HistoryPoint]) -> [HistoryPoint] {
        let calendar = Calendar.current
        let byDay = Dictionary(grouping: points.filter { $0.storage == nil }) { calendar.startOfDay(for: $0.date) }
        return byDay.map { day, list in
            let count = UInt64(list.count)
            let memories = list.compactMap(\.memoryUsed)
            return HistoryPoint(date: day.addingTimeInterval(12 * 3600),
                                diskUsed: list.reduce(0) { $0 + $1.diskUsed } / count,
                                diskTotal: list.last?.diskTotal ?? 0,
                                memoryUsed: memories.isEmpty ? nil : memories.reduce(0, +) / UInt64(memories.count),
                                memoryTotal: list.compactMap(\.memoryTotal).last,
                                apps: list.flatMap { $0.apps ?? [] }.isEmpty ? nil : list.flatMap { $0.apps ?? [] })
        }
        .sorted { $0.date < $1.date }
    }
}

// MARK: - Ce que l'historique raconte

public struct HistoryInsight: Sendable, Equatable, Identifiable {
    public enum Kind: String, Sendable { case diskGrowth, diskFreed, diskForecast, appMemory }
    public var id: String
    public var kind: Kind
    public var text: L
    /// À surveiller (orange) ou simple information.
    public var isWarning: Bool
}

public enum HistoryInsights {
    /// Au moins quelques jours de mesures avant de parler de tendance.
    static let minimumSpan: TimeInterval = 5 * 86_400

    public static func make(_ points: [HistoryPoint], now: Date = Date()) -> [HistoryInsight] {
        var insights: [HistoryInsight] = []
        if let disk = diskChange(points, now: now) { insights.append(disk) }
        if let forecast = forecast(points, now: now) { insights.append(forecast) }
        insights += appMemory(points, now: now)
        return insights
    }

    /// « Ton disque a pris 30 Go ce mois-ci, surtout à cause de Docker (+12 Go). »
    static func diskChange(_ points: [HistoryPoint], now: Date) -> HistoryInsight? {
        let window = points.filter { now.timeIntervalSince($0.date) <= 30 * 86_400 }
        guard let first = window.first, let last = window.last, last.date.timeIntervalSince(first.date) >= minimumSpan else { return nil }
        let delta = Int64(last.diskUsed) - Int64(first.diskUsed)
        guard abs(delta) >= 2_000_000_000 else { return nil }
        let days = Int((last.date.timeIntervalSince(first.date) / 86_400).rounded())
        let period = days >= 27 ? L("ce mois-ci", "this month") : L("en \(days) jours", "in \(days) days")
        let amount = { (language: Language) in Format.bytes(UInt64(abs(delta)), decimal: true, in: language) }
        if delta < 0 {
            return HistoryInsight(id: "disk", kind: .diskFreed,
                                  text: L("Ton disque a libéré \(amount(.fr)) \(period.fr).", "Your disk freed up \(amount(.en)) \(period.en)."),
                                  isWarning: false)
        }
        var cause = L("", "")
        let scans = window.filter { $0.storage != nil }
        if let before = scans.first?.storage, let after = scans.last?.storage, scans.count > 1 {
            let previous = Dictionary(before.map { ($0.id, $0.size) }, uniquingKeysWith: max)
            let grown = after.map { ($0, Int64($0.size) - Int64(previous[$0.id] ?? 0)) }.max { $0.1 < $1.1 }
            if let (mark, growth) = grown, growth >= 1_000_000_000 {
                let size = { (language: Language) in Format.bytes(UInt64(growth), decimal: true, in: language) }
                cause = L(", dont +\(size(.fr)) pour « \(mark.title.fr) »", ", including +\(size(.en)) for “\(mark.title.en)”")
            }
        }
        return HistoryInsight(id: "disk", kind: .diskGrowth,
                              text: L("Ton disque a pris \(amount(.fr)) \(period.fr)\(cause.fr).", "Your disk grew by \(amount(.en)) \(period.en)\(cause.en)."),
                              isWarning: delta >= 10_000_000_000)
    }

    /// « Au rythme actuel, ton disque sera plein dans environ 6 semaines. » (régression sur 30 jours)
    static func forecast(_ points: [HistoryPoint], now: Date) -> HistoryInsight? {
        let window = points.filter { now.timeIntervalSince($0.date) <= 30 * 86_400 }
        guard window.count >= 4, let first = window.first, let last = window.last,
              last.date.timeIntervalSince(first.date) >= 7 * 86_400 else { return nil }
        let xs = window.map { $0.date.timeIntervalSince(first.date) / 86_400 }
        let ys = window.map { Double($0.diskFree) }
        let meanX = xs.reduce(0, +) / Double(xs.count), meanY = ys.reduce(0, +) / Double(ys.count)
        let covariance = zip(xs, ys).reduce(0) { $0 + ($1.0 - meanX) * ($1.1 - meanY) }
        let variance = xs.reduce(0) { $0 + ($1 - meanX) * ($1 - meanX) }
        guard variance > 0 else { return nil }
        let slope = covariance / variance // octets libres par jour
        guard slope < -200_000_000 else { return nil } // moins de 200 Mo par jour : pas une tendance
        let days = Double(last.diskFree) / -slope
        guard days <= 120 else { return nil }
        let text: L
        if days < 14 {
            let count = max(1, Int(days.rounded()))
            text = L("Au rythme actuel, ton disque sera plein dans environ \(count) jour\(count > 1 ? "s" : "").",
                     "At this pace, your disk will be full in about \(count) day\(count > 1 ? "s" : "").")
        } else {
            let weeks = Int((days / 7).rounded())
            text = L("Au rythme actuel, ton disque sera plein dans environ \(weeks) semaines.",
                     "At this pace, your disk will be full in about \(weeks) weeks.")
        }
        return HistoryInsight(id: "forecast", kind: .diskForecast, text: text, isWarning: true)
    }

    enum DayPart: CaseIterable {
        case morning, afternoon, evening, night

        init(_ date: Date) {
            switch Calendar.current.component(.hour, from: date) {
            case 6..<12: self = .morning
            case 12..<18: self = .afternoon
            case 18..<24: self = .evening
            default: self = .night
            }
        }

        var text: L {
            switch self {
            case .morning: return L("le matin", "in the morning")
            case .afternoon: return L("l'après-midi", "in the afternoon")
            case .evening: return L("le soir", "in the evening")
            case .night: return L("la nuit", "at night")
            }
        }
    }

    /// « Slack prend environ 2,1 Go de mémoire l'après-midi. » : les apps lourdes qui reviennent (14 derniers jours).
    static func appMemory(_ points: [HistoryPoint], now: Date) -> [HistoryInsight] {
        let window = points.filter { now.timeIntervalSince($0.date) <= 14 * 86_400 && $0.apps != nil }
        var samples: [String: [(date: Date, memory: UInt64)]] = [:]
        for point in window {
            var perPoint: [String: UInt64] = [:]
            for app in point.apps ?? [] { perPoint[readableName(app.name), default: 0] = max(perPoint[readableName(app.name)] ?? 0, app.memory) }
            for (name, memory) in perPoint { samples[name, default: []].append((point.date, memory)) }
        }
        let calendar = Calendar.current
        var found: [(name: String, typical: UInt64, part: DayPart?)] = []
        for (name, values) in samples {
            let days = Set(values.map { calendar.startOfDay(for: $0.date) })
            guard days.count >= 5 else { continue }
            let sorted = values.map(\.memory).sorted()
            let median = sorted[sorted.count / 2]
            guard median >= 1_500_000_000 else { continue }
            // Le moment de la journée où elle pèse nettement plus qu'en moyenne, s'il y en a un.
            var byPart: [DayPart: [UInt64]] = [:]
            for value in values { byPart[DayPart(value.date), default: []].append(value.memory) }
            let averages = byPart.filter { $0.value.count >= 3 }.mapValues { $0.reduce(0, +) / UInt64($0.count) }
            let top = averages.max { $0.value < $1.value }
            let part = top.flatMap { Double($0.value) >= Double(median) * 1.25 ? $0.key : nil }
            found.append((name, top.map { part != nil ? $0.value : median } ?? median, part))
        }
        return found.sorted { $0.typical > $1.typical }.prefix(3).map { item in
            let size = { (language: Language) in Format.bytes(item.typical, decimal: true, in: language) }
            let when = item.part?.text ?? L("quand elle est ouverte", "when it's open")
            return HistoryInsight(id: "app:" + item.name, kind: .appMemory,
                                  text: L("\(item.name) prend environ \(size(.fr)) de mémoire \(when.fr).",
                                          "\(item.name) uses about \(size(.en)) of memory \(when.en)."),
                                  isWarning: false)
        }
    }
}

// MARK: - Les apps qui prennent le plus de mémoire

public struct HeavyApp: Sendable, Equatable {
    public enum Presence: Sendable, Equatable {
        case almostAlways, often, sometimes

        public var text: L {
            switch self {
            case .almostAlways: return L("presque toujours ouverte", "almost always open")
            case .often: return L("souvent ouverte", "often open")
            case .sometimes: return L("parfois ouverte", "sometimes open")
            }
        }
    }

    public var name: String
    /// Mémoire habituelle (médiane des mesures où elle est ouverte).
    public var typical: UInt64
    /// Le plus haut relevé.
    public var peak: UInt64
    /// nil tant qu'il n'y a pas assez de mesures pour parler d'habitude.
    public var presence: Presence?
}

extension HistoryInsights {
    /// Sous ce nombre de mesures (environ une journée), on ne parle pas encore d'habitudes.
    public static let measuresForHabits = 8

    /// Noms techniques remplacés par ce qu'ils sont.
    static let readableNames: [String: L] = [
        "SimulatorTrampoline": L("Simulateur iPhone (Xcode)", "iPhone Simulator (Xcode)"),
        "com.apple.CoreSimulator.CoreSimulatorService": L("Simulateur iPhone (Xcode)", "iPhone Simulator (Xcode)"),
        "com.apple.CoreSimulator.SimulatorTrampoline": L("Simulateur iPhone (Xcode)", "iPhone Simulator (Xcode)"),
    ]

    public static func readableName(_ name: String, language: Language = Localization.current) -> String {
        if let known = readableNames[name] { return known.text(in: language) }
        // Un identifiant (« com.editeur.app ») : son dernier mot, en capitale.
        if name.contains("."), !name.contains(" "), let last = name.split(separator: ".").last {
            return last.prefix(1).uppercased() + last.dropFirst()
        }
        return name
    }

    /// Les apps les plus lourdes sur la période : chaque app compte une fois par mesure (la plus grosse ligne à son nom).
    public static func heavyApps(_ points: [HistoryPoint], limit: Int = 6) -> [HeavyApp] {
        let measured = points.filter { $0.apps != nil }
        guard !measured.isEmpty else { return [] }
        var values: [String: [UInt64]] = [:]
        for point in measured {
            var perPoint: [String: UInt64] = [:]
            for app in point.apps ?? [] {
                let name = readableName(app.name)
                perPoint[name] = max(perPoint[name] ?? 0, app.memory)
            }
            for (name, memory) in perPoint { values[name, default: []].append(memory) }
        }
        let enough = measured.count >= measuresForHabits
        return values.map { name, list -> HeavyApp in
            let sorted = list.sorted()
            let share = Double(list.count) / Double(measured.count)
            let presence: HeavyApp.Presence? = enough ? (share >= 0.8 ? .almostAlways : share >= 0.4 ? .often : .sometimes) : nil
            return HeavyApp(name: name, typical: sorted[sorted.count / 2], peak: sorted.last ?? 0, presence: presence)
        }
        .sorted { $0.typical > $1.typical }
        .prefix(limit)
        .map { $0 }
    }
}
