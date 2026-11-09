import Foundation

/// Transforme la liste brute des processus en groupes lisibles :
/// une ligne par app (avec ses processus d'aide), une ligne par projet de dev, etc.
public struct GroupBuilder {
    public var runningApps: [RunningApp]
    public var myUID: UInt32
    public var myPID: Int32
    public var homeDirectory: String
    public var protectedBundleIDs: Set<String>
    public var details: (RawProcess) -> ProcessDetails
    public var bundleInfo: (String) -> BundleInfo?

    public init(
        runningApps: [RunningApp],
        myUID: UInt32,
        myPID: Int32,
        homeDirectory: String,
        protectedBundleIDs: Set<String>,
        details: @escaping (RawProcess) -> ProcessDetails = { _ in .empty },
        bundleInfo: @escaping (String) -> BundleInfo? = { _ in nil }
    ) {
        self.runningApps = runningApps
        self.myUID = myUID
        self.myPID = myPID
        self.homeDirectory = PathRules.normalize(homeDirectory)
        self.protectedBundleIDs = protectedBundleIDs
        self.details = details
        self.bundleInfo = bundleInfo
    }

    enum Slot: Equatable {
        /// Dans un paquet .app (clé = chemin du paquet retenu).
        case bundle(String)
        /// Outil de dev ou de ligne de commande.
        case dev
        /// Programme tiers hors paquet (agent installé dans /Library…).
        case thirdParty
        /// Processus système de l'utilisateur (shell, service XPC…) : rattaché à son app si possible.
        case orphan
        /// Processus d'un autre utilisateur (root, _spotlight…).
        case foreign
    }

    private enum Owner {
        case bundle(String)
        case dev(String)
    }

    private struct DevBucket {
        var title: String
        var location: String?
        var directory: String?
        var processes: [RawProcess] = []
        var launchers: [String: Int] = [:]
        var orphanCount = 0
    }

