import Foundation

/// L'état du Mac en une phrase, avec une seule action : ce que voit d'abord quelqu'un qui n'y connaît rien.
/// Vert : rien à faire. Orange : le disque se remplit. Rouge : presque plein.
public struct MacHealth: Sendable, Equatable {
    public enum Level: Sendable, Equatable {
        case good, attention, critical
    }

    public enum Action: Sendable, Equatable {
        /// Vider sans risque ce montant (récapitulatif avant de confirmer).
        case freeSpace(UInt64)
        /// Pas encore d'analyse récente : la lancer.
        case scan
        /// Quitter l'app qui s'emballe (même confirmation que le bouton × de sa ligne).
        case quit(id: String, name: String)
        /// Montrer les apps qui prennent le plus de mémoire.
        case showMemory
    }

    public var level: Level
    public var title: String
    public var message: String
    public var action: Action?

    /// Sous ce montant, proposer de vider ne vaut pas la peine d'un bouton.
    public static let worthwhileCleanup: UInt64 = 1_000_000_000

    /// `reclaimable` : ce qu'on peut vider sans risque d'après une analyse de moins de 24 h (nil : pas d'analyse).
    public static func evaluate(disk: DiskStatus, reclaimable: UInt64?, language: Language = Localization.current) -> MacHealth {
        let fr = language == .fr
        let free = Format.bytes(disk.available, decimal: true, in: language)
        let level: Level = disk.isLow ? .critical : disk.isTight ? .attention : .good

        var action: Action?
        if let reclaimable {
            if reclaimable >= worthwhileCleanup { action = .freeSpace(reclaimable) }
        } else if level != .good {
            action = .scan
        }
        let cleanup = reclaimable.map { Format.bytes($0, decimal: true, in: language) }

        switch level {
        case .good:
            var message = fr ? "\(free) libres : largement de quoi faire." : "\(free) free: plenty of room."
            if let cleanup, action != nil {
                message += fr ? " Tu peux quand même libérer \(cleanup) sans risque." : " You can still free \(cleanup) safely."
            }
            return MacHealth(level: .good, title: fr ? "Ton Mac va bien" : "Your Mac is fine", message: message, action: action)
        case .attention:
            var message = fr ? "Il reste \(disk.freePercent) % d'espace (\(free))." : "\(disk.freePercent)% of space left (\(free))."
            if let cleanup, action != nil {
                message += fr ? " Tu peux libérer \(cleanup) sans rien perdre." : " You can free \(cleanup) without losing anything."
            } else if action == .scan {
                message += fr ? " Vigie peut chercher ce qui prend de la place." : " Vigie can find what's taking up space."
            }
            return MacHealth(level: .attention, title: fr ? "Ton disque se remplit" : "Your disk is filling up", message: message, action: action)
        case .critical:
            var message = fr ? "Il ne reste que \(disk.freePercent) % (\(free)) : ton Mac peut ralentir et les mises à jour échouer."
                             : "Only \(disk.freePercent)% left (\(free)): your Mac may slow down and updates may fail."
            if let cleanup, action != nil {
                message += fr ? " Libère \(cleanup) sans risque." : " Free \(cleanup) safely."
            }
            return MacHealth(level: .critical, title: fr ? "Disque presque plein" : "Disk almost full", message: message, action: action)
        }
    }

    /// Texte du bouton principal.
    public func actionTitle(language: Language = Localization.current) -> String? {
        let fr = language == .fr
        switch action {
        case .freeSpace(let amount)?:
            let size = Format.bytes(amount, decimal: true, in: language)
            return fr ? "Libérer \(size) sans risque" : "Free \(size) safely"
        case .scan?:
            return fr ? "Chercher ce qui prend de la place" : "Find what's taking up space"
        case .quit(_, let name)?:
            return fr ? "Quitter \(name)" : "Quit \(name)"
        case .showMemory?:
            return fr ? "Voir ce qui prend de la mémoire" : "See what's using memory"
        case nil:
            return nil
        }
    }
}
