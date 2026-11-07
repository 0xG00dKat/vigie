import Foundation
@preconcurrency import UserNotifications
import VigieCore

/// Notification « disque presque plein ». macOS demande l'autorisation la première fois.
@MainActor
enum Notifier {
    static func diskLow(_ disk: DiskStatus, dockerDisk: DockerVirtualDisk?, isTest: Bool = false) {
        // Sans identifiant d'app (binaire lancé hors du paquet .app), le centre de notifications plante.
        guard Bundle.main.bundleIdentifier != nil else { return }
        let content = UNMutableNotificationContent()
        content.title = tr("Disque presque plein", "Disk almost full") + (isTest ? tr(" (test)", " (test)") : "")
        var body = tr(
            "Il reste \(disk.freePercent) % d'espace libre (\(Format.bytes(disk.available, decimal: true))).",
            "Only \(disk.freePercent)% free space left (\(Format.bytes(disk.available, decimal: true)))."
        )
        if let dockerDisk {
            body += " " + tr(
                "Docker en occupe \(Format.bytes(dockerDisk.allocated, decimal: true)) : ouvre Vigie pour voir quoi nettoyer.",
                "Docker uses \(Format.bytes(dockerDisk.allocated, decimal: true)): open Vigie to see what to clean."
            )
        }
        content.body = body
        let request = UNNotificationRequest(identifier: "vigie.disque", content: content, trigger: nil)
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            center.add(request)
        }
    }
}
