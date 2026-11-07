import Foundation

/// Espace du disque de démarrage. Mesure stricte (comme `df`) : n'inclut pas l'espace « purgeable »
/// que macOS pourrait libérer, pour ne jamais surestimer la place disponible.
public struct DiskStatus: Sendable, Equatable {
    public var available: UInt64
    public var total: UInt64

    /// Sous ce seuil, Vigie prévient.
    public static let lowThreshold = 0.15
    /// Au-dessus de ce seuil, l'alerte est réarmée (évite d'alerter en boucle autour de 15 %).
    public static let recoveredThreshold = 0.17

    public init(available: UInt64, total: UInt64) {
        self.available = available
        self.total = total
    }

    public var freeRatio: Double { total > 0 ? Double(available) / Double(total) : 1 }
    public var isLow: Bool { freeRatio < Self.lowThreshold }
    public var isTight: Bool { freeRatio < 0.25 }
    public var freePercent: Int { Int((freeRatio * 100).rounded(.down)) }
}

public enum DiskReader {
    public static func read(path: String = "/") -> DiskStatus? {
        let keys: Set<URLResourceKey> = [.volumeTotalCapacityKey, .volumeAvailableCapacityKey]
        guard let values = try? URL(fileURLWithPath: path).resourceValues(forKeys: keys),
              let total = values.volumeTotalCapacity, let available = values.volumeAvailableCapacity,
              total > 0 else { return nil }
        return DiskStatus(available: UInt64(max(0, available)), total: UInt64(total))
    }
}

/// Décide quand envoyer la notification : une fois au passage sous 15 %, puis plus rien
/// tant que l'espace libre n'est pas remonté au-dessus de 17 %.
public struct DiskAlertState: Sendable, Equatable {
    public private(set) var alerted = false

    public init(alerted: Bool = false) {
        self.alerted = alerted
    }

    /// Renvoie vrai quand il faut prévenir maintenant.
    public mutating func update(with status: DiskStatus) -> Bool {
        if status.isLow && !alerted {
            alerted = true
            return true
        }
        if alerted && status.freeRatio > DiskStatus.recoveredThreshold {
            alerted = false
        }
        return false
    }
}
