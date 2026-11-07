import AppKit
import SwiftUI
@preconcurrency import UserNotifications
import VigieCore

@main
enum Main {
    @MainActor
    static func main() {
        let arguments = CommandLine.arguments
        if arguments.contains("--dump") {
            // Les modes de vérification suivent le réglage de langue, comme l'app.
            Localization.current = LanguageSetting.stored.resolved
            Debug.dump(all: arguments.contains("--all"))
            Debug.dumpDiskAndDocker()
            return
        }
        if let index = arguments.firstIndex(of: "--render"), index + 1 < arguments.count {
            Debug.render(to: arguments[index + 1], options: Array(arguments[(index + 2)...]))
            return
        }
        if let index = arguments.firstIndex(of: "--debug-close"), index + 1 < arguments.count {
            Debug.close(title: arguments[index + 1], patient: arguments.contains("--patient"))
            return
        }
        if arguments.contains("--debug-update") {
            Debug.update(arguments: arguments)
            return
        }
        if arguments.contains("--debug-notify") {
            Debug.notifyTest()
            return
        }
        if let index = arguments.firstIndex(of: "--debug-ask"), index + 1 < arguments.count {
            Debug.ask(title: arguments[index + 1])
            return
        }
        // `Vigie --login-item on|off|status` : même réglage que la case « Ouvrir au démarrage ».
        if let index = arguments.firstIndex(of: "--login-item") {
            let action = index + 1 < arguments.count ? arguments[index + 1] : "status"
            do {
                if action == "on" { try LoginItem.set(true) }
                if action == "off" { try LoginItem.set(false) }
            } catch {
                print("Erreur : \(error.localizedDescription)")
            }
            print("Ouverture au démarrage : \(LoginItem.state)")
            return
        }
        VigieApp.main()
    }
}

struct VigieApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            MainPanel()
                .environment(model)
        } label: {
            MenuBarLabel(model: model)
        }
        .menuBarExtraStyle(.window)
    }
}

/// L'œil de Vigie en modèle monochrome (macOS le colore selon la barre des menus).
/// Hors du paquet .app (lancement via `swift run`), repli sur un symbole système.
enum MenuBarIcon {
    static let image: NSImage = {
        if let image = Bundle.main.image(forResource: "MenuBarIcon") {
            image.isTemplate = true
            return image
        }
        let fallback = NSImage(systemSymbolName: "eye", accessibilityDescription: "Vigie") ?? NSImage()
        fallback.isTemplate = true
        return fallback
    }()
}

/// Modes de vérification en ligne de commande (utilisés pendant le développement).
@MainActor
enum Debug {
    /// `Vigie --dump [--all]` : affiche les groupes en texte.
    static func dump(all: Bool) {
        let sampler = ProcessSampler()
        _ = sampler.snapshot()
        Thread.sleep(forTimeInterval: 1)
        let snapshot = SnapshotBuilder.capture(sampler: sampler, runningApps: RunningApps.current(), ownBundleID: Bundle.main.bundleIdentifier)
        print("\(Format.processes(snapshot.processCount)) · RAM \(Format.bytes(snapshot.memoryUsed)) / \(Format.bytes(snapshot.memoryTotal))")
        for category in ProcessCategory.allCases {
            let groups = snapshot.groups(in: category)
            let processes = groups.reduce(0) { $0 + $1.processes.count }
            print("\n== \(category.title) : \(groups.count) groupes, \(processes) processus")
            for group in groups.prefix(all || category != .system ? groups.count : 25) {
                var meta = [Format.processes(group.processes.count), Format.bytes(group.memory)]
                if let cpu = Format.cpu(group.cpuPercent) { meta.append(cpu) }
                if !group.ports.isEmpty { meta.append("ports " + group.ports.map(String.init).joined(separator: ",")) }
                if let start = group.startTime { meta.append(Format.uptime(since: start)) }
                if let launcher = group.launchedBy { meta.append("lancé par " + launcher) }
                if group.isOrphan { meta.append("sans app parente") }
                let close: String
                switch group.close {
                case .quitApps(let pids): close = "quitter app \(pids)"
                case .signal(let pids): close = "SIGTERM ×\(pids.count)"
                case .notAllowed(let reason): close = "non : \(reason)"
                }
                print("  \(group.title) — \(meta.joined(separator: " · ")) — [\(close)]\(group.isProtected ? " 🔒" : "")")
                print("      \(group.explanation.text)\(group.explanation.isGeneric ? "  (générique)" : "")")
                if let location = group.location, category == .dev { print("      \(location)") }
                if category == .dev {
                    for process in group.processes.prefix(6) {
                        print("        · \(process.name) [\(process.pid)] \(Format.cpu(process.cpuPercent ?? 0) ?? "") \(Explainer.commandSummary(process)?.prefix(90) ?? "")")
                    }
                }
            }
        }
    }

