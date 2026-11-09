import Foundation

/// Des règles simples, créées par l'utilisateur et gardées sur le Mac :
/// « préviens-moi si Slack dépasse 4 Go de mémoire », « quitte Slack à 19 h ».
///
/// Garde-fous : une alerte part une fois par dépassement (elle se réarme quand l'app redescend sous 90 % du seuil) ;
/// une fermeture est normale (comme ⌘Q, l'app peut demander d'enregistrer), jamais forcée, et jamais pour une app
/// protégée (Finder, Dock, Centre de contrôle, Vigie, macOS, autres utilisateurs).
public struct VigieRule: Codable, Sendable, Equatable, Identifiable {
    public enum Kind: Codable, Sendable, Equatable {
        /// Prévenir quand l'app dépasse ce nombre d'octets de mémoire.
        case memoryAbove(bytes: UInt64)
        /// Quitter l'app chaque jour à cette heure.
        case quitAt(hour: Int, minute: Int)
    }

    public var id: UUID
    /// Nom de l'app, tel que Vigie l'affiche (« Slack »).
    public var appName: String
    /// Identifiant de l'app quand on le connaît (plus sûr que le nom).
    public var bundleID: String?
    public var kind: Kind
    public var isEnabled: Bool

    public init(id: UUID = UUID(), appName: String, bundleID: String? = nil, kind: Kind, isEnabled: Bool = true) {
        self.id = id
        self.appName = appName
        self.bundleID = bundleID
        self.kind = kind
        self.isEnabled = isEnabled
    }

    /// « Me prévenir si Slack dépasse 4 Go de mémoire », « Quitter Slack à 19:00 ».
    public var summary: L {
        switch kind {
        case .memoryAbove(let bytes):
            let fr = Format.bytes(bytes, decimal: true, in: .fr), en = Format.bytes(bytes, decimal: true, in: .en)
            return L("Me prévenir si \(appName) dépasse \(fr) de mémoire", "Warn me if \(appName) goes over \(en) of memory")
        case .quitAt(let hour, let minute):
            let time = String(format: "%02d:%02d", hour, minute)
            return L("Quitter \(appName) chaque jour à \(time)", "Quit \(appName) every day at \(time)")
        }
    }

    /// Le groupe de Vigie qui correspond à l'app (par identifiant, sinon par nom).
    public func match(in groups: [ProcessGroup]) -> ProcessGroup? {
        let candidates = groups.filter { $0.category == .apps || $0.category == .background }
        if let bundleID, let group = candidates.first(where: { $0.bundleID == bundleID }) { return group }
        return candidates.first { $0.title.localizedCaseInsensitiveCompare(appName) == .orderedSame }
    }
}

public enum RuleEngine {
    /// En dessous de 90 % du seuil, l'alerte se réarme : pas de notification en boucle autour du seuil.
    static let rearmRatio = 0.9

    public struct MemoryAlert: Sendable, Equatable {
        public var rule: VigieRule
        public var group: ProcessGroup.ID
        public var memory: UInt64

        public var title: String { tr("\(rule.appName) prend beaucoup de mémoire", "\(rule.appName) is using a lot of memory") }
        public var body: String {
            guard case .memoryAbove(let limit) = rule.kind else { return "" }
            return tr("\(Format.bytes(memory, decimal: true)), au-dessus de ta limite de \(Format.bytes(limit, decimal: true)). La quitter libère cette mémoire.",
                      "\(Format.bytes(memory, decimal: true)), above your \(Format.bytes(limit, decimal: true)) limit. Quitting it frees that memory.")
        }
    }

    /// Alertes à envoyer maintenant. `alerted` : les règles déjà signalées et pas encore redescendues (mis à jour).
    public static func memoryAlerts(rules: [VigieRule], groups: [ProcessGroup], alerted: inout Set<UUID>) -> [MemoryAlert] {
        var alerts: [MemoryAlert] = []
        for rule in rules where rule.isEnabled {
            guard case .memoryAbove(let limit) = rule.kind else { continue }
            guard let group = rule.match(in: groups) else {
                alerted.remove(rule.id) // app fermée : la règle se réarme
                continue
            }
            if group.memory > limit {
                if alerted.insert(rule.id).inserted { alerts.append(MemoryAlert(rule: rule, group: group.id, memory: group.memory)) }
            } else if Double(group.memory) < Double(limit) * rearmRatio {
                alerted.remove(rule.id)
            }
        }
        return alerts
    }

    /// L'heure d'une règle « quitter à » est passée entre deux vérifications (même si le Mac dormait un peu).
    /// Au-delà d'une heure de retard (Mac en veille toute la soirée), on ne quitte plus : ce serait une surprise.
    public static func quitIsDue(_ rule: VigieRule, lastCheck: Date, now: Date, calendar: Calendar = .current) -> Bool {
        guard rule.isEnabled, case .quitAt(let hour, let minute) = rule.kind, now > lastCheck else { return false }
        guard let today = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: now) else { return false }
        return today > lastCheck && today <= now && now.timeIntervalSince(today) <= 3600
    }

    /// Prochaine fois qu'une règle « quitter à » se déclenchera.
    public static func nextQuit(_ rule: VigieRule, after date: Date, calendar: Calendar = .current) -> Date? {
        guard case .quitAt(let hour, let minute) = rule.kind else { return nil }
        return calendar.nextDate(after: date, matching: DateComponents(hour: hour, minute: minute, second: 0), matchingPolicy: .nextTime)
    }

    /// Une règle peut fermer ce groupe : une app ou un utilitaire de l'utilisateur, ni protégé ni de macOS.
    public static func canQuit(_ group: ProcessGroup) -> Bool {
        group.category != .system && !group.isProtected && group.close.isAllowed
    }
}

public enum RuleStore {
    public static let key = "reglesVigie"

    public static func load(_ defaults: UserDefaults = .standard) -> [VigieRule] {
        guard let data = defaults.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([VigieRule].self, from: data)) ?? []
    }

    public static func save(_ rules: [VigieRule], _ defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(rules) { defaults.set(data, forKey: key) }
    }
}
