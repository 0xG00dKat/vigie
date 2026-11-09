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
        if let index = arguments.firstIndex(of: "--intro-preview") {
            IntroPreview.run(soundsFolder: index + 1 < arguments.count ? arguments[index + 1] : nil)
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
        if let index = arguments.firstIndex(of: "--compare-du") {
            Debug.compareDu(Array(arguments.dropFirst(index + 1)))
            return
        }
        if let index = arguments.firstIndex(of: "--dump-explorer") {
            // Ce que montre l'explorateur pour un dossier (le dossier personnel par défaut), avec la durée de la mesure.
            let path = index + 1 < arguments.count ? arguments[index + 1] : NSHomeDirectory()
            let start = Date()
            var request = DiskUsage.Request(path: path)
            request.recordDepth = 3
            let result = DiskUsage.measure([request])[0]
            print(String(format: "Mesure en %.1f s · %d dossiers mémorisés", Date().timeIntervalSince(start), result.directorySizes.count))
            if let listing = FolderListing.make(path: path, from: result, root: path) {
                print("\(Format.bytes(listing.size, decimal: true)) · \(listing.items.count) éléments")
                for item in listing.items.prefix(12) { print("  \(Format.bytes(item.size, decimal: true).padding(toLength: 9, withPad: " ", startingAt: 0)) \(item.name)") }
            }
            return
        }
        if arguments.contains("--dump-startup") {
            // Ce qui démarre avec le Mac, tel que Vigie le voit.
            for item in StartupReader.read() {
                let state = item.isRunning ? "en marche" : item.isEnabled ? "arrêté" : "désactivé"
                print("\(item.displayName.padding(toLength: 30, withPad: " ", startingAt: 0)) \(state.padding(toLength: 10, withPad: " ", startingAt: 0)) \(item.scope) · \(item.canToggle ? "coupable" : "Réglages") · \(item.label)")
            }
            return
        }
        if arguments.contains("--dump-speed") {
            // Ce que Vigie lit pour « Vitesse et batterie », sur ce Mac.
            let status = PerformanceReader.read()
            print("Mémoire : pression \(status.memory.pressure) · rangé sur le disque \(Format.bytes(status.memory.swapUsed, decimal: true))")
            print("Chaleur : \(status.thermal)")
            if let battery = status.battery {
                print("Batterie : \(battery.percent) % · en charge \(battery.charging) · branché \(battery.onPower) · reste \(battery.minutesRemaining.map { "\($0) min" } ?? "?") · santé \(battery.health.map { "\($0) %" } ?? "?") · \(battery.cycles ?? 0) cycles")
            } else {
                print("Batterie : aucune (Mac de bureau)")
            }
            for blocker in status.blockers {
                print("Veille empêchée : \(blocker.name) (\(blocker.kind), « \(blocker.reason) », \(blocker.seconds) s)\(blocker.isSystem ? " · macOS" : "")")
            }
            return
        }
        if arguments.contains("--dump-toolchains") {
            // Versions de Node, Python, Ruby, paquets npm globaux et volumes Docker orphelins (rien n'est touché).
            let start = Date()
            let versions = Toolchains.measure(Toolchains.find())
            let trashable = Set(Toolchains.trashable(versions).map(\.path))
            for version in versions {
                var flags: [String] = []
                if version.isDefault { flags.append("par défaut") }
                if version.inUse { flags.append("en cours") }
                if !version.usedBy.isEmpty { flags.append("projets " + version.usedBy.joined(separator: ",")) }
                if trashable.contains(version.path) { flags.append("CORBEILLE") }
                if let command = version.command { flags.append(command) }
                print("\(version.runtime.title) \(version.version) · \(version.manager) · \(Format.bytes(version.size, decimal: true)) · \(flags.joined(separator: " · "))")
            }
            for package in Toolchains.globalPackages(versions: versions) {
                print("npm -g \(package.name) · \(package.owner) · \(Format.bytes(package.size, decimal: true))")
            }
            for volume in DockerReader.orphanVolumes() {
                print("volume \(volume.isAnonymous ? "anonyme" : volume.project ?? "?") · \(Format.bytes(volume.size, decimal: true)) · \(volume.name.prefix(24))")
            }
            print("en \(String(format: "%.1f", Date().timeIntervalSince(start))) s")
            return
        }
        if arguments.contains("--dump-dormant") {
            // Projets endormis d'après la dernière analyse gardée (aucune nouvelle analyse, rien n'est touché).
            guard let report = StorageReportStore.loadAny(from: StorageReportStore.defaultURL) else { print("Pas d'analyse gardée"); return }
            let start = Date()
            let dormant = DormantProjects.find(in: report)
            for project in dormant {
                print("\(Format.bytes(project.size, decimal: true).padding(toLength: 9, withPad: " ", startingAt: 0)) \(project.title.fr) · \(project.modified.map { Format.ago($0, in: .fr) } ?? "?") · \(project.children.map { PathRules.lastComponent($0.path) }.joined(separator: ", "))")
            }
            print("\(dormant.count) projets endormis sur \(report.entries(of: .project).count), \(Format.bytes(dormant.reduce(0) { $0 + $1.size }, decimal: true)), en \(String(format: "%.1f", Date().timeIntervalSince(start))) s")
            return
        }
        if arguments.contains("--dump-roles") {
            // Services de macOS rangés par rôle : combien par famille, et ceux qui restent dans « Autres ».
            Localization.current = LanguageSetting.stored.resolved
            let model = AppModel(startImmediately: false)
            model.refreshNow()
            let roles = SystemRoleGroup.make(model.visibleGroups(in: .system))
            for family in roles {
                print("\(family.role.title.text) : \(family.groups.count) services, \(Format.bytes(family.memory))")
                if arguments.contains("--all") { print("   " + family.groups.map(\.title).joined(separator: " | ")) }
            }
            if let other = roles.first(where: { $0.role == .other }) {
                print("\nAutres : " + other.groups.map(\.title).joined(separator: " | "))
            }
            return
        }
        if arguments.contains("--dump-ports") {
            // Qui occupe quel port, sur ce Mac (processus de l'utilisateur).
            let sampler = ProcessSampler()
            _ = sampler.snapshot()
            let snapshot = SnapshotBuilder.capture(sampler: sampler, runningApps: RunningApps.current(), ownBundleID: Bundle.main.bundleIdentifier)
            let containers = DockerReader.read().containers
            let start = Date()
            let entries = PortMap.scan(groups: snapshot.groups, containers: containers)
            let jobs = KeepAliveJob.read()
            for entry in entries {
                let place = (entry.location ?? "").replacingOccurrences(of: NSHomeDirectory(), with: "~")
                // Le service qui relance ce programme dès qu'il s'arrête (lui-même ou un de ses parents).
                let job = jobs.first { job in job.pid == entry.pid || snapshot.descendants(of: job.pid).contains(entry.pid) }
                print("\(String(entry.port).padding(toLength: 6, withPad: " ", startingAt: 0)) \(entry.isExposed ? "RÉSEAU" : "local ") \(entry.groupTitle ?? entry.processName) · \(entry.processName)\(entry.container.map { " · conteneur " + $0 } ?? "") \(place)\(job.map { " · relancé par " + $0.label } ?? "")")
            }
            print("\(entries.count) ports en \(Int(Date().timeIntervalSince(start) * 1000)) ms")
            return
        }
        if arguments.contains("--dump-duplicates") {
            // Doublons dans tes dossiers, sans rien toucher (noms de fichiers seulement, pas de contenu).
            let start = Date()
            let groups = DuplicateFinder.find(roots: DuplicateFinder.roots())
            for group in groups.prefix(30) {
                print("\(Format.bytes(group.freed(), decimal: true).padding(toLength: 9, withPad: " ", startingAt: 0)) \(group.files.count)× \(group.name)")
                for file in group.files { print("    \(file.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))\(file.freed < group.size / 2 ? " (clone)" : "")") }
            }
            let total = groups.reduce(UInt64(0)) { $0 + $1.freed() }
            print("\(groups.count) groupes, \(Format.bytes(total, decimal: true)) à récupérer, en \(Int(Date().timeIntervalSince(start))) s")
            return
        }
        if arguments.contains("--dump-leftovers") {
            // Restes d'apps supprimées, sans rien toucher.
            let installed = LeftoverFinder.installedIdentifiers()
            for leftover in LeftoverFinder.find(installed: installed) {
                let size = leftover.paths.reduce(UInt64(0)) { $0 + DiskUsage.measure($1).total }
                print("\(Format.bytes(size, decimal: true).padding(toLength: 9, withPad: " ", startingAt: 0)) \(leftover.id) — \(leftover.paths.map { PathRules.lastComponent(($0 as NSString).deletingLastPathComponent) }.joined(separator: ", "))")
            }
            print("\(installed.count) apps installées connues")
            return
        }
        if arguments.contains("--dump-storage") {
            Localization.current = LanguageSetting.stored.resolved
            Debug.dumpStorage()
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
    @NSApplicationDelegateAdaptor(VigieAppDelegate.self) private var appDelegate
    @State private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            MainPanel()
                .environment(model)
        } label: {
            MenuBarLabel(model: model)
                .modifier(WindowOpenerRegistration())
        }
        .menuBarExtraStyle(.window)

        // La même chose en grand : barre latérale, vue d'ensemble, une page par famille.
        Window("Vigie", id: VigieWindow.id) {
            VigieWindow()
                .environment(model)
        }
        .defaultSize(width: 1200, height: 760)
        .windowResizability(.contentMinSize)
        // Pas de barre de titre : la barre latérale à gauche, la page à droite, rien par-dessus.
        .windowStyle(.hiddenTitleBar)
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
                if !group.exposedPorts.isEmpty { meta.append("visibles sur le réseau " + group.exposedPorts.map(String.init).joined(separator: ",")) }
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
        // Les captures montrent la fenêtre telle quelle, sans l'animation d'ouverture.
        LogoIntroGate.played = true

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
            case "--storage":
                model.mode = .storage
                if !options.contains("--demo") { model.scanStorageNow() }
            case "--mode":
                // Capture d'un mode précis : « simple » ou « developer ».
                if let mode = ExperienceMode(rawValue: value) { model.setExperience(mode, persist: false) }
                index += 1
            case "--speed":
                model.mode = .speed
            case "--storage-filter":
                model.storageFilter = StorageKind(rawValue: value)
                index += 1
            case "--collapse-storage":
                if let kind = StorageKind(rawValue: value) { model.collapsedStorage.insert(kind) }
                index += 1
            case "--begin-uninstall":
                // Capture du panneau de désinstallation (identifiant d'une app, « application:/Applications/Nom.app »).
                if let entry = model.storage?.entries.first(where: { $0.id == value }) {
                    model.beginUninstall(entry)
                    model.storageScrollTarget = entry.id
                }
                index += 1
            case "--review-safe-clean":
                model.reviewSafeClean()
            case "--select":
                // Lignes cochées (identifiants séparés par des virgules, ou « all:famille »).
                if value.hasPrefix("all:"), let kind = StorageKind(rawValue: String(value.dropFirst(4))) {
                    model.setSelection(model.storage?.entries(of: kind) ?? [], selected: true)
                } else {
                    for id in value.split(separator: ",") { model.storageSelection.insert(String(id)) }
                }
                index += 1
            case "--lesson":
                model.windowPageRequest = .lesson(value)
                index += 1
            case "--compact-sidebar":
                // Barre latérale réduite aux icônes (réglage du binaire de rendu, effacé à la fin).
                UserDefaults.standard.set(true, forKey: SidebarCompact.key)
                atexit { UserDefaults.standard.removeObject(forKey: SidebarCompact.key) }
            case "--redesign":
                model.redesign = true
            case "--section":
                model.demoSection = value
                index += 1
            case "--scan-step":
                model.demoScanStep = Int(value)
                index += 1
            case "--running-filter":
                // Familles choisies dans le filtre de « Ce qui tourne » : « apps », « apps+background »…
                model.runningFilter = Set(value.split(separator: "+").compactMap { ProcessCategory(rawValue: String($0)) })
                index += 1
            case "--dormant":
                model.refreshDormantProjects()
            case "--toolchains":
                model.refreshToolchains()
            case "--toolchain-extras":
                model.debugOnlyToolchainExtras()
            case "--confirm-selection":
                model.requestTrashSelection()
            case "--explorer-select":
                // Bloc choisi dans l'explorateur (nom dans le dossier personnel).
                model.openExplorer()
                model.explorerSelection = model.explorerRoot + "/" + value
                index += 1
            case "--large-filter":
                // Filtres de la page Gros fichiers : « video », « unused », « video+unused »…
                for part in value.split(separator: "+") {
                    if part == "unused" {
                        model.largeFileFilter.unusedOnly = true
                    } else if let category = FileCategory(rawValue: String(part)) {
                        model.largeFileFilter.categories.insert(category)
                    }
                }
                index += 1
            case "--duplicates":
                // Onglet Doublons, recherche faite, le premier groupe ouvert (sur le Mac fictif seulement).
                model.largeFilesTab = .duplicates
                if options.contains("--demo") {
                    model.findDuplicates()
                    if let first = model.duplicateGroups.first { model.expandedStorage.insert("dup:" + first.id) }
                }
            case "--confirm-duplicates":
                if let first = model.duplicateGroups.first { model.requestTrashDuplicates(first) }
            case "--confirm-clean":
                // Capture de la confirmation d'un nettoyage (identifiant d'une ligne ou d'un sous-dossier).
                let all = (model.storage?.entries ?? []).flatMap { [$0] + $0.children }
                if let entry = all.first(where: { $0.id == value }) { model.requestClean(entry) }
                index += 1
            case "--expand-storage":
                model.expandedStorage.insert(value)
                model.storageScrollTarget = value
                index += 1
            case "--learn-path":
                // Explication lue depuis une question de « Par où commencer » (étape et « Suivant »).
                model.learnPath = value
                index += 1
            case "--relaunch":
                // Bandeau « relancé par macOS » après une fermeture qui n'a pas tenu.
                model.showDemoRelaunch()
            case "--demo-update":
                // Bandeau « nouvelle version » avec une version fictive, pour les captures.
                model.showDemoUpdate()
            case "--app-sections":
                // Sections comme dans l'app : fermées au premier lancement, puis selon le dernier choix.
                model.restoreOpenSections(remember: false)
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

        // `--window [page]` : la fenêtre (pages : overview, processes:dev, docker, storage:cache…) au lieu du panneau.
        let windowPage: WindowPage? = options.firstIndex(of: "--window").map { index in
            let value = index + 1 < options.count ? options[index + 1] : "overview"
            let parts = value.split(separator: ":").map(String.init)
            switch parts.first {
            case "processes": return .processes(ProcessCategory(rawValue: parts.last ?? "") ?? .apps)
            case "docker": return .docker
            case "explorer": return .explorer
            case "speed": return .speed
            case "ports": return .ports
            case "history": return .history
            case "running": return .running
            case "rules": return .rules
            case "learn": return .learn
            case "checkup": return .checkup
            case "profile": return .macProfile
            case "glossary": return .glossary
            case "lesson": return .lesson(parts.last ?? "memoire")
            case "settings": return .settings
            case "question": return .learnQuestion(parts.last ?? "lent")
            case "topic": return .learnTopic(LessonTopic(rawValue: parts.last ?? "") ?? .basics)
            case "toolchains": return .toolchains
            case "storage": return .storage(StorageKind(rawValue: parts.last ?? "") ?? .cache)
            default: return .overview
            }
        }
        // Le bilan se rend comme dans l'app : toutes les analyses lancées.
        if windowPage == .checkup { model.runCheckup() }
        // `--intro t` : une image de l'animation d'ouverture, à l'instant t (en secondes).
        if let index = options.firstIndex(of: "--intro"), index + 1 < options.count, let time = Double(options[index + 1]) {
            let host = NSHostingView(rootView: LogoIntro(t: time).frame(width: 1200, height: 760))
            host.frame = NSRect(x: 0, y: 0, width: 1200, height: 760)
            host.appearance = NSAppearance(named: options.contains("--dark") ? .darkAqua : .aqua)
            let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.contentView = host
            window.setFrameOrigin(NSPoint(x: -4000, y: -4000))
            window.orderFrontRegardless()
            RunLoop.main.run(until: Date().addingTimeInterval(0.4))
            host.layoutSubtreeIfNeeded()
            if let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
                host.cacheDisplay(in: host.bounds, to: bitmap)
                try? bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
                print("Image écrite : \(path)")
            }
            return
        }
        // `--onboarding [0|1|2]` : un écran de l'accueil.
        if let index = options.firstIndex(of: "--onboarding") {
            let page = index + 1 < options.count ? Int(options[index + 1]) ?? 0 : 0
            let host = NSHostingView(rootView: OnboardingView(startPage: page, onFinish: {}).environment(model))
            host.frame = NSRect(x: 0, y: 0, width: 580, height: 500)
            host.appearance = NSAppearance(named: options.contains("--dark") ? .darkAqua : .aqua)
            let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.contentView = host
            window.setFrameOrigin(NSPoint(x: -4000, y: -4000))
            window.orderFrontRegardless()
            RunLoop.main.run(until: Date().addingTimeInterval(1.0))
            host.layoutSubtreeIfNeeded()
            if let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
                host.cacheDisplay(in: host.bounds, to: bitmap)
                try? bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
                print("Image écrite : \(path)")
            }
            return
        }
        // `--titled` (avec `--window`) : une vraie fenêtre, avec barre de titre et barre d'outils, capturée en entier.
        if let page = windowPage, options.contains("--titled") {
            let controller = NSHostingController(rootView: VigieWindow(page: page).environment(model))
            let window = NSWindow(contentViewController: controller)
            window.styleMask = [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView]
            // Comme la vraie fenêtre (`.hiddenTitleBar`) : barre de titre transparente, sans titre.
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.appearance = NSAppearance(named: options.contains("--dark") ? .darkAqua : .aqua)
            window.setContentSize(NSSize(width: 1200, height: 760))
            window.setFrameOrigin(NSPoint(x: -4000, y: -4000))
            window.orderFrontRegardless()
            RunLoop.main.run(until: Date().addingTimeInterval(1.5))
            if let frame = window.contentView?.superview, let bitmap = frame.bitmapImageRepForCachingDisplay(in: frame.bounds) {
                frame.cacheDisplay(in: frame.bounds, to: bitmap)
                try? bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
                print("Image écrite : \(path)")
            }
            return
        }
        let showGrid = options.contains("--grid")
        let root: AnyView = windowPage.map { page in
            AnyView(VigieWindow(page: page).environment(model).background(Color(nsColor: .windowBackgroundColor))
                .overlay { if showGrid { LayoutGridOverlay() } })
        } ?? AnyView(MainPanel().environment(model).background(Color(nsColor: .windowBackgroundColor)))
        let host = NSHostingView(rootView: root)
        // `--height N` : une capture plus haute (pour voir le bas d'une page).
        let height = options.firstIndex(of: "--height").flatMap { $0 + 1 < options.count ? Double(options[$0 + 1]) : nil }
        // `--width N` : une fenêtre plus large (pour voir une page sur grand écran).
        let width = options.firstIndex(of: "--width").flatMap { $0 + 1 < options.count ? Double(options[$0 + 1]) : nil }
        host.frame = windowPage == nil ? NSRect(x: 0, y: 0, width: 460, height: height ?? 640) : NSRect(x: 0, y: 0, width: width ?? 1200, height: height ?? 760)
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

    /// `Vigie --dump-storage` : lance l'analyse du stockage et affiche le résultat en texte.
    /// `Vigie --compare-du dossier…` : taille et durée avec `du -sk`, puis avec le compteur de Vigie.
    static func compareDu(_ paths: [String]) {
        for path in paths {
            var start = Date()
            let du = StorageScanner.measureWithDu(path)?.total ?? 0
            let duTime = Date().timeIntervalSince(start)
            start = Date()
            let walk = DiskUsage.measure(path)
            let walkTime = Date().timeIntervalSince(start)
            let gap = du == 0 ? 0 : (Double(walk.total) - Double(du)) / Double(du) * 100
            print(String(format: "%@\n  du      %@ en %.1f s\n  Vigie   %@ en %.1f s (écart %+.2f %%)%@", PathRules.abbreviate(path, home: NSHomeDirectory()),
                         Format.bytes(du, decimal: true), duTime, Format.bytes(walk.total, decimal: true), walkTime, gap, walk.denied ? " · refusé en partie" : ""))
        }
    }

    static func dumpStorage() {
        let start = Date()
        // Sur la sortie d'erreur : ce que la vue Stockage affiche déjà pendant l'analyse.
        let report = StorageScanner.scan(partial: { partial in
            let line = String(format: "  partiel à %.1f s : %d lignes, %d apps\n", Date().timeIntervalSince(start), partial.entries.count,
                              partial.entries(of: .application).count)
            FileHandle.standardError.write(Data(line.utf8))
        })
        let home = NSHomeDirectory()
        print("Analyse en \(Int(Date().timeIntervalSince(start))) s · \(Format.bytes(report.cacheTotal, decimal: true)) récupérables (caches et dépendances)")
        for kind in StorageKind.allCases {
            let entries = report.entries(of: kind)
            guard !entries.isEmpty else { continue }
            print("\n== \(kind.title)")
            for entry in entries {
                let size = entry.isProtected ? "protégé" : Format.bytes(entry.size, decimal: true)
                let command = entry.command.map { " · « \($0) »" } ?? ""
                print("  \(size.padding(toLength: 9, withPad: " ", startingAt: 0)) \(entry.title.text) — \(PathRules.abbreviate(entry.path, home: home))\(command)")
                for child in entry.children {
                    let childSize = child.isProtected ? "protégé" : Format.bytes(child.size, decimal: true)
                    let where_ = entry.kind == .application ? " — " + PathRules.abbreviate(child.path, home: home) : ""
                    print("      \(childSize.padding(toLength: 9, withPad: " ", startingAt: 0)) \(child.title.text) : \(child.explanation.text)\(where_)\(child.command.map { " « \($0) »" } ?? "")")
                }
            }
        }
        print("\nInstantanés Time Machine locaux : \(report.localSnapshots)")
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
        Notifier.diskLow(DemoData.disk(low: true), dockerDisk: DockerReader.findVirtualDisk(),
                         diagnosis: DiskDiagnosis.make(report: DemoData.storage(), previous: DemoData.storagePrevious()), isTest: true)
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