    static func dumpDiskAndDocker() {
        if let disk = DiskReader.read() {
            print("\n== Disque : \(Format.bytes(disk.available, decimal: true)) libres sur \(Format.bytes(disk.total, decimal: true)) (\(disk.freePercent) %)\(disk.isLow ? " — ALERTE" : "")")
        }
        let docker = DockerReader.read()
        print("== Docker : \(docker.state)")
        if let virtual = docker.virtualDisk {
            print("   disque virtuel \(virtual.engine) : \(Format.bytes(virtual.allocated, decimal: true)) occupés (max \(Format.bytes(virtual.maximum, decimal: true)))")
        }
        for group in docker.groups {
            print("   \(group.title) — \(group.containers.count) conteneur(s) · \(Format.bytes(group.memory)) · ports \(group.ports)")
        }
        if let usage = docker.disk {
            print("   images \(Format.bytes(usage.images.size, decimal: true)), volumes \(Format.bytes(usage.volumes.size, decimal: true)), cache \(Format.bytes(usage.buildCache.size, decimal: true))")
        }
    }

    /// `Vigie --render fichier.png [--dark] [--query texte] [--expand titre]… [--open-system]` :
    /// dessine le panneau dans une image, sans passer par la barre des menus.
    static func render(to path: String, options: [String]) {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)

        let model = AppModel(startImmediately: false)
        // `--lang fr|en` : langue de la capture, sans toucher au réglage enregistré.
        if let index = options.firstIndex(of: "--lang"), index + 1 < options.count,
           let setting = LanguageSetting(rawValue: options[index + 1]) {
            model.setLanguage(setting, persist: false, reload: false)
        }
        if options.contains("--demo") {
            model.loadDemo(diskLow: options.contains("--demo-disk-low"))
        } else {
            model.refreshNow()
            Thread.sleep(forTimeInterval: 1)
            model.refreshNow()
        }

        var index = 0
        while index < options.count {
            let option = options[index]
            let value = index + 1 < options.count ? options[index + 1] : ""
            switch option {
            case "--lang":
                index += 1
            case "--switch-lang":
                // Même chemin que le menu ⚙︎ : changement à chaud, données rechargées.
                if let setting = LanguageSetting(rawValue: value) {
                    model.setLanguage(setting, persist: false, reload: true)
                }
                index += 1
            case "--query":
                model.query = value
                index += 1
            case "--expand":
                for category in ProcessCategory.allCases {
                    for group in model.visibleGroups(in: category) where group.title.localizedCaseInsensitiveCompare(value) == .orderedSame {
                        model.expandedGroups.insert(group.id)
                    }
                }
                for group in model.visibleDockerGroups where group.title.localizedCaseInsensitiveCompare(value) == .orderedSame {
                    model.expandedGroups.insert(group.id)
                }
                index += 1
            case "--demo-update":
                // Bandeau « nouvelle version » avec une version fictive, pour les captures.
                model.showDemoUpdate()
            case "--open-system":
                model.collapsedSections.remove(.system)
            case "--collapse":
                if let category = ProcessCategory(rawValue: value) { model.collapsedSections.insert(category) }
                index += 1
            case "--confirm":
                for category in ProcessCategory.allCases {
                    for group in model.visibleGroups(in: category) where group.title.localizedCaseInsensitiveCompare(value) == .orderedSame {
                        model.requestConfirmation(group.id)
                    }
                }
                index += 1
            default:
                break
            }
            index += 1
        }

        let root = MainPanel()
            .environment(model)
            .background(Color(nsColor: .windowBackgroundColor))
        let host = NSHostingView(rootView: root)
        host.frame = NSRect(x: 0, y: 0, width: 460, height: 640)
        if options.contains("--dark") {
            host.appearance = NSAppearance(named: .darkAqua)
        } else {
            host.appearance = NSAppearance(named: .aqua)
        }
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        window.setFrameOrigin(NSPoint(x: -4000, y: -4000))
        window.orderFrontRegardless()

