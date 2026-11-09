import CoreServices
import Foundation
import Security

/// Ce qu'on peut faire d'un emplacement : le dire clairement est le but de la vue Stockage.
public enum StorageKind: String, CaseIterable, Sendable, Codable {
    /// Se recrée tout seul : on peut le vider sans rien perdre.
    case cache
    /// Dépendances des projets (`node_modules`) : une commande d'installation les recrée.
    case project
    /// Outils installés et données d'apps : à garder, ou à nettoyer depuis l'outil lui-même.
    case appData
    /// Applications installées, avec leur dernière ouverture.
    case application
    /// Dossiers laissés par des apps qui ne sont plus installées.
    case leftover
    /// Gros fichiers dans tes dossiers (vidéos, archives, images disque…).
    case largeFile
    /// Tes fichiers : à trier toi-même.
    case personal
    /// Ce que macOS range dans « Données système » et gère lui-même (modèles d'IA, systèmes des simulateurs…).
    case systemData

    public var title: String {
        if Wording.simple {
            switch self {
            case .cache: return tr("Fichiers temporaires", "Temporary files")
            case .application: return tr("Apps installées", "Installed apps")
            case .leftover: return tr("Restes d'apps désinstallées", "Leftovers from uninstalled apps")
            case .systemData: return tr("Fichiers de macOS", "macOS files")
            default: break
            }
        }
        switch self {
        case .cache: return tr("Caches · se recréent tout seuls", "Caches · rebuild themselves")
        case .project: return tr("Projets de dev", "Dev projects")
        case .application: return tr("Applications", "Applications")
        case .largeFile: return tr("Gros fichiers", "Large files")
        case .appData: return tr("Outils et données d'apps", "Tools and app data")
        case .personal: return tr("Tes fichiers", "Your files")
        case .leftover: return tr("Restes d'apps supprimées", "Leftovers from deleted apps")
        case .systemData: return tr("Caché dans « Données système »", "Hidden in “System Data”")
        }
    }

    /// Nom court, pour les filtres de la vue d'ensemble.
    public var shortTitle: String {
        if Wording.simple {
            switch self {
            case .cache: return tr("Temporaires", "Temporary")
            case .systemData: return tr("macOS", "macOS")
            default: break
            }
        }
        switch self {
        case .cache: return tr("Caches", "Caches")
        case .project: return tr("Projets", "Projects")
        case .application: return tr("Apps", "Apps")
        case .largeFile: return tr("Gros fichiers", "Large files")
        case .appData: return tr("Outils", "Tools")
        case .personal: return tr("Tes fichiers", "Your files")
        case .leftover: return tr("Restes", "Leftovers")
        case .systemData: return tr("macOS", "macOS")
        }
    }

    public var badge: String {
        switch self {
        case .cache: return tr("sans risque", "safe")
        case .project: return tr("réinstallable", "reinstallable")
        case .application: return tr("app", "app")
        case .largeFile: return tr("à trier", "to sort")
        case .appData: return tr("à garder", "keep")
        case .personal: return tr("tes données", "your data")
        case .leftover: return tr("à vérifier", "review first")
        case .systemData: return tr("géré par macOS", "managed by macOS")
        }
    }
}

/// Un emplacement connu, relatif au dossier personnel.
public struct StorageLocation: Sendable {
    public var id: String
    public var path: String
    public var title: L
    public var explanation: L
    public var kind: StorageKind
    public var command: String?
    /// Détailler les sous-dossiers (les plus gros).
    public var breakdown: Bool

    public init(_ id: String, _ path: String, _ title: L, _ explanation: L, _ kind: StorageKind, command: String? = nil, breakdown: Bool = false) {
        self.id = id
        self.path = path
        self.title = title
        self.explanation = explanation
        self.kind = kind
        self.command = command
        self.breakdown = breakdown
    }
}

public struct StorageEntry: Sendable, Identifiable, Equatable, Codable {
    public var id: String
    public var title: L
    public var explanation: L
    public var kind: StorageKind
    public var path: String
    public var size: UInt64
    public var command: String?
    public var children: [StorageEntry]
    public var modified: Date?
    /// macOS a refusé la lecture (dossier protégé) : il faut « l'accès complet au disque ».
    public var isProtected: Bool
    /// Autres apps qui utilisent aussi ce dossier (le dossier partagé d'Office sert à Word, Excel…) :
    /// le désinstalleur ne le retire jamais.
    public var sharedWith: [String]?
    /// Gros fichiers : dernière ouverture d'après Spotlight (nil : inconnue, on se rabat sur la modification).
    public var lastUsed: Date?
    /// Gros fichiers : synchronisé avec iCloud Drive (le mettre à la corbeille le retire aussi des autres appareils).
    public var inICloud: Bool?
    /// Petite étiquette sur la ligne (« par défaut », « en cours »…), et si elle appelle à la prudence.
    public var note: L?
    public var noteIsWarning: Bool?

    public init(id: String, title: L, explanation: L, kind: StorageKind, path: String, size: UInt64,
                command: String? = nil, children: [StorageEntry] = [], modified: Date? = nil, isProtected: Bool = false) {
        self.id = id
        self.title = title
        self.explanation = explanation
        self.kind = kind
        self.path = path
        self.size = size
        self.command = command
        self.children = children
        self.modified = modified
        self.isProtected = isProtected
    }
}

public struct StorageReport: Sendable, Equatable, Codable {
    public var entries: [StorageEntry]
    public var localSnapshots: Int
    public var date: Date

    public init(entries: [StorageEntry], localSnapshots: Int, date: Date = Date()) {
        self.entries = entries
        self.localSnapshots = localSnapshots
        self.date = date
    }

    public func entries(of kind: StorageKind) -> [StorageEntry] {
        entries.filter { $0.kind == kind }.sorted { $0.size > $1.size }
    }

    /// Les gros fichiers sont déjà comptés dans leurs dossiers : ils ne s'ajoutent pas au total.
    public var total: UInt64 { entries.filter { $0.kind != .largeFile }.reduce(0) { $0 + $1.size } }
    public var cacheTotal: UInt64 { entries(of: .cache).reduce(0) { $0 + $1.size } + entries(of: .project).reduce(0) { $0 + $1.size } }
}

// MARK: - Catalogue

/// Dernière analyse gardée sur le Mac (`~/Library/Application Support/Vigie/stockage.json`) pendant 24 h :
/// rouvrir Vigie ne relance pas une analyse d'une demi-minute. Rien ne quitte le Mac.
public enum StorageReportStore {
    public static let maximumAge: TimeInterval = 86_400
    private static let version = 1

    private struct Saved: Codable {
        var version: Int
        var report: StorageReport
    }

