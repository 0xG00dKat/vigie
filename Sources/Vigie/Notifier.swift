import Foundation
@preconcurrency import UserNotifications
import VigieCore

/// Notifications de Vigie : disque presque plein, et alertes de vitesse (avec un bouton « Quitter »).
/// macOS demande l'autorisation la première fois.
@MainActor
enum Notifier {
    static var onQuit: ((String) -> Void)?
    private static let delegate = NotificationDelegate()
    private static let appCategory = "vigie.app"

    /// À appeler au lancement : le bouton « Quitter » des notifications, et leur affichage même app au premier plan.
    static func configure(onQuit: @escaping (String) -> Void) {
        guard Bundle.main.bundleIdentifier != nil else { return }
        self.onQuit = onQuit
        let center = UNUserNotificationCenter.current()
        center.delegate = delegate
        let quit = UNNotificationAction(identifier: "quitter", title: tr("Quitter", "Quit"), options: [.destructive])
        center.setNotificationCategories([UNNotificationCategory(identifier: appCategory, actions: [quit], intentIdentifiers: [])])
    }

    static func checkPermission(_ completion: @escaping @MainActor (Bool) -> Void) {
        guard Bundle.main.bundleIdentifier != nil else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            Task { @MainActor in completion(granted) }
        }
    }

    static func speed(_ alert: SpeedAlert) {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let content = UNMutableNotificationContent()
        content.title = alert.title
        content.body = alert.body
        if let id = alert.quitGroupID {
            content.categoryIdentifier = appCategory
            content.userInfo = ["groupe": id]
        }
        let request = UNNotificationRequest(identifier: "vigie.vitesse." + alert.key, content: content, trigger: nil)
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            center.add(request)
        }
    }

    /// Notification d'une règle de l'utilisateur ; avec un bouton « Quitter » si `quitGroupID` est donné.
    static func message(id: String, title: String, body: String, quitGroupID: String?) {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        if let quitGroupID {
            content.categoryIdentifier = appCategory
            content.userInfo = ["groupe": quitGroupID]
        }
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            center.add(request)
        }
    }

    static func diskLow(_ disk: DiskStatus, dockerDisk: DockerVirtualDisk?, diagnosis: DiskDiagnosis?, isTest: Bool = false) {
        // Sans identifiant d'app (binaire lancé hors du paquet .app), le centre de notifications plante.
        guard Bundle.main.bundleIdentifier != nil else { return }
        let content = UNMutableNotificationContent()
        content.title = tr("Disque presque plein", "Disk almost full") + (isTest ? tr(" (test)", " (test)") : "")
        var body = tr(
            "Il reste \(disk.freePercent) % d'espace libre (\(Format.bytes(disk.available, decimal: true))).",
            "Only \(disk.freePercent)% free space left (\(Format.bytes(disk.available, decimal: true)))."
        )
        // Ce qui a grossi d'abord (le « pourquoi »), puis quoi vider.
        let lines = [diagnosis?.growthLine(), diagnosis?.reclaimableLine()].compactMap { $0 }
        if !lines.isEmpty {
            body += "\n" + lines.joined(separator: "\n")
        } else if let dockerDisk {
            body += " " + tr(
                "Docker en occupe \(Format.bytes(dockerDisk.allocated, decimal: true)) : ouvre Vigie pour voir quoi nettoyer.",
                "Docker uses \(Format.bytes(dockerDisk.allocated, decimal: true)): open Vigie to see what to clean."
            )
        }
        if diagnosis == nil {
            body += " " + tr("Ouvre Vigie › Stockage pour voir ce qui prend de la place.", "Open Vigie › Storage to see what's taking up space.")
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

/// Reçoit le clic sur « Quitter » d'une notification.
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        if response.actionIdentifier == "quitter", let id = response.notification.request.content.userInfo["groupe"] as? String {
            Task { @MainActor in Notifier.onQuit?(id) }
        }
        completionHandler()
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
