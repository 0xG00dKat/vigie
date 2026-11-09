import Foundation

// MARK: - Désinstallation

/// Désinstaller une app avec ses restes. Tout va à la corbeille (on peut revenir en arrière) ; l'app est quittée d'abord.
public enum AppUninstaller {
    public struct Item: Sendable, Equatable, Identifiable {
        public var id: String { path }
        public var path: String
        public var title: L
        public var size: UInt64
        /// Coché au départ.
        public var selected: Bool
        /// Pourquoi on ne peut pas le cocher (protégé, partagé avec une autre app), sinon nil.
        public var blocked: L?
    }

    /// Jamais les apps de macOS (`com.apple.*`), ni Vigie, ni ce qui n'est pas dans /Applications ou ~/Applications.
    public static func canUninstall(_ entry: StorageEntry, home: String = NSHomeDirectory(), ownBundleID: String? = Bundle.main.bundleIdentifier) -> Bool {
        guard entry.kind == .application, entry.path.hasSuffix(".app"),
              entry.path.hasPrefix("/Applications/") || entry.path.hasPrefix(home + "/Applications/") else { return false }
        let id = bundleID(entry.path) ?? ""
        return !id.hasPrefix("com.apple.") && id != ownBundleID
    }

    public static func bundleID(_ appPath: String) -> String? {
        (NSDictionary(contentsOfFile: appPath + "/Contents/Info.plist") as? [String: Any])?["CFBundleIdentifier"] as? String
    }

    /// Ce qui partirait : l'app, puis ses dossiers. Un dossier protégé ou partagé avec une autre app reste décoché.
    public static func items(for entry: StorageEntry) -> [Item] {
        let appSize = entry.size - entry.children.reduce(UInt64(0)) { $0 + $1.size }
        var items = [Item(path: entry.path, title: L("L'app \(entry.title.fr)", "The \(entry.title.en) app"), size: appSize, selected: true, blocked: nil)]
        for child in entry.children {
            var blocked: L?
            if let others = child.sharedWith, !others.isEmpty {
                let list = others.joined(separator: ", ")
                blocked = L("partagé avec \(list)", "shared with \(list)")
            } else if child.isProtected {
                blocked = L("protégé : accès complet au disque", "protected: Full Disk Access")
            } else if child.id == "footprint:docker" || child.path.hasSuffix("/Docker.raw") {
                // Rangé dans le dossier privé de Docker : il part avec lui, pas seul.
                blocked = L("dans le dossier privé de l'app", "inside the app's private folder")
            }
            items.append(Item(path: child.path, title: child.title, size: child.size, selected: blocked == nil, blocked: blocked))
        }
        return items
    }
}

// MARK: - Restes d'apps supprimées

/// Dossiers de ~/Library laissés par des apps qui ne sont plus installées. Prudent : seuls les noms en forme
/// d'identifiant (« com.editeur.app ») comptent, et jamais ceux d'un éditeur dont une app est encore installée
/// (« com.google.Keystone » reste tant que Chrome est là), ni ceux d'Apple ou des bibliothèques courantes.
public enum LeftoverFinder {
    public struct Leftover: Sendable, Equatable {
        public var id: String
        public var paths: [String]
    }

    /// Pas les agents de lancement : ce peuvent être tes propres scripts (un ménage programmé, par exemple).
    static let places = ["Application Support", "Caches", "HTTPStorages", "WebKit", "Saved Application State", "Preferences", "Logs"]
    static let topLevelDomains: Set<String> = ["com", "io", "org", "net", "app", "dev", "co", "me", "ai", "so", "us", "de", "fr", "uk",
                                               "ch", "nl", "se", "jp", "cn", "ru", "info", "tv", "sh", "xyz", "tech", "studio", "design", "cc", "is"]
    /// Bibliothèques embarquées dans beaucoup d'apps : leurs dossiers ne disent pas quelle app a disparu.
    /// Bibliothèques et outils en ligne de commande (SwiftPM, Vercel, Firebase…) : ce ne sont pas des apps disparues.
    static let libraries: [String] = ["org.sparkle-project", "com.crashlytics", "com.plausiblelabs", "io.sentry", "com.github.electron",
                                      "com.google.keystone", "com.microsoft.autoupdate", "com.adobe.acc", "org.swift", "org.cups",
                                      "com.segment", "com.firebase", "io.branch", "com.hackemist", "com.bugsnag", "com.breakpad",
                                      "com.yourcompany", "com.install4j", "dev.reactnative", "org.webkit", "org.nodejs", "org.python"]