        RunLoop.main.run(until: Date().addingTimeInterval(1.5))
        host.layoutSubtreeIfNeeded()
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
            print("Échec du rendu")
            return
        }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else { return }
        do {
            try data.write(to: URL(fileURLWithPath: path))
            print("Image écrite : \(path)")
        } catch {
            print("Échec de l'écriture : \(error.localizedDescription)")
        }
    }

    /// `Vigie --debug-ask Titre` : pose la question à Claude comme le bouton « Demander à Claude ».
    static func ask(title: String) {
        let model = AppModel(startImmediately: false)
        model.refreshNow()
        let groups = ProcessCategory.allCases.flatMap { model.visibleGroups(in: $0) }
        guard let group = groups.first(where: { $0.title.localizedCaseInsensitiveCompare(title) == .orderedSame }) else {
            print("Aucun groupe « \(title) »")
            return
        }
        let subject = ClaudeExplainer.subject(for: group)
        print("Question envoyée :\n\(subject.prompt)\n")
        var done = false
        Task {
            do {
                let answer = try await ClaudeExplainer.explain(subject)
                ExplanationCache.shared.set(answer, for: subject.key)
                print("Réponse :\n\(answer)")
            } catch {
                print("Erreur : \(error.localizedDescription)")
            }
            done = true
        }
        let deadline = Date().addingTimeInterval(100)
        while !done, Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        }
    }

    /// `Vigie --debug-update [--repo propriétaire/dépôt] [--pretend-version x.y.z]` :
    /// la même vérification que le bouton « Rechercher une mise à jour ».
    static func update(arguments: [String]) {
        func value(_ flag: String) -> String? {
            arguments.firstIndex(of: flag).flatMap { $0 + 1 < arguments.count ? arguments[$0 + 1] : nil }
        }
        let repository = value("--repo") ?? (Bundle.main.object(forInfoDictionaryKey: "VigieUpdateRepository") as? String ?? UpdateChecker.defaultRepository)
        let versionText = value("--pretend-version") ?? (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0")
        guard let current = Version(versionText) else {
            print("Version illisible : \(versionText)")
            return
        }
        print("Dépôt : \(repository) · version actuelle : \(current)")
        var done = false
        Task {
            do {
                switch try await UpdateChecker.check(current: current, repository: repository) {
                case .available(let release):
                    print("Mise à jour disponible : \(release.version) (« \(release.name) »)")
                    print("  page : \(release.pageURL)")
                    print("  téléchargement : \(release.downloadURL?.absoluteString ?? "aucun .zip joint")")
                    print("  résumé : \(release.summary)")
                case .upToDate(let latest):
                    print(latest.map { "À jour (dernière version publiée : \($0))" } ?? "À jour : aucune version publiée sur ce dépôt")
                }
            } catch {
                print("Échec : \(error.localizedDescription)")
            }
            done = true
        }
        let deadline = Date().addingTimeInterval(30)
        while !done, Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        }
    }

    /// `Vigie --debug-notify` : envoie la notification « disque presque plein », marquée comme test.
    static func notifyTest() {
        let center = UNUserNotificationCenter.current()
        Notifier.diskLow(DemoData.disk(low: true), dockerDisk: DockerReader.findVirtualDisk(), isTest: true)
        print("Notification demandée ; en attente de ta réponse à macOS (60 s au plus)…")
        let deadline = Date().addingTimeInterval(60)
        var result = ""
        while result.isEmpty, Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.5))
            let done = DispatchSemaphore(value: 0)
            center.getNotificationSettings { settings in
                switch settings.authorizationStatus {
                case .authorized, .provisional:
                    center.getDeliveredNotifications { delivered in
                        if delivered.contains(where: { $0.request.identifier == "vigie.disque" }) {
                            result = "autorisée et affichée"
                        }
                        done.signal()
                    }
                    return
                case .denied:
                    result = "refusée par l'utilisateur"
                default:
                    break
                }
                done.signal()
            }
            done.wait()
        }
        print("Notification : \(result.isEmpty ? "pas de réponse dans les 60 s" : result)")
    }

    /// `Vigie --debug-close Titre` : ferme le groupe portant ce titre avec la même logique que le bouton.
    static func close(title: String, patient: Bool = false) {
        let model = AppModel(startImmediately: false)
        model.refreshNow()
        let groups = ProcessCategory.allCases.flatMap { model.visibleGroups(in: $0) }
        // Groupe Docker : même appel que le bouton (`docker stop`).
        if let dockerGroup = model.visibleDockerGroups.first(where: { $0.title.localizedCaseInsensitiveCompare(title) == .orderedSame }) {
            let ids = dockerGroup.containers.map(\.id)
            print("Groupe Docker : \(dockerGroup.title) · \(ids.count) conteneur(s) · docker stop")
            print(DockerReader.stop(ids) ? "Arrêtés : \(dockerGroup.containers.map(\.name))" : "Échec de docker stop")
            return
        }
        guard let group = groups.first(where: { $0.title.localizedCaseInsensitiveCompare(title) == .orderedSame }) else {
            print("Aucun groupe « \(title) »")
            return
        }
        print("Groupe : \(group.title) (\(group.category.title)) · méthode : \(group.close)")
        guard group.close.isAllowed, !group.isProtected else {
            print("Fermeture refusée par Vigie.")
            return
        }
        let pids = Closer.perform(group.close)
        func wait(_ seconds: TimeInterval) {
            let deadline = Date().addingTimeInterval(seconds)
            while Date() < deadline, pids.contains(where: ProcessSignals.isAlive) {
                RunLoop.main.run(until: Date().addingTimeInterval(0.25))
            }
        }
        // `--patient` : attendre jusqu'à 90 s sans jamais forcer (Docker Desktop arrête sa machine virtuelle).
        wait(patient ? 90 : 6)
        var alive = pids.filter(ProcessSignals.isAlive)
        if !alive.isEmpty && patient {
            print("Toujours en vie après 90 s, sans forcer : \(alive)")
            return
        }
        if !alive.isEmpty {
            // Même suite que le bouton « Forcer » qui apparaît après 5 s.
            print("Toujours en vie après 6 s : \(alive) → Forcer")
            Closer.force(alive)
            wait(3)
            alive = pids.filter(ProcessSignals.isAlive)
        }
        print(alive.isEmpty ? "Fermé : \(pids)" : "Toujours en vie : \(alive)")
    }
}