    public func build(_ input: [RawProcess]) -> [ProcessGroup] {
        let byPID = Dictionary(input.map { ($0.pid, $0) }, uniquingKeysWith: { first, _ in first })

        var appsByBundle: [String: [RunningApp]] = [:]
        for app in runningApps {
            appsByBundle[PathRules.normalize(app.bundlePath), default: []].append(app)
        }

        var appByPID: [Int32: RunningApp] = [:]
        for app in runningApps { appByPID[app.pid] = app }

        var slots: [Int32: Slot] = [:]
        for process in input {
            slots[process.pid] = slot(for: process, appsByBundle: appsByBundle, appByPID: appByPID)
        }

        var categoryCache: [String: ProcessCategory] = [:]
        func bundleCategory(_ key: String) -> ProcessCategory {
            if let cached = categoryCache[key] { return cached }
            let category: ProcessCategory
            if Self.nestedRegularApps(of: key, appsByBundle: appsByBundle).isEmpty == false
                || (appsByBundle[key] ?? []).contains(where: { $0.policy == .regular }) {
                category = .apps
            } else if PathRules.isSystem(key) {
                category = .system
            } else {
                category = .background
            }
            categoryCache[key] = category
            return category
        }

        // Un paquet d'aide sans Dock lancé par une app ouverte (les « Helper » de Chromium et d'Electron,
        // y compris quand l'app tourne depuis une copie temporaire après une mise à jour) appartient à cette app.
        func openAppBundle(_ pid: Int32) -> String? {
            if case .bundle(let key)? = slots[pid], bundleCategory(key) == .apps { return key }
            return nil
        }
        for process in input where process.pid != myPID {
            guard case .bundle(let key)? = slots[process.pid], bundleCategory(key) == .background else { continue }
            if let owner = openAppBundle(process.ppid) ?? process.responsiblePID.flatMap(openAppBundle) {
                slots[process.pid] = .bundle(owner)
            }
        }

        func userBundle(_ pid: Int32) -> String? {
            if case .bundle(let key)? = slots[pid], bundleCategory(key) != .system { return key }
            return nil
        }

        /// Première app (hors système) parmi les ancêtres, puis l'app « responsable » selon macOS.
        func launcherBundle(of process: RawProcess) -> String? {
            var current = process.ppid
            var steps = 0
            while current > 1, steps < 64 {
                if let key = userBundle(current) { return key }
                current = byPID[current]?.ppid ?? 0
                steps += 1
            }
            if let responsible = process.responsiblePID, let key = userBundle(responsible) { return key }
            return nil
        }

        // 1. Outils de dev, rangés par dossier de projet. Sans projet, un processus suit son parent de dev
        //    (les serveurs MCP suivent leur session Claude Code) ; à défaut, il est rangé par outil.

        // Les programmes empaquetés dans une app fermée et lancés par un outil de dev
        // (le serveur MCP livré dans Pen.app, par exemple) sont traités comme des outils de dev.
        for process in input where process.uid == myUID {
            guard case .bundle(let key)? = slots[process.pid], bundleCategory(key) == .background,
                  appsByBundle[key] == nil, slots[process.ppid] == .dev else { continue }
            slots[process.pid] = .dev
        }

        var enrichedByPID: [Int32: RawProcess] = [:]
        var projectByPID: [Int32: String] = [:]
        for process in input where slots[process.pid] == .dev {
            let found = details(process)
            var enriched = process
            enriched.cwd = found.cwd
            enriched.arguments = found.arguments
            enriched.listeningPorts = found.listeningPorts
            enriched.exposedPorts = found.exposedPorts
            enriched.name = PathRules.devDisplayName(path: process.path, fallback: process.name, arguments: found.arguments)
            enrichedByPID[process.pid] = enriched
            if let cwd = found.cwd, PathRules.isProjectDirectory(cwd, home: homeDirectory) {
                projectByPID[process.pid] = PathRules.normalize(cwd)
            }
        }

        func nearestDevAncestor(_ pid: Int32) -> Int32? {
            var current = byPID[pid]?.ppid ?? 0
            var steps = 0
            while current > 1, steps < 64 {
                if enrichedByPID[current] != nil { return current }
                current = byPID[current]?.ppid ?? 0
                steps += 1
            }
            return nil
        }

        var devKeyByPID: [Int32: String] = [:]
        var devBuckets: [String: DevBucket] = [:]
        func devKey(_ pid: Int32) -> String {
            if let known = devKeyByPID[pid] { return known }
            let process = enrichedByPID[pid]!
            let key: String
            if let directory = projectByPID[pid] {
                key = "dev:dir:" + directory
                if devBuckets[key] == nil {
                    devBuckets[key] = DevBucket(
                        title: PathRules.lastComponent(directory),
                        location: PathRules.abbreviate(directory, home: homeDirectory),
                        directory: directory
                    )
                }
            } else if let parent = nearestDevAncestor(pid) {
                key = devKey(parent)
            } else {
                let launcher = launcherBundle(of: process).map { bundleTitle($0, appsByBundle: appsByBundle) }
                key = "dev:tool:" + process.name + "|" + (launcher ?? "-")
                if devBuckets[key] == nil {
                    devBuckets[key] = DevBucket(title: process.name, location: nil, directory: nil)
                }
            }
            devKeyByPID[pid] = key
            return key
        }

        for process in input where slots[process.pid] == .dev {
            let key = devKey(process.pid)
            let enriched = enrichedByPID[process.pid]!
            devBuckets[key]!.processes.append(enriched)
            if let launcher = launcherBundle(of: process).map({ bundleTitle($0, appsByBundle: appsByBundle) }) {
                devBuckets[key]!.launchers[launcher, default: 0] += 1
            }
            if process.ppid == 1 { devBuckets[key]!.orphanCount += 1 }
        }

        func nearestOwner(of process: RawProcess) -> Owner? {
            var current = process.ppid
            var steps = 0
            while current > 1, steps < 64 {
                if let key = devKeyByPID[current] { return .dev(key) }
                if let key = userBundle(current) { return .bundle(key) }
                current = byPID[current]?.ppid ?? 0
                steps += 1
            }
            if let responsible = process.responsiblePID {
                if let key = devKeyByPID[responsible] { return .dev(key) }
                if let key = userBundle(responsible) { return .bundle(key) }
            }
            return nil
        }

        // 2. Le reste : paquets .app, processus rattachés, système et programmes tiers.
        var bundleBuckets: [String: [RawProcess]] = [:]
        var namedBuckets: [String: (category: ProcessCategory, processes: [RawProcess])] = [:]

        for process in input {
            switch slots[process.pid] ?? .foreign {
            case .dev:
                continue
            case .bundle(let key):
                bundleBuckets[key, default: []].append(process)
            case .orphan:
                switch nearestOwner(of: process) {
                case .dev(let key)?:
                    devBuckets[key]?.processes.append(process)
                case .bundle(let key)?:
                    bundleBuckets[key, default: []].append(process)
                case nil:
                    namedBuckets["sys:" + process.name, default: (.system, [])].processes.append(process)
                }
            case .foreign:
                namedBuckets["sys:" + process.name, default: (.system, [])].processes.append(process)
            case .thirdParty:
                namedBuckets["bg:" + process.name, default: (.background, [])].processes.append(process)
            }
        }

        var groups: [ProcessGroup] = []

        for (key, processes) in bundleBuckets {
            groups.append(makeBundleGroup(key: key, processes: processes, category: bundleCategory(key), appsByBundle: appsByBundle))
        }

        for (key, bucket) in devBuckets {
            let launcher = bucket.launchers.max { $0.value < $1.value }?.key
            let own = ownPIDs(bucket.processes)
            groups.append(ProcessGroup(
                id: key,
                category: .dev,
                title: bucket.title,
                location: bucket.location,
                explanation: Explainer.forDev(bucket.processes),
                executablePath: bucket.processes.max { ($0.memory ?? 0) < ($1.memory ?? 0) }?.path,
                directory: bucket.directory,
                processes: bucket.processes,
                launchedBy: launcher,
                isOrphan: launcher == nil && bucket.orphanCount > 0,
                close: own.isEmpty ? .notAllowed(tr("Rien à arrêter.", "Nothing to stop.")) : .signal(own),
                isProtected: false
            ))
        }

        for (key, bucket) in namedBuckets {
            let sample = bucket.processes.max { ($0.memory ?? 0) < ($1.memory ?? 0) } ?? bucket.processes[0]
            let name = sample.name
            if bucket.category == .system {
                groups.append(ProcessGroup(
                    id: key,
                    category: .system,
                    title: name,
                    explanation: Explainer.forSystem(name: name, path: sample.path, isOtherUser: sample.uid != myUID),
                    executablePath: sample.path,
                    processes: bucket.processes,
                    close: .notAllowed(tr("Fait partie de macOS ou d'un service administrateur.", "Part of macOS or an administrator service.")),
                    isProtected: true
                ))
            } else {
                let own = ownPIDs(bucket.processes)
                groups.append(ProcessGroup(
                    id: key,
                    category: .background,
                    title: name,
                    location: PathRules.abbreviate((sample.path as NSString).deletingLastPathComponent, home: homeDirectory),
                    explanation: Explainer.forThirdParty(name: name, path: sample.path),
                    executablePath: sample.path,
                    processes: bucket.processes,
                    close: own.isEmpty ? .notAllowed(tr("Appartient à un autre utilisateur.", "Belongs to another user.")) : .signal(own),
                    isProtected: false
                ))
            }
        }

        let order = Dictionary(uniqueKeysWithValues: ProcessCategory.allCases.enumerated().map { ($1, $0) })
        return groups.sorted {
            if $0.category != $1.category { return order[$0.category]! < order[$1.category]! }
            if $0.memory != $1.memory { return $0.memory > $1.memory }
            return $0.title.localizedStandardCompare($1.title) == .orderedAscending
        }
    }

