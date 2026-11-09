import Foundation

/// Ce que l'alerte « disque presque plein » dit en plus du pourcentage : quoi vider en priorité,
/// et ce qui a grossi depuis l'analyse précédente (souvent la vraie raison : une image Docker,
/// des compilations, un modèle d'IA téléchargé).
public struct DiskDiagnosis: Sendable, Equatable {
    public struct Item: Sendable, Equatable {
        public var title: L
        public var size: UInt64
    }

    public struct Growth: Sendable, Equatable {
        public var title: L
        /// Place prise depuis l'analyse précédente.
        public var increase: UInt64
        public var size: UInt64
        /// Absent de l'analyse précédente (nouveau projet, nouveau gros fichier…).
        public var isNew: Bool
        /// Sous-dossier qui a le plus grossi (« uv » dans les caches des outils de dev).
        public var mainly: L?
    }

    public var reclaimable: [Item]
    public var growth: [Growth]
    /// Date de l'analyse de référence (nil : pas d'analyse précédente).
    public var comparedTo: Date?

    /// Croissance minimale pour être citée : en dessous, c'est le bruit normal des caches.
    public static let minimumGrowth: UInt64 = 500_000_000

    public static func make(report: StorageReport, previous: StorageReport?, limit: Int = 3) -> DiskDiagnosis {
        // À vider : les plus gros caches, et les node_modules ensemble (une ligne par projet serait trop longue).
        var reclaimable = report.entries(of: .cache).map { Item(title: $0.title, size: $0.size) }
        let projects = report.entries(of: .project)
        if !projects.isEmpty {
            let total = projects.reduce(UInt64(0)) { $0 + $1.size }
            reclaimable.append(Item(title: L("node_modules de \(projects.count) projet\(projects.count > 1 ? "s" : "")",
                                             "node_modules of \(projects.count) project\(projects.count > 1 ? "s" : "")"),
                                    size: total))
        }
        reclaimable = Array(reclaimable.filter { $0.size > 0 }.sorted { $0.size > $1.size }.prefix(limit))

        guard let previous, previous.date < report.date else {
            return DiskDiagnosis(reclaimable: reclaimable, growth: [], comparedTo: nil)
        }
        let before = Dictionary(previous.entries.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var growth: [Growth] = []
        for entry in report.entries where !entry.isProtected {
            let old = before[entry.id]
            let oldSize = old?.size ?? 0
            guard entry.size > oldSize, entry.size - oldSize >= minimumGrowth else { continue }
            // Le sous-dossier qui a le plus grossi, s'il explique au moins la moitié de la hausse.
            let oldChildren = Dictionary((old?.children ?? []).map { ($0.id, $0.size) }, uniquingKeysWith: { first, _ in first })
            let increase = entry.size - oldSize
            let mainly = entry.children
                .map { ($0.title, $0.size > (oldChildren[$0.id] ?? 0) ? $0.size - (oldChildren[$0.id] ?? 0) : 0) }
                .max { $0.1 < $1.1 }
                .flatMap { $0.1 * 2 >= increase ? $0.0 : nil }
            growth.append(Growth(title: entry.title, increase: increase, size: entry.size, isNew: old == nil, mainly: mainly))
        }
        growth = Array(growth.sorted { $0.increase > $1.increase }.prefix(limit))
        return DiskDiagnosis(reclaimable: reclaimable, growth: growth, comparedTo: previous.date)
    }

    /// « À vider en priorité : … »
    public func reclaimableLine(in language: Language = Localization.current) -> String? {
        guard !reclaimable.isEmpty else { return nil }
        let items = reclaimable.map { "\($0.title.text(in: language)) \(Format.bytes($0.size, decimal: true, in: language))" }
        return (language == .fr ? "À vider en priorité : " : "Clear first: ") + items.joined(separator: ", ") + "."
    }

    /// « A grossi depuis 3 jours : Docker +8 Go (surtout Disque virtuel de Docker), … »
    public func growthLine(in language: Language = Localization.current, now: Date = Date()) -> String? {
        guard !growth.isEmpty, let comparedTo else { return nil }
        let french = language == .fr
        let items = growth.map { item -> String in
            var text = "\(item.title.text(in: language)) +\(Format.bytes(item.increase, decimal: true, in: language))"
            if item.isNew {
                text += french ? " (nouveau)" : " (new)"
            } else if let mainly = item.mainly {
                text += french ? " (surtout \(mainly.text(in: language)))" : " (mostly \(mainly.text(in: language)))"
            }
            return text
        }
        return (french ? "A grossi " : "Grew ") + Self.since(comparedTo, in: language, now: now) + (french ? " : " : ": ")
            + items.joined(separator: ", ") + "."
    }

    /// « depuis hier », « depuis 3 jours », « depuis 5 h ».
    static func since(_ date: Date, in language: Language, now: Date) -> String {
        let hours = max(1, Int(now.timeIntervalSince(date) / 3600))
        let days = hours / 24
        if language == .fr {
            if hours < 24 { return "depuis \(hours) h" }
            if days == 1 { return "depuis hier" }
            return "depuis \(days) jours"
        }
        if hours < 24 { return "in the last \(hours) h" }
        if days == 1 { return "since yesterday" }
        return "in the last \(days) days"
    }
}