    public static var defaultURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Vigie", isDirectory: true)
            .appendingPathComponent("stockage.json")
    }

    /// Une analyse d'au moins 6 h devient la référence pour dire « ce qui a grossi » : comparer à une analyse
    /// d'il y a dix minutes ne montrerait rien. La référence est gardée tant qu'aucune plus récente ne la remplace.
    public static let referenceMinimumAge: TimeInterval = 6 * 3600

    public static func previousURL(for url: URL) -> URL {
        url.deletingLastPathComponent().appendingPathComponent("stockage-precedent.json")
    }

    /// Enregistre l'analyse et renvoie la référence avec laquelle la comparer (nil s'il n'y en a pas encore).
    @discardableResult
    public static func save(_ report: StorageReport, to url: URL = defaultURL) -> StorageReport? {
        let previousURL = previousURL(for: url)
        // Sans référence, l'analyse d'avant le devient tout de suite ; ensuite, seulement si elle a 6 h de plus.
        if let current = loadAny(from: url), current.date < report.date,
           loadAny(from: previousURL) == nil || report.date.timeIntervalSince(current.date) >= referenceMinimumAge {
            try? FileManager.default.removeItem(at: previousURL)
            try? FileManager.default.moveItem(at: url, to: previousURL)
        }
        guard let data = try? JSONEncoder().encode(Saved(version: version, report: report)) else { return nil }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
        return loadAny(from: previousURL)
    }

    /// Référence pour la comparaison, quel que soit son âge.
    public static func loadPrevious(for url: URL = defaultURL) -> StorageReport? {
        loadAny(from: previousURL(for: url))
    }

    public static func loadAny(from url: URL) -> StorageReport? {
        guard let data = try? Data(contentsOf: url),
              let saved = try? JSONDecoder().decode(Saved.self, from: data),
              saved.version == version else { return nil }
        return saved.report
    }

    /// La dernière analyse si elle a moins de 24 h ; sinon rien (une analyse plus ancienne ne dit plus la vérité).
    public static func load(from url: URL = defaultURL, now: Date = Date()) -> StorageReport? {
        guard let report = loadAny(from: url), isFresh(report, now: now) else { return nil }
        return report
    }

    public static func isFresh(_ report: StorageReport, now: Date = Date()) -> Bool {
        now.timeIntervalSince(report.date) < maximumAge
    }
}

public enum StorageCatalog {
    static let browserCache = L("Cache du navigateur : vide-le depuis ses réglages.", "Browser cache: clear it from the browser's settings.")
    static let downloadedUpdates = L("Mises à jour d'app déjà téléchargées.", "App updates already downloaded.")
    static let appInternalCache = L("Cache interne de l'app.", "The app's internal cache.")
    static let appData = L(
        "Réglages, historique et caches internes de l'app. Mieux vaut les nettoyer depuis l'app elle-même.",
        "The app's settings, history and internal caches. Better cleaned from within the app itself."
    )

    /// Emplacements mesurés, sans recoupement : un dossier n'apparaît qu'une fois.
    public static let locations: [StorageLocation] = [
        // Caches.
        StorageLocation("caches", "Library/Caches", L("Caches des apps", "App caches"),
                        L("Fichiers temporaires que les apps recréent quand il le faut (navigateurs, outils, mises à jour).",
                          "Temporary files apps recreate when needed (browsers, tools, updates)."), .cache, breakdown: true),
        StorageLocation("dotcache", ".cache", L("Caches des outils de dev", "Developer tool caches"),
                        L("Paquets et téléchargements gardés par des outils en ligne de commande (uv, pip, Puppeteer…).",
                          "Packages and downloads kept by command-line tools (uv, pip, Puppeteer…)."), .cache, breakdown: true),
        StorageLocation("npm", ".npm", L("Cache npm", "npm cache"),
                        L("Paquets JavaScript déjà téléchargés par npm.", "JavaScript packages npm already downloaded."), .cache,
                        command: "npm cache clean --force"),
        StorageLocation("pnpm-store", "Library/pnpm", L("Magasin pnpm", "pnpm store"),
                        L("Paquets JavaScript partagés entre tes projets pnpm. La commande ne retire que ceux qu'aucun projet n'utilise.",
                          "JavaScript packages shared by your pnpm projects. The command only removes those no project uses."), .cache,
                        command: "pnpm store prune"),
        StorageLocation("bun", ".bun/install/cache", L("Cache Bun", "Bun cache"),
                        L("Paquets JavaScript téléchargés par Bun.", "JavaScript packages downloaded by Bun."), .cache, command: "bun pm cache rm"),
        StorageLocation("yarn", ".yarn/berry/cache", L("Cache Yarn", "Yarn cache"),
                        L("Paquets JavaScript téléchargés par Yarn.", "JavaScript packages downloaded by Yarn."), .cache, command: "yarn cache clean"),
        StorageLocation("gradle", ".gradle/caches", L("Cache Gradle", "Gradle cache"),
                        L("Dépendances Java et Android téléchargées par Gradle.", "Java and Android dependencies downloaded by Gradle."), .cache),
        StorageLocation("maven", ".m2/repository", L("Dépôt Maven local", "Local Maven repository"),
                        L("Dépendances Java téléchargées par Maven.", "Java dependencies downloaded by Maven."), .cache),
        StorageLocation("cargo", ".cargo/registry", L("Cache des paquets Rust", "Rust package cache"),
                        L("Paquets Rust (crates) téléchargés par Cargo.", "Rust packages (crates) downloaded by Cargo."), .cache),
        StorageLocation("go", "go/pkg/mod", L("Modules Go", "Go modules"),
                        L("Modules Go téléchargés.", "Downloaded Go modules."), .cache, command: "go clean -modcache"),
        StorageLocation("logs", "Library/Logs", L("Journaux et rapports de plantage", "Logs and crash reports"),
                        L("Historique technique des apps et rapports de plantage : utiles seulement pour déboguer. Les apps en écrivent de nouveaux.",
                          "Apps' technical history and crash reports: only useful for debugging. Apps write new ones."), .cache, breakdown: true),
        StorageLocation("ios-updates", "Library/iTunes/iPhone Software Updates", L("Mises à jour d'iPhone téléchargées", "Downloaded iPhone updates"),
                        L("Anciennes mises à jour d'iOS gardées par le Finder : elles se retéléchargent si besoin.",
                          "Old iOS updates kept by the Finder: they download again if needed."), .cache),
        StorageLocation("derived-data", "Library/Developer/Xcode/DerivedData", L("Compilations de Xcode", "Xcode build data"),
                        L("Fichiers de compilation de Xcode : il les recrée à la prochaine compilation.",
                          "Xcode build files: it recreates them on the next build."), .cache),
        StorageLocation("device-support", "Library/Developer/Xcode/iOS DeviceSupport", L("Symboles des iPhone branchés", "Connected iPhone symbols"),
                        L("Xcode les retélécharge quand tu rebranches un appareil.", "Xcode downloads them again when you reconnect a device."), .cache),
        // Outils et données d'apps.
        StorageLocation("simulators", "Library/Developer/CoreSimulator", L("Simulateurs iPhone de Xcode", "Xcode iPhone simulators"),
                        L("Appareils simulés et leurs données. La commande retire ceux que Xcode ne peut plus utiliser.",
                          "Simulated devices and their data. The command removes those Xcode can no longer use."), .appData,
                        command: "xcrun simctl delete unavailable"),
        StorageLocation("rustup", ".rustup", L("Outils Rust (rustup)", "Rust toolchains (rustup)"),
                        L("Compilateurs Rust installés. La commande les liste ; « rustup toolchain uninstall » retire ceux qui ne servent plus.",
                          "Installed Rust compilers. The command lists them; “rustup toolchain uninstall” removes unused ones."), .appData,
                        command: "rustup toolchain list"),
        StorageLocation("local", ".local", L("Outils installés dans ton dossier", "Tools installed in your folder"),
                        L("Programmes en ligne de commande installés pour toi (Claude Code, uv, pipx…).",
                          "Command-line programs installed for you (Claude Code, uv, pipx…)."), .appData, breakdown: true),
        StorageLocation("nvm", ".nvm", L("Versions de Node.js (nvm)", "Node.js versions (nvm)"),
                        L("Versions de Node.js installées avec nvm.", "Node.js versions installed with nvm."), .appData, command: "nvm ls"),
        StorageLocation("ollama", ".ollama", L("Modèles d'IA d'Ollama", "Ollama AI models"),
                        L("Modèles d'IA téléchargés : ils se retéléchargent, mais c'est long.", "Downloaded AI models: they can be downloaded again, but it takes time."),
                        .appData, command: "ollama list"),
        // Tes fichiers.
        StorageLocation("desktop", "Desktop", L("Bureau", "Desktop"),
                        L("Tes fichiers sur le Bureau ; le détail montre les plus gros dossiers.",
                          "Your files on the Desktop; the details show the largest folders."), .personal, breakdown: true),
        StorageLocation("documents", "Documents", L("Documents", "Documents"),
                        L("Ton dossier Documents ; le détail montre les plus gros dossiers.",
                          "Your Documents folder; the details show the largest folders."), .personal, breakdown: true),
        StorageLocation("downloads", "Downloads", L("Téléchargements", "Downloads"),
                        L("Fichiers que tu as téléchargés : souvent des installeurs et des archives oubliés.",
                          "Files you downloaded: often forgotten installers and archives."), .personal),
        StorageLocation("trash", ".Trash", L("Corbeille", "Trash"),
                        L("Fichiers supprimés mais pas encore effacés : ils prennent toujours de la place tant que la corbeille n'est pas vidée.",
                          "Deleted files not yet erased: they still take up space until the Trash is emptied."), .personal),
        StorageLocation("ios-backups", "Library/Application Support/MobileSync/Backup", L("Sauvegardes d'iPhone et d'iPad", "iPhone and iPad backups"),
                        L("Sauvegardes locales de tes appareils : gère-les dans le Finder, quand l'appareil est branché.",
                          "Local backups of your devices: manage them in the Finder when the device is connected."), .personal),
    ]

