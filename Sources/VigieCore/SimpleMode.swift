import Foundation

// Ce que le mode Simple regroupe ou rend lisible : quelqu'un qui n'est pas développeur n'a pas à voir
// « .npm », « pnpm-store » ou « com.readdle.SparkDesktop.helper ». Rien n'est caché : c'est regroupé ou renommé.

// MARK: - Caches des outils de développement

extension StorageCatalog {
    /// Caches des outils de développement (gestionnaires de paquets, Xcode, compilateurs).
    public static let developerCacheIDs: Set<String> = [
        "dotcache", "npm", "pnpm-store", "bun", "yarn", "gradle", "maven", "cargo", "go", "derived-data", "device-support",
    ]
    public static let developerCachesID = "dev-caches"
}

extension StorageReport {
    /// Caches pour le mode Simple : ceux des outils de développement réunis en une ligne « Outils de développement »,
    /// chacun restant vidable dans son détail.
    public func cacheEntriesGroupingDeveloperTools() -> [StorageEntry] {
        let caches = entries(of: .cache)
        // « .cache » ne se vide pas d'un bloc : ses sous-dossiers (uv, pip…) entrent un par un dans le groupe.
        let developer = caches.filter { StorageCatalog.developerCacheIDs.contains($0.id) }
            .flatMap { StorageCleaner.wholeFolders.contains($0.id) ? $0.children : [$0] }
            .sorted { $0.size > $1.size }
        guard developer.count > 1 else { return caches }
        let group = StorageEntry(
            id: StorageCatalog.developerCachesID, title: L("Outils de développement", "Developer tools"),
            explanation: L("Copies que les outils de programmation gardent (paquets téléchargés, compilations). Elles se refont toutes seules si tu t'en sers encore. Vide-les une par une ci-dessous.",
                           "Copies programming tools keep (downloaded packages, builds). They come back on their own if you still use them. Clear them one by one below."),
            kind: .cache, path: "", size: caches.filter { StorageCatalog.developerCacheIDs.contains($0.id) }.reduce(0) { $0 + $1.size },
            children: developer)
        return (caches.filter { !StorageCatalog.developerCacheIDs.contains($0.id) } + [group]).sorted { $0.size > $1.size }
    }
}

// MARK: - Dossiers cachés de l'explorateur

extension FolderListing {
    /// Chemin fictif du bloc qui réunit les dossiers cachés (il n'existe pas sur le disque).
    public static let hiddenGroupName = ".dossiers-caches"

    public var hiddenGroupPath: String { path + "/" + Self.hiddenGroupName }

    /// Les dossiers et fichiers cachés (« .npm », « .cache »…) réunis en un bloc « Dossiers cachés ».
    public func groupingHiddenItems(title: String) -> (listing: FolderListing, members: [Item]) {
        let hidden = items.filter { $0.name.hasPrefix(".") }
        guard hidden.count > 1 else { return (self, []) }
        var listing = self
        listing.items = items.filter { !$0.name.hasPrefix(".") }
        listing.items.append(Item(name: title, path: hiddenGroupPath, size: hidden.reduce(0) { $0 + $1.size }, isDirectory: false))
        listing.items.sort { $0.size > $1.size }
        return (listing, hidden)
    }
}

extension ExplorerAdvice {
    /// Le bloc « Dossiers cachés » : à garder dans l'ensemble, avec ce qu'il contient de récupérable.
    public static func adviseHiddenGroup(members: [FolderListing.Item], home: String, report: StorageReport?) -> ExplorerAdvice {
        var reclaimable: UInt64 = 0
        for member in members {
            let advice = advise(path: member.path, home: home, report: report)
            reclaimable += advice.level == .safe ? member.size : advice.reclaimableInside
        }
        let names = members.prefix(4).map(\.name).joined(separator: ", ")
        var advice = ExplorerAdvice(level: .keep,
                              explanation: L("Dossiers cachés (\(names)…) : réglages et données de tes outils et de tes apps. Ce qui s'y vide sans risque se trouve dans « Fichiers temporaires ».",
                                             "Hidden folders (\(names)…): settings and data of your tools and apps. What can be safely cleared there is in “Temporary files”."),
                              reclaimableInside: reclaimable)
        advice.reclaimableKind = reclaimable > 0 ? .cache : nil
        return advice
    }
}

// MARK: - Nom lisible d'un reste d'app

extension LeftoverFinder {
    /// Mots qui ne disent pas de quelle app il s'agit.
    static let genericWords: Set<String> = ["mac", "macos", "osx", "desktop", "app", "helper", "agent", "client", "console", "search",
                                            "launcher", "daemon", "service", "plugin", "extension", "updater", "login", "loginitem"]

    /// « com.readdle.SparkDesktop.helper » → « Spark », « org.mozilla.firefox » → « Firefox »,
    /// « com.parallels.desktop.console » → « Parallels ». nil si rien de lisible n'en sort.
    public static func appName(fromIdentifier identifier: String) -> String? {
        var parts = identifier.split(separator: ".").map(String.init)
        if let first = parts.first, topLevelDomains.contains(first.lowercased()) { parts.removeFirst() }
        guard let vendor = parts.first else { return nil }
        for part in parts.dropFirst() {
            let words = camelWords(part).filter { !genericWords.contains($0.lowercased()) }
            if !words.isEmpty { return capitalized(words.joined()) }
        }
        let vendorWords = camelWords(vendor).filter { !genericWords.contains($0.lowercased()) }
        return vendorWords.isEmpty ? nil : capitalized(vendorWords.joined())
    }

    /// « SparkDesktop » → [« Spark », « Desktop »] ; « setapp-agent » → [« setapp », « agent »].
    static func camelWords(_ text: String) -> [String] {
        var words: [String] = []
        var current = ""
        for character in text {
            if character == "-" || character == "_" {
                if !current.isEmpty { words.append(current) }
                current = ""
            } else if character.isUppercase, let last = current.last, last.isLowercase {
                words.append(current)
                current = String(character)
            } else {
                current.append(character)
            }
        }
        if !current.isEmpty { words.append(current) }
        return words
    }

    static func capitalized(_ text: String) -> String {
        guard let first = text.first else { return text }
        return first.uppercased() + text.dropFirst()
    }
}

extension StorageEntry {
    /// Titre affiché : le nom de l'app pour un reste d'app (« Spark »), sinon le titre.
    public var displayTitle: String {
        if id.hasPrefix("leftover:"), let name = LeftoverFinder.appName(fromIdentifier: String(id.dropFirst("leftover:".count))) {
            return name
        }
        return title.text
    }

    /// Identifiant de l'app d'un reste (« com.readdle.SparkDesktop.helper »).
    public var leftoverIdentifier: String? {
        id.hasPrefix("leftover:") ? String(id.dropFirst("leftover:".count)) : nil
    }
}