    // MARK: - Détails

    func slot(for process: RawProcess, appsByBundle: [String: [RunningApp]], appByPID: [Int32: RunningApp] = [:]) -> Slot {
        let path = process.path
        let candidates = PathRules.bundleCandidates(path)
        if !candidates.isEmpty {
            // Le paquet le plus intérieur qui est une app du Dock (Simulator dans Xcode), sinon le plus extérieur :
            // les « Opera Helper.app » (enregistrés comme apps de barre des menus) sont rangés sous Opera.
            if let innerIndex = candidates.lastIndex(where: { candidate in
                (appsByBundle[candidate] ?? []).contains { $0.policy == .regular }
            }) {
                // Si un paquet plus extérieur est lui aussi une app ouverte, tout va sous lui :
                // la fenêtre « Docker Desktop.app » vit dans Docker.app, dont elle fait partie.
                if let outer = candidates[..<innerIndex].first(where: { candidate in
                    (appsByBundle[candidate] ?? []).contains { $0.policy != .prohibited }
                }) {
                    return .bundle(outer)
                }
                return .bundle(candidates[innerIndex])
            }
            if process.uid == myUID {
                // Outils de compilation livrés dans Xcode : des outils de dev, pas l'app Xcode.
                if path.contains("/Contents/Developer/") { return .dev }
                // Outil de dev empaqueté dans un .app jamais ouvert comme app (les sessions Claude Code
                // de l'app Claude tournent depuis …/claude-code/<version>/claude.app).
                let registered = candidates.contains { !(appsByBundle[$0] ?? []).isEmpty }
                if !registered && Explainer.isKnownDevTool(process.name) { return .dev }
            }
            return .bundle(candidates[0])
        }
        // Exécutable hors de son paquet (copie temporaire pendant une mise à jour, comme Opera) :
        // macOS sait quand même à quelle app il appartient.
        if let app = appByPID[process.pid] {
            return .bundle(PathRules.normalize(app.bundlePath))
        }
        if process.uid != myUID { return .foreign }
        if path.isEmpty { return .orphan }
        if PathRules.isDevLocation(path, home: homeDirectory) || PathRules.isDevTool(name: process.name) {
            return .dev
        }
        if PathRules.isSystem(path) { return .orphan }
        return .thirdParty
    }