    /// Données d'apps connues dans « Application Support » (mesurées une par une, pour ne pas toucher aux dossiers protégés).
    public static let appSupport: [(folder: String, name: String)] = [
        ("Claude", "Claude"), ("Code", "Visual Studio Code"), ("Cursor", "Cursor"), ("Slack", "Slack"), ("discord", "Discord"),
        ("Google", "Google Chrome"), ("BraveSoftware", "Brave"), ("com.operasoftware.Opera", "Opera"), ("Firefox", "Firefox"),
        ("Spotify", "Spotify"), ("zoom.us", "Zoom"), ("Figma", "Figma"), ("JetBrains", "JetBrains"), ("Notion", "Notion"),
        ("obsidian", "Obsidian"), ("Microsoft", "Microsoft"), ("Arc", "Arc"), ("Zed", "Zed"), ("Docker Desktop", "Docker Desktop"),
    ]

    /// Explication d'un sous-dossier connu (dans un cache ou les données d'une app).
    public static func child(_ name: String, parentKind: StorageKind) -> (explanation: L, command: String?) {
        let known: [String: (L, String?)] = [
            "uv": (L("Paquets Python téléchargés par uv.", "Python packages downloaded by uv."), "uv cache clean"),
            "pip": (L("Paquets Python téléchargés par pip.", "Python packages downloaded by pip."), "pip cache purge"),
            "puppeteer": (L("Navigateurs téléchargés par Puppeteer.", "Browsers downloaded by Puppeteer."), nil),
            "huggingface": (L("Modèles d'IA téléchargés (Hugging Face) : ils se retéléchargent, mais c'est long.",
                              "Downloaded AI models (Hugging Face): they can be downloaded again, but it takes time."), nil),
            "codex-runtimes": (L("Environnements d'exécution téléchargés par Codex.", "Runtimes downloaded by Codex."), nil),
            "prisma": (L("Moteurs de base de données téléchargés par Prisma.", "Database engines downloaded by Prisma."), nil),
            "ms-playwright": (L("Navigateurs utilisés par Playwright pour les tests.", "Browsers Playwright uses for tests."), "npx playwright uninstall --all"),
            "Homebrew": (L("Téléchargements de Homebrew.", "Homebrew downloads."), "brew cleanup --prune=all"),
            "pnpm": (L("Métadonnées des paquets de pnpm.", "pnpm package metadata."), nil),
            "Yarn": (L("Paquets JavaScript téléchargés par Yarn.", "JavaScript packages downloaded by Yarn."), "yarn cache clean"),
            "com.operasoftware.Opera": (browserCache, nil),
            "BraveSoftware": (browserCache, nil),
            "Google": (browserCache, nil),
            "Firefox": (browserCache, nil),
            "company.thebrowser.Browser": (browserCache, nil),
            "vm_bundles": (L("Images de machine virtuelle de l'app Claude : elle les retéléchargerait.",
                             "Virtual machine images of the Claude app: it would download them again."), nil),
            "claude-code": (L("Versions de Claude Code utilisées par l'app.", "Claude Code versions used by the app."), nil),
            "Cache": (appInternalCache, nil),
            "Code Cache": (appInternalCache, nil),
            "GPUCache": (appInternalCache, nil),
            "CachedData": (appInternalCache, nil),
            "CachedExtensionVSIXs": (L("Extensions téléchargées en cache.", "Cached downloaded extensions."), nil),
            "User": (L("Tes réglages et l'historique de l'app.", "Your settings and the app's history."), nil),
        ]
        if let match = known[name] { return match }
        let lowered = name.lowercased()
        if lowered.contains("updater") || lowered.contains("shipit") || lowered.hasSuffix(".shipit") { return (downloadedUpdates, nil) }
        switch parentKind {
        case .cache: return (L("Cache d'une app ou d'un outil.", "Cache of an app or tool."), nil)
        case .personal, .leftover, .systemData: return (L("Dossier.", "Folder."), nil)
        default: return (L("Données de l'app.", "App data."), nil)
        }
    }
}

// MARK: - Analyse

public enum StorageScanner {
    /// Taille réellement occupée (comme `du`), d'un dossier et éventuellement de ses sous-dossiers.
    public struct Measure: Sendable {
        public var total: UInt64
        public var children: [(name: String, size: UInt64)]
        public var denied: Bool
    }

