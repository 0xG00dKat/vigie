import Foundation

/// Ce que Vigie peut dire d'un bloc de l'explorateur : peut-on le vider, faut-il le vérifier, ou le garder ?
/// La carte se colore avec, et le détail d'un bloc propose l'action qui va avec.
///
/// D'abord l'analyse du stockage (même chemin : son explication et son nettoyage), puis ce qu'elle a trouvé
/// de récupérable à l'intérieur (caches, `node_modules`), et sinon des règles sur les emplacements connus.
public struct ExplorerAdvice: Sendable, Equatable {
    public enum Level: Sendable, Equatable {
        /// Se recrée tout seul : se vide sans risque.
        case safe
        /// À regarder avant (restes d'apps, gros fichiers, téléchargements, apps).
        case review
        /// À garder, ou géré par macOS ou par l'app.
        case keep
        /// Rien à en dire.
        case unknown
    }

    public var level: Level
    public var explanation: L?
    /// Ligne de l'analyse au même chemin : son nettoyage (s'il y en a un) se lance depuis le détail.
    public var entry: StorageEntry?
    /// Ce qui se vide sans risque à l'intérieur (caches, `node_modules`), d'après l'analyse.
    public var reclaimableInside: UInt64
    /// Où le voir en détail : « Caches » ou « Projets », selon ce qui pèse le plus.
    public var reclaimableKind: StorageKind?

    public init(level: Level, explanation: L? = nil, entry: StorageEntry? = nil, reclaimableInside: UInt64 = 0) {
        self.level = level
        self.explanation = explanation
        self.entry = entry
        self.reclaimableInside = reclaimableInside
    }

    public static func level(of kind: StorageKind) -> Level {
        switch kind {
        case .cache, .project: return .safe
        case .leftover, .largeFile, .application: return .review
        case .appData, .personal, .systemData: return .keep
        }
    }

    public static func advise(path: String, home: String, report: StorageReport?) -> ExplorerAdvice {
        let entries = report.map(flatten) ?? []
        if let entry = entries.first(where: { $0.path == path && !$0.isProtected }) {
            var advice = ExplorerAdvice(level: level(of: entry.kind), explanation: entry.explanation, entry: entry)
            // Les téléchargements sont « tes fichiers », mais surtout des installeurs déjà utilisés : à trier.
            if entry.id == "downloads" { advice.level = .review }
            if advice.level != .safe { (advice.reclaimableInside, advice.reclaimableKind) = reclaimable(under: path, in: entries) }
            return advice
        }
        var advice = rule(path: path, home: home)
        (advice.reclaimableInside, advice.reclaimableKind) = reclaimable(under: path, in: entries)
        return advice
    }

    /// Lignes de l'analyse et leurs sous-dossiers.
    static func flatten(_ report: StorageReport) -> [StorageEntry] {
        report.entries.flatMap { [$0] + $0.children }
    }

    /// Caches et `node_modules` sous ce chemin, chacun compté une fois (pas un dossier et son sous-dossier).
    static func reclaimable(under path: String, in entries: [StorageEntry]) -> (UInt64, StorageKind?) {
        let safe = entries.filter { level(of: $0.kind) == .safe && $0.path.hasPrefix(path + "/") && !$0.isProtected }
        let counted = safe.filter { entry in !safe.contains { $0.path != entry.path && entry.path.hasPrefix($0.path + "/") } }
        let total = counted.reduce(UInt64(0)) { $0 + $1.size }
        guard total > 0 else { return (0, nil) }
        let projects = counted.filter { $0.kind == .project }.reduce(UInt64(0)) { $0 + $1.size }
        return (total, projects * 2 > total ? .project : .cache)
    }