    /// Identifiant d'app tiré d'un nom de dossier ou de fichier, s'il en a la forme.
    static func identifier(from name: String) -> String? {
        var id = name
        for suffix in [".plist", ".savedState", ".binarycookies"] where id.hasSuffix(suffix) {
            id = String(id.dropLast(suffix.count))
        }
        let parts = id.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 3, parts.allSatisfy({ !$0.isEmpty }),
              topLevelDomains.contains(parts[0].lowercased()),
              id.allSatisfy({ $0.isLetter || $0.isNumber || "._-".contains($0) }) else { return nil }
        return id
    }

    /// Nom lisible de l'endroit où un reste a été trouvé.
    public static func placeTitle(_ place: String) -> L {
        switch place {
        case "Application Support": return L("Données", "Data")
        case "Caches": return L("Cache", "Cache")
        case "HTTPStorages", "WebKit": return L("Données web", "Web data")
        case "Saved Application State": return L("État des fenêtres", "Window state")
        case "Preferences": return L("Réglages", "Settings")
        case "Logs": return L("Journaux", "Logs")
        default: return L(place, place)
        }
    }

    static func vendor(_ id: String) -> String {
        id.lowercased().split(separator: ".").prefix(2).joined(separator: ".")
    }

    /// Identifiants des apps installées (toutes celles que Spotlight connaît, plus /Applications et ~/Applications).
    public static func installedIdentifiers(home: String = NSHomeDirectory()) -> Set<String> {
        var paths = Set<String>()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/mdfind")
        process.arguments = ["kMDItemContentType == 'com.apple.application-bundle'"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        if (try? process.run()) != nil {
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            String(decoding: data, as: UTF8.self).split(separator: "\n").forEach { paths.insert(String($0)) }
        }
        for folder in ["/Applications", "/Applications/Utilities", "/System/Applications", "/System/Applications/Utilities", home + "/Applications"] {
            for name in (try? FileManager.default.contentsOfDirectory(atPath: folder)) ?? [] where name.hasSuffix(".app") {
                paths.insert(folder + "/" + name)
            }
        }
        return Set(paths.compactMap { AppUninstaller.bundleID($0) })
    }

    public static func find(home: String = NSHomeDirectory(), installed: Set<String>, ownBundleID: String? = "io.github.0xg00dkat.vigie") -> [Leftover] {
        let installedVendors = Set(installed.map(vendor))
        let installedLower = Set(installed.map { $0.lowercased() })
        var byID: [String: [String]] = [:]
        let library = home + "/Library"
        for place in places {
            for name in (try? FileManager.default.contentsOfDirectory(atPath: library + "/" + place)) ?? [] {
                guard let id = identifier(from: name) else { continue }
                let lower = id.lowercased()
                // Un outil en ligne de commande (« com.vercel.cli ») n'est pas une app.
                if lower.split(separator: ".").contains(where: { $0 == "cli" }) { continue }
                guard !lower.hasPrefix("com.apple."), lower != ownBundleID?.lowercased(),
                      !libraries.contains(where: { lower.hasPrefix($0) }),
                      !installedVendors.contains(vendor(lower)),
                      !installedLower.contains(where: { lower.hasPrefix($0) || $0.hasPrefix(lower) }) else { continue }
                byID[id, default: []].append(library + "/" + place + "/" + name)
            }
        }
        return byID.map { Leftover(id: $0.key, paths: $0.value.sorted()) }.sorted { $0.id < $1.id }
    }
}

// MARK: - Nettoyer ce qui est sûr

/// Ce que le bouton « Nettoyer ce qui est sûr » vide d'un coup : les caches qui se recréent vite,
/// avec leur commande officielle quand elle existe. Pas les modèles d'IA ni les navigateurs de test
/// (longs à retélécharger), pas les projets, pas les apps : ceux-là se regardent d'abord.
public enum SafeCleanup {
    static let slowToRebuild: Set<String> = ["huggingface", "ms-playwright", "puppeteer", "codex-runtimes", "prisma"]