    /// Lit la sortie de `du -k` : « kilo-octets<TAB>chemin » par ligne.
    public static func parseDu(_ output: String, root: String) -> (total: UInt64, children: [(name: String, size: UInt64)]) {
        var total: UInt64 = 0
        var children: [(name: String, size: UInt64)] = []
        let normalizedRoot = PathRules.normalize(root)
        for line in output.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: "\t", maxSplits: 1)
            guard parts.count == 2, let kilobytes = UInt64(parts[0]) else { continue }
            let path = PathRules.normalize(String(parts[1]))
            if path == normalizedRoot {
                total = kilobytes * 1024
            } else {
                children.append((PathRules.lastComponent(path), kilobytes * 1024))
            }
        }
        return (total, children.sorted { $0.size > $1.size })
    }

    public static func measureWithDu(_ path: String, breakdown: Bool = false, timeout: TimeInterval = 120) -> Measure? {
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/du")
        process.arguments = breakdown ? ["-k", "-d", "1", path] : ["-sk", path]
        let output = Pipe(), errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        do { try process.run() } catch { return nil }
        let watchdog = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: watchdog)
        let data = output.fileHandleForReading.readDataToEndOfFile()
        let errorText = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        watchdog.cancel()
        let parsed = parseDu(String(decoding: data, as: UTF8.self), root: path)
        let denied = errorText.contains("Operation not permitted") || errorText.contains("Permission denied")
        return Measure(total: parsed.total, children: parsed.children, denied: denied && parsed.total < 1_048_576)
    }

    /// Taille d'un dossier (et de ses sous-dossiers directs) avec le compteur parallèle de Vigie.
    public static func measure(_ path: String, breakdown: Bool) -> Measure? {
        let result = DiskUsage.measure(path, breakdown: breakdown)
        guard result.exists else { return nil }
        return Measure(total: result.total, children: result.children, denied: result.denied && result.total < 1_048_576)
    }

    /// Dossiers `node_modules` des projets, sans descendre dans les dépendances ni les dossiers cachés.
    public static func findNodeModules(roots: [String]) -> [String] {
        DiskUsage.measure(roots.map { DiskUsage.Request(path: $0, findNodeModules: true, skipHidden: true) })
            .flatMap { $0.nodeModules.map(\.path) }
    }

    /// Dossiers visibles du dossier personnel où chercher des projets.
    public static func projectRoots(home: String) -> [String] {
        let skipped: Set<String> = ["Library", "Applications", "Movies", "Music", "Pictures", "Public", "Downloads"]
        let names = (try? FileManager.default.contentsOfDirectory(atPath: home)) ?? []
        return names.filter { !$0.hasPrefix(".") && !skipped.contains($0) }
            .map { home + "/" + $0 }
            .filter { var isDirectory: ObjCBool = false; return FileManager.default.fileExists(atPath: $0, isDirectory: &isDirectory) && isDirectory.boolValue }
            .sorted()
    }

    public static func localSnapshotCount() -> Int {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tmutil")
        process.arguments = ["listlocalsnapshots", "/"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return 0 }
        let text = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        return text.split(whereSeparator: \.isNewline).filter { $0.contains("com.apple") }.count
    }

    /// Analyse complète, en parallèle. `progress` reçoit une valeur entre 0 et 1.
    /// Analyse complète. `partial` reçoit des résultats partiels pendant l'analyse (environ deux fois par seconde) :
    /// les petits dossiers sont prêts en quelques secondes, le Bureau et les gros caches arrivent ensuite.
    public static func scan(home: String = NSHomeDirectory(), minimumSize: UInt64 = 50_000_000,
                            progress: @escaping @Sendable (Double) -> Void = { _ in },
                            partial: (@Sendable (StorageReport) -> Void)? = nil) -> StorageReport {
        progress(0.01)
        let plan = ScanPlan(home: home, minimumSize: minimumSize)
        let collector = ResultCollector(count: plan.requests.count)
        let results = DiskUsage.measure(plan.requests, completed: { index, result in
            let (done, snapshot) = collector.store(result, at: index, snapshotEvery: partial == nil ? nil : 0.5)
            progress(0.03 + 0.95 * Double(done) / Double(max(1, plan.requests.count)))
            if let snapshot, let partial {
                partial(plan.report(from: snapshot, date: Date(), localSnapshots: 0))
            }
        })
        let report = plan.report(from: results.map { Optional($0) }, date: Date(), localSnapshots: localSnapshotCount())
        progress(1)
        return report
    }

    /// Résultats reçus pendant l'analyse, avec un instantané de temps en temps pour l'affichage.
    private final class ResultCollector: @unchecked Sendable {
        private let lock = NSLock()
        private var results: [DiskUsage.Result?]
        private var done = 0
        private var lastSnapshot = Date.distantPast

        init(count: Int) { results = Array(repeating: nil, count: count) }

        func store(_ result: DiskUsage.Result, at index: Int, snapshotEvery interval: TimeInterval?) -> (Int, [DiskUsage.Result?]?) {
            lock.lock()
            defer { lock.unlock() }
            results[index] = result
            done += 1
            guard let interval, Date().timeIntervalSince(lastSnapshot) >= interval else { return (done, nil) }
            lastSnapshot = Date()
            return (done, results)
        }
    }

    /// Ce qu'une analyse mesure, et comment en tirer un rapport (même partiel).
    struct ScanPlan: Sendable {
        struct Job: Sendable {
            var id: String, path: String, title: L, explanation: L, kind: StorageKind, command: String?, breakdown: Bool
        }
        let home: String
        let minimumSize: UInt64
        let jobs: [Job]
        let requests: [DiskUsage.Request]
        /// Index des premières demandes propres aux apps (les précédentes : emplacements, projets, gros fichiers).
        let appStart: Int
        let candidates: [AppCandidate]
        /// Vieux installeurs (.dmg, .pkg…) de Téléchargements, repérés avant la mesure.
        let installers: [OldInstallers.File]
        /// Restes d'apps supprimées (dossiers repérés avant la mesure).
        let leftovers: [LeftoverFinder.Leftover]
        /// Demande qui mesure les ressources de macOS (`/System/Library/AssetsV2`).
        let systemAssetsRequest: Int
        /// Demande qui mesure chaque chemin d'app (un dossier déjà demandé, comme « Données de Notion », est réutilisé).
        let appRequestIndex: [String: Int]

        init(home: String, minimumSize: UInt64) {
            self.home = home
            self.minimumSize = minimumSize
            var jobs: [Job] = StorageCatalog.locations.map {
                Job(id: $0.id, path: home + "/" + $0.path, title: $0.title, explanation: $0.explanation, kind: $0.kind, command: $0.command, breakdown: $0.breakdown)
            }
            for app in StorageCatalog.appSupport {
                jobs.append(Job(id: "app:" + app.folder, path: home + "/Library/Application Support/" + app.folder,
                                title: L("Données de \(app.name)", "\(app.name) data"), explanation: StorageCatalog.appData,
                                kind: .appData, command: nil, breakdown: app.folder == "Claude"))
            }
            // Tout est mesuré en une seule passe parallèle. Le Bureau et les Documents ne sont lus qu'une fois :
            // la même lecture donne leur taille, leurs projets (`node_modules`) et leurs gros fichiers.
            let largeFileMinimum = StorageScanner.largeFileMinimum
            let projectFolders: Set<String> = ["Desktop", "Documents"]
            let largeFileFolders: Set<String> = ["Desktop", "Documents", "Downloads"]
            var requests = jobs.map { job -> DiskUsage.Request in
                let relative = String(job.path.dropFirst(home.count + 1))
                return DiskUsage.Request(path: job.path, breakdown: job.breakdown, findNodeModules: projectFolders.contains(relative),
                                         largeFileMinimum: largeFileFolders.contains(relative) ? largeFileMinimum : nil)
            }
            // Autres dossiers visibles du dossier personnel : seulement pour y trouver des projets.
            for root in StorageScanner.projectRoots(home: home) where !projectFolders.contains(PathRules.lastComponent(root)) {
                requests.append(DiskUsage.Request(path: root, findNodeModules: true, skipHidden: true))
            }
            requests.append(DiskUsage.Request(path: home + "/Movies", largeFileMinimum: largeFileMinimum))
            installers = OldInstallers.find(home: home)
            systemAssetsRequest = requests.count
            requests.append(DiskUsage.Request(path: SystemAssets.path, breakdown: true))
            // Apps et leurs dossiers dans ~/Library : repérés d'abord (rapide), mesurés dans la même passe.
            let candidates = StorageScanner.locateApplications(home: home)
            appStart = requests.count
            var index: [String: Int] = [:]
            for (position, request) in requests.enumerated() where index[request.path] == nil { index[request.path] = position }
            var appRequestIndex: [String: Int] = [:]
            let leftovers = home == NSHomeDirectory() || FileManager.default.fileExists(atPath: home + "/Library")
                ? LeftoverFinder.find(home: home, installed: LeftoverFinder.installedIdentifiers(home: home)) : []
            self.leftovers = leftovers
            for path in StorageScanner.measurementPaths(for: candidates) + leftovers.flatMap(\.paths) {
                if let existing = index[path] {
                    appRequestIndex[path] = existing
                } else {
                    appRequestIndex[path] = requests.count
                    index[path] = requests.count
                    requests.append(DiskUsage.Request(path: path))
                }
            }
            self.appRequestIndex = appRequestIndex
            self.jobs = jobs
            self.requests = requests
            self.candidates = candidates
        }

        /// Rapport à partir des résultats reçus ; les demandes encore en cours sont simplement absentes.
        func report(from results: [DiskUsage.Result?], date: Date, localSnapshots: Int) -> StorageReport {
            var entries: [StorageEntry] = []
            for (job, measure) in zip(jobs, results) {
                guard let measure, measure.exists else { continue }
                let denied = measure.denied && measure.total < 1_048_576
                guard denied || measure.total >= minimumSize else { continue }
                // Les journaux sont petits mais nombreux : on montre aussi les dossiers de quelques Mo, pour pouvoir les vider.
                let childMinimum = job.id == "logs" ? min(minimumSize, 5_000_000) : minimumSize
                let children: [StorageEntry] = (job.breakdown ? measure.children : []).filter { $0.size >= childMinimum }.prefix(8).map { child in
                    let info = StorageCatalog.child(child.name, parentKind: job.kind)
                    return StorageEntry(id: job.id + "/" + child.name, title: L(child.name, child.name), explanation: info.explanation,
                                        kind: job.kind, path: job.path + "/" + child.name, size: child.size, command: info.command)
                }
                entries.append(StorageEntry(id: job.id, title: job.title, explanation: job.explanation, kind: job.kind, path: job.path,
                                            size: measure.total, command: job.command, children: children, isProtected: denied))
            }

            var projects = Set<String>()
            for case let result? in results[..<appStart] {
                for module in result.nodeModules where module.size >= minimumSize && projects.insert(module.path).inserted {
                    let project = (module.path as NSString).deletingLastPathComponent
                    let name = PathRules.lastComponent(project)
                    let modified = (try? URL(fileURLWithPath: project + "/package.json")
                        .resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? nil
                    entries.append(StorageEntry(id: "project:" + module.path, title: L(name, name),
                                                explanation: L("Dépendances JavaScript du projet : npm install (ou pnpm install) les réinstalle.",
                                                               "The project's JavaScript dependencies: npm install (or pnpm install) reinstalls them."),
                                                kind: .project, path: module.path, size: module.size, modified: modified))
                }
            }

            // Le disque virtuel de Docker est lu sans parcourir le dossier de Docker (protégé par macOS).
            if let docker = DockerReader.findVirtualDisk(home: home), docker.allocated >= minimumSize {
                entries.append(StorageEntry(
                    id: "docker", title: L("Disque virtuel de Docker", "Docker virtual disk"),
                    explanation: L("Images, conteneurs et volumes de Docker : détail et nettoyage dans la section Docker.",
                                   "Docker images, containers and volumes: details and cleanup in the Docker section."),
                    kind: .appData, path: docker.path, size: docker.allocated, command: "docker system prune"
                ))
            }

            // Les apps s'affichent tout de suite (taille estimée par Spotlight, puis mesurée) ; leurs dossiers s'ajoutent une fois mesurés.
            var measured: [String: DiskUsage.Result] = [:]
            for (path, index) in appRequestIndex {
                if let result = results[index] { measured[path] = result }
            }
            var candidates = self.candidates
            StorageScanner.apply(measured, to: &candidates)
            let applications = StorageScanner.assembleApplications(
                candidates, extraData: entries.filter { $0.id.hasPrefix("app:") || $0.id == "docker" })
            entries.append(contentsOf: applications)
            // Les données d'une app installée sont maintenant rangées sous elle : pas de ligne en double.
            let groupedPaths = Set(applications.flatMap { $0.children.map(\.path) })
            entries.removeAll { ($0.id.hasPrefix("app:") || $0.id == "docker") && groupedPaths.contains($0.path) }
            entries.append(contentsOf: StorageScanner.largeFileEntries(results[..<appStart].compactMap { $0 }.flatMap(\.largeFiles)))

            // Restes d'apps supprimées : une ligne par app disparue, ses dossiers en dessous (au moins 1 Mo en tout).
            for leftover in leftovers {
                let children: [StorageEntry] = leftover.paths.compactMap { path in
                    guard let index = appRequestIndex[path], let result = results[index], result.exists else { return nil }
                    let place = PathRules.lastComponent((path as NSString).deletingLastPathComponent)
                    return StorageEntry(id: "leftover-file:" + path, title: LeftoverFinder.placeTitle(place),
                                        explanation: L("Reste d'une app qui n'est plus installée.", "Left by an app that is no longer installed."),
                                        kind: .leftover, path: path, size: result.total)
                }.sorted { $0.size > $1.size }
                let total = children.reduce(UInt64(0)) { $0 + $1.size }
                guard total >= 1_000_000, let largest = children.first else { continue }
                entries.append(StorageEntry(id: "leftover:" + leftover.id, title: L(leftover.id, leftover.id),
                                            explanation: L("Restes d'une app qui n'est plus installée : \(children.count) dossier\(children.count > 1 ? "s" : "") (données, caches, réglages). À la corbeille, tu peux revenir en arrière.",
                                                           "Left by an app that is no longer installed: \(children.count) folder\(children.count > 1 ? "s" : "") (data, caches, settings). They go to the Trash, so you can undo."),
                                            kind: .leftover, path: largest.path, size: total, children: children))
            }
            if let entry = OldInstallers.entry(installers, home: home, minimumSize: minimumSize) { entries.append(entry) }
            // Ressources de macOS, en lecture seule.
            if let assets = results[systemAssetsRequest], assets.exists {
                entries.append(contentsOf: SystemAssets.entries(from: assets.children, minimumSize: minimumSize))
            }
            return StorageReport(entries: entries.sorted { $0.size > $1.size }, localSnapshots: localSnapshots, date: date)
        }
    }

    // MARK: Applications

    /// App trouvée dans /Applications ou ~/Applications, avec ses dossiers dans ~/Library.
    public struct AppCandidate: Sendable {
        public var path: String
        public var name: String
        public var size: UInt64 = 0
        /// Taille selon Spotlight, affichée en attendant la mesure : elle peut dater d'une ancienne version de l'app.
        public var spotlightSize: UInt64?
        public var found: [AppFootprint.Found]
    }

    /// Apps de /Applications et ~/Applications, avec leur taille, leurs dossiers et leur dernière ouverture selon macOS.
    public static func scanApplications(home: String, minimumSize: UInt64 = 100_000_000,
                                        extraData: [StorageEntry] = [], folders: [String]? = nil) -> [StorageEntry] {
        var candidates = locateApplications(home: home, folders: folders)
        let paths = measurementPaths(for: candidates)
        let results = DiskUsage.measure(paths.map { DiskUsage.Request(path: $0) })
        apply(Dictionary(zip(paths, results), uniquingKeysWith: { first, _ in first }), to: &candidates)
        return assembleApplications(candidates, minimumSize: minimumSize, extraData: extraData)
    }

    /// Apps et leurs dossiers, sans rien mesurer : quelques millisecondes.
    public static func locateApplications(home: String, folders: [String]? = nil) -> [AppCandidate] {
        var bundles: [String] = []
        for folder in folders ?? ["/Applications", home + "/Applications"] {
            let names = (try? FileManager.default.contentsOfDirectory(atPath: folder)) ?? []
            for name in names where name.hasSuffix(".app") {
                let path = folder + "/" + name
                // Les apps d'Apple installées avec macOS sont des raccourcis : on les ignore.
                if (try? FileManager.default.destinationOfSymbolicLink(atPath: path)) != nil { continue }
                bundles.append(path)
            }
        }
        let fullDiskAccess = AppFootprint.hasFullDiskAccess()
        let lock = NSLock()
        var candidates = [AppCandidate?](repeating: nil, count: bundles.count)
        DispatchQueue.concurrentPerform(iterations: bundles.count) { index in
            let path = bundles[index]
            let estimate = spotlightSize(path)
            let candidate = AppCandidate(path: path, name: PathRules.bundleDisplayName(path), size: estimate ?? 0, spotlightSize: estimate,
                                         found: AppFootprint.locate(path, home: home, fullDiskAccess: fullDiskAccess))
            lock.lock()
            candidates[index] = candidate
            lock.unlock()
        }
        return candidates.compactMap { $0 }
    }

    /// Ce qu'il faut mesurer, chaque chemin une seule fois : les paquets, puis les dossiers lisibles
    /// (deux apps peuvent viser le même, comme Claude et son assistant).
    static func measurementPaths(for candidates: [AppCandidate]) -> [String] {
        var seen = Set<String>()
        var paths: [String] = []
        for candidate in candidates {
            let wanted = [candidate.path] + candidate.found.filter { !$0.entry.isProtected }.map(\.entry.path)
            for path in wanted where seen.insert(path).inserted { paths.append(path) }
        }
        return paths
    }

    /// Reporte les mesures reçues. Un dossier pas encore mesuré est laissé de côté (analyse en cours).
    static func apply(_ results: [String: DiskUsage.Result], to candidates: inout [AppCandidate]) {
        for index in candidates.indices {
            candidates[index].size = results[candidates[index].path]?.total ?? candidates[index].spotlightSize ?? 0
            candidates[index].found = candidates[index].found.compactMap { item in
                guard !item.entry.isProtected else { return item }
                guard let result = results[item.entry.path] else { return nil }
                var item = item
                item.entry.size = result.total
                // macOS peut refuser la lecture même avec l'accès complet (données d'autres apps) : on le dit.
                item.entry.isProtected = result.denied && result.total < 1_048_576
                return item
            }
        }
    }

    /// Place occupée par un paquet d'app selon Spotlight (`kMDItemPhysicalSize`). Juste pour afficher l'app tout de suite :
    /// Spotlight peut garder la taille d'une ancienne version (Bionic : 1,4 Go annoncés, 901 Mo réels).
    static func spotlightSize(_ path: String) -> UInt64? {
        guard let item = MDItemCreate(nil, path as CFString),
              let value = MDItemCopyAttribute(item, "kMDItemPhysicalSize" as CFString) as? NSNumber,
              value.uint64Value > 0 else { return nil }
        return value.uint64Value
    }

    /// Une ligne par app, chaque dossier rattaché à une seule app.
    static func assembleApplications(_ candidates: [AppCandidate], minimumSize: UInt64 = 100_000_000,
                                     extraData: [StorageEntry] = []) -> [StorageEntry] {
        // Un dossier n'appartient qu'à une app : l'identifiant exact l'emporte, puis le nom identique, puis la plus grosse app.
        var owner: [String: Int] = [:]
        for (index, candidate) in candidates.enumerated() {
            for item in candidate.found {
                let path = item.entry.path
                guard let current = owner[path] else { owner[path] = index; continue }
                func score(_ i: Int) -> (Int, Int, UInt64) {
                    let c = candidates[i]
                    let match = c.found.first { $0.entry.path == path }
                    let folder = PathRules.lastComponent(path)
                    return (match?.byIdentifier == true ? 1 : 0, c.name == folder ? 1 : 0, c.size)
                }
                if score(index) > score(current) { owner[path] = index }
            }
        }
        // Un dossier visé par plusieurs apps (le dossier partagé d'Office) : rangé sous une seule, mais marqué partagé.
        var claimants: [String: [Int]] = [:]
        for (index, candidate) in candidates.enumerated() {
            // Seule une revendication forte compte (identifiant ou signature) : l'assistant « Claude Code URL Handler »,
            // qui ne vise le dossier de Claude que par son nom, ne doit pas empêcher de le retirer avec Claude.
            for item in candidate.found where item.byIdentifier { claimants[item.entry.path, default: []].append(index) }
        }
        var related: [[StorageEntry]] = candidates.indices.map { index in
            candidates[index].found.filter { owner[$0.entry.path] == index }.map { item in
                var entry = item.entry
                let others = (claimants[entry.path] ?? []).filter { $0 != index }.map { candidates[$0].name }
                if !others.isEmpty { entry.sharedWith = Array(Set(others)).sorted() }
                return entry
            }
        }
        // Données connues sous un autre nom (« BraveSoftware » pour Brave Browser) : rattachées par le nom de l'app.
        // Nom identique d'abord ; sinon une seule app dont le nom le contient (« Microsoft » couvre plusieurs apps : la ligne reste à part).
        for data in extraData where data.id.hasPrefix("app:") && owner[data.path] == nil {
            let name = data.title.en.replacingOccurrences(of: " data", with: "")
            let exact = candidates.indices.filter { candidates[$0].name.caseInsensitiveCompare(name) == .orderedSame }
            let containing = candidates.indices.filter { candidates[$0].name.localizedCaseInsensitiveContains(name) }
            let matches = exact.isEmpty ? containing : exact
            if matches.count == 1, let index = matches.first {
                related[index].append(StorageEntry(id: "footprint:" + data.path, title: AppFootprint.dataTitle,
                                                   explanation: AppFootprint.dataExplanation, kind: .appData, path: data.path,
                                                   size: data.size, isProtected: data.isProtected))
            }
        }

        // Données mesurées à part mais rangées dans un dossier de l'app : le disque virtuel de Docker est dans son dossier privé.
        for data in extraData where !data.id.hasPrefix("app:") {
            for index in related.indices {
                guard let container = related[index].firstIndex(where: { data.path.hasPrefix($0.path + "/") }) else { continue }
                if !related[index][container].isProtected {
                    related[index][container].size -= min(related[index][container].size, data.size)
                }
                related[index].append(StorageEntry(id: "footprint:" + data.path, title: data.title, explanation: data.explanation,
                                                   kind: .appData, path: data.path, size: data.size, command: data.command,
                                                   isProtected: data.isProtected))
                break
            }
        }

        var results: [StorageEntry] = []
        for (index, candidate) in candidates.enumerated() {
            let children = related[index].sorted { ($0.isProtected ? 1 : 0, $1.size) < ($1.isProtected ? 1 : 0, $0.size) }
            let dataSize = children.reduce(UInt64(0)) { $0 + $1.size }
            let total = candidate.size + dataSize
            guard total >= minimumSize else { continue }
            let lastUsed = lastUsedDate(candidate.path)
            let summary = { (language: Language) in
                applicationSummary(appSize: candidate.size, dataSize: dataSize, places: children.count, lastUsed: lastUsed, in: language)
            }
            results.append(StorageEntry(id: "application:" + candidate.path, title: L(candidate.name, candidate.name),
                                        explanation: L(summary(.fr), summary(.en)), kind: .application,
                                        path: candidate.path, size: total, children: children, modified: lastUsed))
        }
        return results.sorted { $0.size > $1.size }
    }

    /// « App 1 GB + 6 GB de données dans 4 dossiers. Dernière ouverture : il y a 3 jours. »
    public static func applicationSummary(appSize: UInt64, dataSize: UInt64, places: Int, lastUsed: Date?,
                                          in language: Language, now: Date = Date()) -> String {
        let app = Format.bytes(appSize, decimal: true, in: language)
        let data = Format.bytes(dataSize, decimal: true, in: language)
        let used = lastUsed.map { Format.ago($0, in: language, now: now) }
        if language == .fr {
            let extra = places == 0 ? "" : " + \(data) de données dans \(places) dossier\(places > 1 ? "s" : "")"
            return "App \(app)\(extra). " + (used.map { "Dernière ouverture : \($0)." } ?? "Dernière ouverture inconnue.")
        }
        let extra = places == 0 ? "" : " + \(data) of data in \(places) folder\(places > 1 ? "s" : "")"
        return "App \(app)\(extra). " + (used.map { "Last opened \($0)." } ?? "Last opening unknown.")
    }

    static func lastUsedDate(_ path: String) -> Date? {
        guard let item = MDItemCreate(nil, path as CFString) else { return nil }
        return MDItemCopyAttribute(item, kMDItemLastUsedDate) as? Date
    }

    // MARK: Gros fichiers

    /// Seuil des gros fichiers : 100 Mo (une vidéo de quelques minutes, un installeur).
    public static let largeFileMinimum: UInt64 = 100_000_000
    public static let largeFileLimit = 40

    /// Fichiers d'au moins 100 Mo dans Documents, Bureau, Téléchargements et Vidéos.
    public static func findLargeFiles(home: String, minimumSize: UInt64 = largeFileMinimum, limit: Int = largeFileLimit) -> [StorageEntry] {
        let results = DiskUsage.measure(["Documents", "Desktop", "Downloads", "Movies"].map {
            DiskUsage.Request(path: home + "/" + $0, largeFileMinimum: minimumSize)
        })
        return largeFileEntries(results.flatMap(\.largeFiles), limit: limit)
    }

    /// `details` : lire la dernière ouverture (Spotlight) et iCloud ; coupé dans les tests et la démo.
    static func largeFileEntries(_ files: [DiskUsage.LargeFile], limit: Int = largeFileLimit, details: Bool = true) -> [StorageEntry] {
        files.sorted { $0.size > $1.size }.prefix(limit).map { file in
            let type = fileType(file.path)
            let explanation = L("\(type.fr), modifié \(Format.ago(file.modified, in: .fr)).",
                                "\(type.en), modified \(Format.ago(file.modified, in: .en)).")
            let name = PathRules.lastComponent(file.path)
            var entry = StorageEntry(id: "file:" + file.path, title: L(name, name), explanation: explanation, kind: .largeFile,
                                     path: file.path, size: file.size, modified: file.modified)
            if details {
                entry.lastUsed = lastUsedDate(file.path)
                entry.inICloud = LargeFiles.isInICloud(file.path)
            }
            return entry
        }
    }

    static func fileType(_ path: String) -> L {
        let ext = (path as NSString).pathExtension.lowercased()
        switch ext {
        case "mp4", "mov", "mkv", "avi", "m4v", "webm", "mts", "braw": return L("Vidéo", "Video")
        case "zip", "rar", "7z", "tar", "gz", "tgz", "xz", "bz2": return L("Archive compressée", "Compressed archive")
        case "dmg", "iso", "img", "sparseimage": return L("Image disque (souvent un installeur déjà utilisé)", "Disk image (often an installer already used)")
        case "pkg", "mpkg", "xip": return L("Installeur", "Installer")
        case "wav", "aif", "aiff", "flac", "mp3", "m4a": return L("Fichier audio", "Audio file")
        case "gguf", "safetensors", "pt", "onnx", "ckpt", "bin": return L("Modèle d'IA ou fichier binaire", "AI model or binary file")
        case "sql", "db", "sqlite", "bak", "dump": return L("Base de données ou sauvegarde", "Database or backup")
        case "vmdk", "vdi", "qcow2": return L("Disque de machine virtuelle", "Virtual machine disk")
        default:
            switch FileCategory(path: path) {
            case .document: return L("Document", "Document")
            case .image: return L("Image", "Image")
            default: return L("Gros fichier", "Large file")
            }
        }
    }
}