    /// Apps du Dock ouvertes à l'intérieur de ce paquet (« Docker Desktop.app » dans Docker.app).
    /// Les processus d'aide (apps de barre des menus, comme les « Helper » de Chromium) n'en font pas partie.
    static func nestedRegularApps(of key: String, appsByBundle: [String: [RunningApp]]) -> [RunningApp] {
        appsByBundle.filter { $0.key.hasPrefix(key + "/") }.flatMap(\.value).filter { $0.policy == .regular }
    }

    private func bundleTitle(_ key: String, appsByBundle: [String: [RunningApp]]) -> String {
        let apps = appsByBundle[key] ?? []
        let nested = Self.nestedRegularApps(of: key, appsByBundle: appsByBundle)
        if let app = apps.first(where: { $0.policy == .regular }) ?? nested.first
            ?? apps.first(where: { $0.policy == .accessory }) ?? apps.first {
            return PathRules.cleanName(app.name)
        }
        if let name = bundleInfo(key)?.name, !PathRules.cleanName(name).isEmpty { return PathRules.cleanName(name) }
        return PathRules.bundleDisplayName(key)
    }

    private func ownPIDs(_ processes: [RawProcess]) -> [Int32] {
        processes.filter { $0.uid == myUID && $0.pid > 1 && $0.pid != myPID }.map(\.pid)
    }

    private func makeBundleGroup(key: String, processes: [RawProcess], category: ProcessCategory, appsByBundle: [String: [RunningApp]]) -> ProcessGroup {
        let apps = appsByBundle[key] ?? []
        // Quitter le groupe quitte l'app et ses apps imbriquées (Docker : le moteur et sa fenêtre).
        let mainApps = (apps.filter { $0.policy != .prohibited } + Self.nestedRegularApps(of: key, appsByBundle: appsByBundle))
            .filter { $0.pid != myPID }
        let info = bundleInfo(key)
        let bundleID = mainApps.first?.bundleID ?? apps.first?.bundleID ?? info?.bundleID
        let title = bundleTitle(key, appsByBundle: appsByBundle)
        let containsSelf = processes.contains { $0.pid == myPID }
        let isProtected = category == .system || containsSelf || bundleID.map(protectedBundleIDs.contains) == true
        let own = ownPIDs(processes)

        let close: CloseMethod
        if containsSelf {
            close = .notAllowed(tr("C'est Vigie.", "This is Vigie."))
        } else if category == .system {
            close = .notAllowed(tr("Fait partie de macOS.", "Part of macOS."))
        } else if isProtected {
            close = .notAllowed(tr("macOS en a besoin : il se relancerait aussitôt.", "macOS needs it: it would restart right away."))
        } else if !mainApps.isEmpty {
            close = .quitApps(mainApps.map(\.pid))
        } else if !own.isEmpty {
            close = .signal(own)
        } else {
            close = .notAllowed(tr("Appartient au système ou à un autre utilisateur.", "Belongs to the system or another user."))
        }

        let explanation: Explanation
        if containsSelf {
            explanation = Explanation(tr("C'est Vigie, l'app que tu utilises en ce moment.", "This is Vigie, the app you are using right now."))
        } else if category == .system {
            explanation = Explainer.forSystem(name: PathRules.bundleDisplayName(key), path: key, isOtherUser: false, title: title)
        } else {
            explanation = Explainer.forApp(bundleID: bundleID, name: title, isBackground: category == .background, info: info)
        }

        return ProcessGroup(
            id: "app:" + key,
            category: category,
            title: title,
            location: PathRules.abbreviate(key, home: homeDirectory),
            explanation: explanation,
            bundlePath: key,
            bundleID: bundleID,
            executablePath: processes.max { ($0.memory ?? 0) < ($1.memory ?? 0) }?.path,
            processes: processes,
            close: close,
            isProtected: isProtected
        )
    }
}