    public static func items(in report: StorageReport, home: String = NSHomeDirectory()) -> [StorageEntry] {
        var items: [StorageEntry] = []
        for entry in report.entries(of: .cache) {
            if StorageCleaner.wholeFolders.contains(entry.id) {
                for child in entry.children where isSafe(child, home: home) { items.append(child) }
            } else if isSafe(entry, home: home) {
                items.append(entry)
            }
        }
        return items.sorted { $0.size > $1.size }
    }

    static func isSafe(_ entry: StorageEntry, home: String) -> Bool {
        guard entry.size > 0, !slowToRebuild.contains(entry.title.fr), !slowToRebuild.contains(PathRules.lastComponent(entry.path)) else { return false }
        switch StorageCleaner.cleanup(for: entry, home: home) {
        case .command?, .delete?: return true
        default: return false
        }
    }
}

// MARK: - Données système

/// Ressources que macOS télécharge et range dans « Données système » (`/System/Library/AssetsV2`),
/// regroupées par usage. macOS les gère : Vigie les montre, sans proposer de les toucher.
public enum SystemAssets {
    public static let path = "/System/Library/AssetsV2"

    struct Group {
        var id: String
        var title: L
        var explanation: L
        var command: String?
        var matches: (String) -> Bool
    }

    static let groups: [Group] = [
        Group(id: "simulator-runtimes", title: L("Systèmes des simulateurs iOS", "iOS simulator runtimes"),
              explanation: L("Les iOS que Xcode télécharge pour ses simulateurs. Retire ceux qui ne servent plus dans Xcode › Réglages › Composants.",
                             "The iOS versions Xcode downloads for its simulators. Remove unused ones in Xcode › Settings › Components."),
              command: "xcrun simctl runtime list", matches: { $0.contains("SimulatorRuntime") }),
        Group(id: "intelligence", title: L("Modèles de Siri et d'Apple Intelligence", "Siri and Apple Intelligence models"),
              explanation: L("Modèles d'IA, reconnaissance vocale et voix. macOS les gère ; désactiver Apple Intelligence dans les Réglages en retire une partie.",
                             "AI models, speech recognition and voices. macOS manages them; turning off Apple Intelligence in Settings removes some."),
              matches: { $0.contains("_UAF_") }),
        Group(id: "developer-docs", title: L("Documentation de Xcode", "Xcode documentation"),
              explanation: L("Documentation pour développeurs téléchargée par Xcode.", "Developer documentation downloaded by Xcode."),
              matches: { $0.contains("DeveloperDocumentation") }),
        Group(id: "macos-update", title: L("Mise à jour de macOS téléchargée", "Downloaded macOS update"),
              explanation: L("macOS la retire après l'installation.", "macOS removes it after installing."),
              matches: { $0.contains("SoftwareUpdate") }),
        Group(id: "other", title: L("Autres ressources de macOS", "Other macOS resources"),
              explanation: L("Polices, dictionnaires, outils de compilation… téléchargés par macOS à la demande.",
                             "Fonts, dictionaries, build tools… downloaded by macOS on demand."),
              matches: { _ in true }),
    ]

    /// Une ligne par usage, à partir des sous-dossiers d'AssetsV2 mesurés.
    public static func entries(from children: [(name: String, size: UInt64)], minimumSize: UInt64) -> [StorageEntry] {
        var sizes: [String: UInt64] = [:]
        for child in children {
            let group = groups.first { $0.matches(child.name) }!
            sizes[group.id, default: 0] += child.size
        }
        return groups.compactMap { group in
            guard let size = sizes[group.id], size >= minimumSize else { return nil }
            return StorageEntry(id: "system:" + group.id, title: group.title, explanation: group.explanation, kind: .systemData,
                                path: path, size: size, command: group.command)
        }
    }
}