// MARK: - Fichiers liés à une app

/// Retrouve les dossiers d'une app dans la Bibliothèque (données, caches, réglages…), par son identifiant et son nom.
public enum AppFootprint {
    /// Vrai si Vigie a « l'accès complet au disque ». Le test lit un fichier réservé à cet accès :
    /// sans lui, la lecture échoue simplement, sans afficher de demande.
    public static func hasFullDiskAccess() -> Bool {
        FileManager.default.isReadableFile(atPath: "/Library/Application Support/com.apple.TCC/TCC.db")
    }

    struct Place {
        var relativePath: String
        var title: L
        var explanation: L
        var isPrivate: Bool
        var byIdentifier = true
    }

    /// Un dossier trouvé, avec la façon dont il a été rattaché à l'app (identifiant exact ou nom).
    public struct Found: Sendable {
        public var entry: StorageEntry
        public var byIdentifier: Bool
    }

    static let dataTitle = L("Données", "Data")
    static let dataExplanation = L("Documents internes, historique et réglages avancés de l'app.", "The app's internal documents, history and advanced settings.")
    static let cacheTitle = L("Cache", "Cache")
    static let cacheExplanation = L("Se recrée tout seul.", "Rebuilds itself.")

    /// Emplacements candidats pour une app d'identifiant `id` et de nom `name`.
    static func places(id: String, names: [String], library: String, fileManager: FileManager, appGroups: [String] = []) -> [Place] {
        var result: [Place] = []
        for key in [id] + names {
            let byIdentifier = key == id
            result.append(Place(relativePath: "Application Support/" + key, title: dataTitle, explanation: dataExplanation,
                                isPrivate: false, byIdentifier: byIdentifier))
            result.append(Place(relativePath: "Caches/" + key, title: cacheTitle, explanation: cacheExplanation,
                                isPrivate: false, byIdentifier: byIdentifier))
            result.append(Place(relativePath: "Logs/" + key, title: L("Journaux", "Logs"),
                                explanation: L("Historique technique de l'app.", "The app's technical history."),
                                isPrivate: false, byIdentifier: byIdentifier))
        }
        result += [
            Place(relativePath: "HTTPStorages/" + id, title: L("Données web", "Web data"),
                  explanation: L("Cookies et stockage web de l'app.", "The app's cookies and web storage."), isPrivate: false),
            Place(relativePath: "HTTPStorages/" + id + ".binarycookies", title: L("Cookies", "Cookies"),
                  explanation: L("Cookies de l'app.", "The app's cookies."), isPrivate: false),
            Place(relativePath: "WebKit/" + id, title: L("Données web", "Web data"),
                  explanation: L("Stockage du moteur web utilisé par l'app.", "Storage of the web engine the app uses."), isPrivate: false),
            Place(relativePath: "Preferences/" + id + ".plist", title: L("Réglages", "Settings"),
                  explanation: L("Tes réglages pour cette app.", "Your settings for this app."), isPrivate: false),
            Place(relativePath: "Saved Application State/" + id + ".savedState", title: L("État des fenêtres", "Window state"),
                  explanation: L("Fenêtres à rouvrir au prochain lancement.", "Windows to reopen on next launch."), isPrivate: false),
            Place(relativePath: "Application Scripts/" + id, title: L("Scripts de l'app", "App scripts"),
                  explanation: L("Scripts et extensions de l'app.", "The app's scripts and extensions."), isPrivate: false),
        ]
        // Programmes que l'app fait lancer automatiquement à l'ouverture de session.
        let agents = (try? fileManager.contentsOfDirectory(atPath: library + "/LaunchAgents")) ?? []
        for agent in agents where agent.hasPrefix(id) {
            result.append(Place(relativePath: "LaunchAgents/" + agent, title: L("Lancement automatique", "Starts automatically"),
                                explanation: L("Un programme de l'app démarre à l'ouverture de ta session.", "A program of the app starts when you log in."),
                                isPrivate: false))
        }
        // Dossiers privés des apps sandboxées : on lit seulement la liste des noms, jamais leur contenu sans accès complet.
        let containers = (try? fileManager.contentsOfDirectory(atPath: library + "/Containers")) ?? []
        for container in containers where container == id || container.hasPrefix(id + ".") {
            result.append(Place(relativePath: "Containers/" + container, title: L("Dossier privé de l'app", "App's private folder"),
                                explanation: L("Données que macOS range à part pour cette app (documents, caches, réglages).", "Data macOS keeps apart for this app (documents, caches, settings)."),
                                isPrivate: true))
        }
        let groups = (try? fileManager.contentsOfDirectory(atPath: library + "/Group Containers")) ?? []
        // Dossiers partagés : ceux qui portent l'identifiant, et ceux que la signature de l'app déclare (Office : « UBF8T346G9.Office »).
        for group in groups where group.contains(id) || appGroups.contains(group) {
            result.append(Place(relativePath: "Group Containers/" + group, title: L("Dossier partagé de l'app", "App's shared folder"),
                                explanation: L("Données partagées avec ses extensions ou ses autres apps.", "Data shared with its extensions or other apps."),
                                isPrivate: true))
        }
        return result
    }