    /// Emplacements connus du dossier personnel, quand l'analyse ne dit rien.
    static func rule(path: String, home: String) -> ExplorerAdvice {
        let name = PathRules.lastComponent(path)
        if name == "node_modules" || path.contains("/node_modules/") {
            return ExplorerAdvice(level: .safe, explanation: L("Dépendances d'un projet : « npm install » les réinstalle.",
                                                                "A project's dependencies: “npm install” reinstalls them."))
        }
        guard path.hasPrefix(home + "/") else { return ExplorerAdvice(level: .unknown) }
        let relative = String(path.dropFirst(home.count + 1))
        switch relative {
        case "Library/Caches", ".cache":
            return ExplorerAdvice(level: .safe, explanation: L("Caches : ils se recréent tout seuls. Vigie les vide un par un, dans « Caches ».",
                                                                "Caches: they rebuild themselves. Vigie clears them one by one, in “Caches”."))
        case "Downloads":
            return ExplorerAdvice(level: .review, explanation: L("Tes téléchargements : souvent des installeurs et des fichiers déjà utilisés. À trier.",
                                                                  "Your downloads: often installers and files you've already used. Worth sorting."))
        case ".Trash":
            return ExplorerAdvice(level: .review, explanation: L("La corbeille : la place revient quand tu la vides.",
                                                                  "The Trash: the space comes back when you empty it."))
        case "Desktop", "Documents", "Pictures", "Movies", "Music", "Public":
            return ExplorerAdvice(level: .keep, explanation: L("Tes fichiers : Vigie n'y touche jamais d'elle-même.",
                                                                "Your files: Vigie never touches them on its own."))
        case "Library":
            return ExplorerAdvice(level: .keep, explanation: L("La bibliothèque : réglages, données et caches des apps. Les caches se vident dans « Caches ».",
                                                                "The Library: apps' settings, data and caches. Caches are cleared in “Caches”."))
        case "Library/Application Support", "Library/Containers", "Library/Group Containers", "Library/Preferences", "Library/Mail", "Library/Messages":
            return ExplorerAdvice(level: .keep, explanation: L("Données des apps : à garder, ou à nettoyer depuis l'app elle-même.",
                                                                "App data: keep it, or clean up from the app itself."))
        default:
            if !relative.contains("/") && name.hasPrefix(".") {
                return ExplorerAdvice(level: .keep, explanation: L("Dossier caché d'un outil : ses réglages ou ses données.",
                                                                    "A tool's hidden folder: its settings or data."))
            }
            return ExplorerAdvice(level: .unknown)
        }
    }
}

/// Ce que contient un bloc de l'explorateur, pour le colorer par type (photos, documents, apps, dev…).
/// Une indication pour se repérer, pas un conseil : ce qu'on peut jeter reste dit par `ExplorerAdvice`.
public enum ContentKind: String, CaseIterable, Sendable {
    case media, documents, apps, dev, caches, system, other

    public var title: L {
        switch self {
        case .media: return L("Photos, vidéos, musique", "Photos, videos, music")
        case .documents: return L("Documents", "Documents")
        case .apps: return L("Apps", "Apps")
        case .dev: return L("Projets et outils de dev", "Projects and dev tools")
        case .caches: return L("Caches", "Caches")
        case .system: return L("Réglages et données des apps", "App settings and data")
        case .other: return L("Autres", "Other")
        }
    }

    static let devNames: Set<String> = [
        "code", "dev", "developer", "projects", "projets", "src", "repos", "git", "github", "workspace", "sites",
        ".npm", ".cargo", ".rustup", ".gradle", ".m2", ".nvm", ".fnm", ".volta", ".pyenv", ".rbenv", ".rvm", ".asdf",
        ".bun", ".pnpm-store", ".yarn", ".docker", ".orbstack", ".colima", ".vscode", ".cursor", ".local", ".deno",
        ".gem", ".conda", "miniconda3", "anaconda3", "go", "node_modules", ".android", ".expo", ".swiftpm", ".hermes",
    ]
    static let cacheNames: Set<String> = [".cache", "caches", "cache", "deriveddata"]
    static let mediaNames: Set<String> = ["movies", "pictures", "music", "photos"]
    static let mediaPackages = ["photoslibrary", "musiclibrary", "imovielibrary", "fcpbundle", "tvlibrary", "photolibrary"]
    static let documentNames: Set<String> = ["documents", "desktop", "downloads"]

    public init(path: String, isDirectory: Bool) {
        let name = (path as NSString).lastPathComponent.lowercased()
        let ext = (name as NSString).pathExtension
        if Self.cacheNames.contains(name) || path.contains("/Library/Caches") {
            self = .caches
        } else if Self.devNames.contains(name) || path.contains("/Library/Developer") || ext == "xcodeproj" {
            self = .dev
        } else if name == "applications" || ext == "app" {
            self = .apps
        } else if Self.mediaNames.contains(name) || Self.mediaPackages.contains(ext) {
            self = .media
        } else if Self.documentNames.contains(name) {
            self = .documents
        } else if !isDirectory {
            switch FileCategory(path: path) {
            case .video, .image, .audio: self = .media
            case .document, .archive: self = .documents
            case .other: self = path.contains("/Library/") ? .system : .other
            }
        } else if name == "library" || path.contains("/Library/") || name.hasPrefix(".") {
            self = .system
        } else {
            self = .other
        }
    }
}