    /// Chemin avec le nom exact du dernier élément tel qu'il est écrit sur le disque.
    static func onDiskPath(_ path: String, listings: inout [String: [String]], fileManager: FileManager) -> String {
        let parent = (path as NSString).deletingLastPathComponent
        let name = (path as NSString).lastPathComponent
        if listings[parent] == nil { listings[parent] = (try? fileManager.contentsOfDirectory(atPath: parent)) ?? [] }
        let names = listings[parent] ?? []
        if names.contains(name) { return path }
        return names.first { $0.caseInsensitiveCompare(name) == .orderedSame }.map { parent + "/" + $0 } ?? path
    }

    public static func related(to appPath: String, home: String = NSHomeDirectory(),
                               fullDiskAccess: Bool = hasFullDiskAccess()) -> [StorageEntry] {
        relatedDetailed(to: appPath, home: home, fullDiskAccess: fullDiskAccess).map(\.entry)
    }

    public static func relatedDetailed(to appPath: String, home: String = NSHomeDirectory(),
                                       fullDiskAccess: Bool = hasFullDiskAccess()) -> [Found] {
        var found = locate(appPath, home: home, fullDiskAccess: fullDiskAccess)
        let readable = found.indices.filter { !found[$0].entry.isProtected }
        let results = DiskUsage.measure(readable.map { DiskUsage.Request(path: found[$0].entry.path) })
        for (index, result) in zip(readable, results) {
            found[index].entry.size = result.total
            found[index].entry.isProtected = result.denied && result.total < 1_048_576
        }
        return found.sorted { ($0.entry.isProtected ? 1 : 0, $1.entry.size) < ($1.entry.isProtected ? 1 : 0, $0.entry.size) }
    }

    /// Groupes d'apps déclarés dans la signature (`com.apple.security.application-groups`), lus sans lancer l'app.
    static func applicationGroups(_ appPath: String) -> [String] {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(URL(fileURLWithPath: appPath) as CFURL, [], &code) == errSecSuccess, let code else { return [] }
        var information: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess,
              let dictionary = information as? [String: Any],
              let entitlements = dictionary[kSecCodeInfoEntitlementsDict as String] as? [String: Any] else { return [] }
        return entitlements["com.apple.security.application-groups"] as? [String] ?? []
    }

    /// Dossiers de l'app dans ~/Library, sans les mesurer. Dossiers privés : « protégé » sans l'accès complet au disque.
    public static func locate(_ appPath: String, home: String, fullDiskAccess: Bool) -> [Found] {
        let fileManager = FileManager.default
        let info = NSDictionary(contentsOfFile: appPath + "/Contents/Info.plist") as? [String: Any] ?? [:]
        guard let id = info["CFBundleIdentifier"] as? String, !id.isEmpty else { return [] }
        let names = [info["CFBundleName"], info["CFBundleDisplayName"], info["CFBundleExecutable"]]
            .compactMap { $0 as? String }
            .map(PathRules.cleanName)
            .filter { $0.count >= 3 }
            + [PathRules.bundleDisplayName(appPath)]
        let library = home + "/Library"
        var seen = Set<String>()
        var found: [Found] = []
        var listings: [String: [String]] = [:]
        for place in places(id: id, names: Array(Set(names)), library: library, fileManager: fileManager,
                            appGroups: applicationGroups(appPath)) {
            guard fileManager.fileExists(atPath: library + "/" + place.relativePath) else { continue }
            // Le disque du Mac ne distingue pas les majuscules : « claude » et « Claude » sont le même dossier.
            // On garde le nom tel qu'il est écrit sur le disque, pour ne le compter qu'une fois, ici comme entre apps.
            let path = onDiskPath(library + "/" + place.relativePath, listings: &listings, fileManager: fileManager)
            guard !seen.contains(path) else { continue }
            seen.insert(path)
            found.append(Found(entry: StorageEntry(id: "footprint:" + path, title: place.title, explanation: place.explanation,
                                                   kind: .appData, path: path, size: 0,
                                                   isProtected: place.isPrivate && !fullDiskAccess),
                               byIdentifier: place.byIdentifier))
        }
        return found
    }
}
