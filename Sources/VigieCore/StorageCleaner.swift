import Foundation

/// Ce que Vigie peut nettoyer elle-même dans la vue Stockage, et comment.
///
/// - Un cache qui a une commande officielle (npm, pnpm, uv, Homebrew, Docker…) : Vigie lance cette commande,
///   qui sait ce qui peut partir (pnpm ne retire que les paquets qu'aucun projet n'utilise).
/// - Un autre cache (un dossier de ~/Library/Caches, les compilations de Xcode…) : supprimé pour de bon,
///   il se recrée tout seul. La corbeille ne libérerait rien tant qu'on ne la vide pas.
/// - Les `node_modules` d'un projet : à la corbeille, pour pouvoir revenir en arrière (`npm install` les recrée).
/// - Un gros fichier ou un doublon que tu choisis : à la corbeille, jamais supprimé pour de bon.
/// - Tout le reste (tes dossiers, données d'apps, apps, dossiers protégés) : jamais.
public enum StorageCleanup: Sendable, Equatable {
    case command(String)
    case delete
    case trash
    /// Plusieurs dossiers à la corbeille d'un coup (les restes d'une app supprimée).
    case trashAll([String])
    /// Vider la corbeille, en le demandant au Finder (définitif).
    case emptyTrash

    public var isCommand: Bool {
        if case .command = self { return true }
        return false
    }

    /// À la corbeille : la place ne revient qu'une fois la corbeille vidée.
    public var goesToTrash: Bool {
        switch self {
        case .trash, .trashAll: return true
        case .command, .delete, .emptyTrash: return false
        }
    }
}

public enum StorageCleaner {
    /// Commandes officielles lancées telles quelles, sans question (sinon la commande attendrait une réponse).
    /// Les commandes qui ne font que lister (`rustup toolchain list`, `ollama list`) n'y sont pas.
    static let runnable: [String: String] = [
        "npm cache clean --force": "npm cache clean --force",
        "pnpm store prune": "pnpm store prune",
        "bun pm cache rm": "bun pm cache rm",
        "yarn cache clean": "yarn cache clean",
        "go clean -modcache": "go clean -modcache",
        "xcrun simctl delete unavailable": "xcrun simctl delete unavailable",
        "uv cache clean": "uv cache clean",
        "pip cache purge": "pip3 cache purge",
        "brew cleanup --prune=all": "brew cleanup --prune=all",
        "docker system prune": "docker system prune -f",
    ]

    /// Dossiers entiers jamais supprimés d'un bloc : on nettoie leurs sous-dossiers un par un.
    static let wholeFolders: Set<String> = ["caches", "dotcache", "logs", "dev-caches"]

    public static func cleanup(for entry: StorageEntry, home: String = NSHomeDirectory()) -> StorageCleanup? {
        // La corbeille : macOS en protège le contenu, mais le Finder sait la vider.
        if entry.id == "trash" { return .emptyTrash }
        guard !entry.isProtected, isInsideHome(entry.path, home: home) else { return nil }
        // Vieux installeurs de Téléchargements : à la corbeille, tous ou un par un.
        if entry.id == "installers" {
            let paths = entry.children.map(\.path).filter { isInsideHome($0, home: home) }
            return paths.isEmpty ? nil : .trashAll(paths)
        }
        if entry.id.hasPrefix("installer:") { return .trash }
        // Versions de langages : une version proposée (ni par défaut, ni utilisée, ni la dernière) va à la corbeille ;
        // une ancienne version Homebrew part avec `brew cleanup <formule>`.
        if entry.id.hasPrefix("runtime-trash:") { return isInsideHome(entry.path, home: home) ? .trash : nil }
        if entry.id.hasPrefix("runtime:") {
            guard let command = entry.command, command.range(of: #"^brew cleanup [a-z0-9@._+-]+$"#, options: .regularExpression) != nil else { return nil }
            return .command(command)
        }
        // Paquet npm global : le npm du Node qui l'a installé le retire (nom vérifié).
        if entry.id.hasPrefix("npm-global:") {
            let package = GlobalPackage(name: entry.title.fr, path: entry.path, size: entry.size, owner: "")
            guard package.hasSafeName, let npm = package.npmPath, !npm.contains(where: { "\"$`\\".contains($0) }) else { return nil }
            // Le bon Node en tête du PATH : npm calcule le dossier global à partir du Node qui l'exécute.
            let bin = (npm as NSString).deletingLastPathComponent
            return .command("PATH=\"\(bin):$PATH\" \"\(npm)\" uninstall -g \(package.name)")
        }
        // Projet endormi : ses dépendances et compilations à la corbeille, jamais le projet lui-même.
        if entry.id.hasPrefix("dormant:") {
            let paths = entry.children.map(\.path).filter { isInsideHome($0, home: home) && $0.hasPrefix(entry.path + "/") }
            return paths.isEmpty ? nil : .trashAll(paths)
        }
        if entry.id.hasPrefix("dormant-part:") { return entry.path.hasPrefix(home + "/") && isInsideHome(entry.path, home: home) ? .trash : nil }
        if let command = entry.command, let run = runnable[command] { return .command(run) }
        switch entry.kind {
        case .project:
            return entry.path.hasSuffix("/node_modules") ? .trash : nil
        case .cache:
            return wholeFolders.contains(entry.id) ? nil : .delete
        case .appData:
            // Le cache d'une app, rangé sous elle dans « Applications ».
            return entry.id.hasPrefix("footprint:") && entry.path.hasPrefix(home + "/Library/Caches/") ? .delete : nil
        case .leftover:
            // Restes d'une app supprimée : tous ses dossiers, ou un seul.
            if entry.id.hasPrefix("leftover:") {
                let paths = entry.children.map(\.path).filter { isInsideHome($0, home: home) }
                return paths.isEmpty ? nil : .trashAll(paths)
            }
            return .trash
        case .largeFile:
            // Un de tes gros fichiers : à la corbeille seulement (réversible), après confirmation.
            return .trash
        case .application, .personal, .systemData:
            return nil
        }
    }

    /// Dans le dossier personnel, au moins un niveau en dessous, sans « .. » : jamais le dossier personnel lui-même.
    public static func isInsideHome(_ path: String, home: String) -> Bool {
        guard path.hasPrefix(home + "/"), !path.contains("/../"), !path.hasSuffix("/..") else { return false }
        let relative = path.dropFirst(home.count + 1)
        return !relative.isEmpty && relative != "Library" && relative != "Library/Caches" && relative != ".cache"
    }

    public enum Failure: Error, Equatable {
        case command(String)
        case file(String)
    }

    /// Nettoie et renvoie la place libérée (mesurée avant et après). À lancer hors du fil principal.
    public static func run(_ cleanup: StorageCleanup, path: String) -> Result<UInt64, Failure> {
        if cleanup == .emptyTrash {
            // L'espace libre avant et après : macOS ne laisse pas lire la corbeille elle-même.
            let before = DiskReader.read()?.available ?? 0
            if let error = emptyTrashWithFinder() { return .failure(.command(error)) }
            let after = DiskReader.read()?.available ?? 0
            return .success(after > before ? after - before : 0)
        }
        if case .trashAll(let paths) = cleanup {
            var freed: UInt64 = 0
            for item in paths {
                let size = DiskUsage.measure(item).total
                do { try FileManager.default.trashItem(at: URL(fileURLWithPath: item), resultingItemURL: nil) } catch {
                    return .failure(.file(error.localizedDescription))
                }
                freed += size
            }
            return .success(freed)
        }
        let before = DiskUsage.measure(path).total
        switch cleanup {
        case .command(let command):
            if let error = runCommand(command) { return .failure(.command(error)) }
        case .delete:
            do { try FileManager.default.removeItem(atPath: path) } catch { return .failure(.file(error.localizedDescription)) }
        case .trash:
            do { try FileManager.default.trashItem(at: URL(fileURLWithPath: path), resultingItemURL: nil) } catch {
                return .failure(.file(error.localizedDescription))
            }
        case .trashAll, .emptyTrash:
            break
        }
        let after = FileManager.default.fileExists(atPath: path) && cleanup != .trash ? DiskUsage.measure(path).total : 0
        return .success(before > after ? before - after : 0)
    }

    /// Le Finder vide la corbeille (comme son menu). La première fois, macOS demande si Vigie peut piloter le Finder.
    static func emptyTrashWithFinder() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", "tell application \"Finder\" to empty trash"]
        let errors = Pipe()
        process.standardError = errors
        process.standardOutput = FileHandle.nullDevice
        do { try process.run() } catch { return error.localizedDescription }
        let data = errors.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus != 0 else { return nil }
        let text = String(decoding: data, as: UTF8.self)
        if text.contains("-1743") || text.contains("Not authorized") {
            return L("autorise Vigie à piloter le Finder dans Réglages Système › Confidentialité et sécurité › Automatisation.",
                     "allow Vigie to control the Finder in System Settings › Privacy & Security › Automation.").text
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "\n").last.map(String.init) ?? "Finder"
    }

    /// Lance la commande dans un shell de connexion, avec les dossiers où ces outils s'installent d'habitude
    /// (une app lancée par le Finder n'a pas le PATH du Terminal). Renvoie l'erreur, ou nil si tout va bien.
    static func runCommand(_ command: String, timeout: TimeInterval = 600) -> String? {
        let home = NSHomeDirectory()
        let extra = ["/opt/homebrew/bin", "/usr/local/bin", home + "/.local/bin", home + "/Library/pnpm", home + "/.bun/bin",
                     home + "/go/bin", home + "/.cargo/bin", "/Applications/Docker.app/Contents/Resources/bin"]
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", command]
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = (extra + [environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"]).joined(separator: ":")
        environment["CI"] = "1"
        process.environment = environment
        process.standardInput = FileHandle.nullDevice
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        do { try process.run() } catch { return error.localizedDescription }
        let watchdog = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: watchdog)
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        watchdog.cancel()
        guard process.terminationStatus != 0 else { return nil }
        let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        let last = text.split(separator: "\n").suffix(2).joined(separator: " ")
        return last.isEmpty ? "code \(process.terminationStatus)" : String(last.prefix(200))
    }
}

extension StorageReport {
    /// Rapport après un nettoyage : toutes les lignes de ce dossier (il peut apparaître à deux endroits, comme
    /// le cache d'Opera, dans « Caches des apps » et sous l'app Opera) maigrissent de `freed`, ou disparaissent
    /// si le dossier n'existe plus ; les lignes qui les contiennent maigrissent aussi.
    public func afterCleaning(path: String, freed: UInt64, removed: Bool) -> StorageReport {
        func update(_ entries: [StorageEntry]) -> (entries: [StorageEntry], touched: Bool) {
            var touched = false
            var result: [StorageEntry] = []
            for var entry in entries {
                if entry.path == path {
                    touched = true
                    if removed { continue }
                    entry.size -= min(entry.size, freed)
                    entry.children = []
                } else {
                    let children = update(entry.children)
                    // Une ligne qui contient le dossier (le Bureau pour un node_modules qui s'y trouve) maigrit aussi.
                    if children.touched || path.hasPrefix(entry.path + "/") {
                        touched = true
                        entry.children = children.entries
                        entry.size -= min(entry.size, freed)
                    }
                }
                result.append(entry)
            }
            return (result, touched)
        }
        var report = self
        report.entries = update(entries).entries
        return report
    }
}

/// Vieux installeurs (.dmg, .pkg…) restés dans Téléchargements depuis plus d'un mois : l'app est installée,
/// on n'en a plus besoin. À la corbeille, pour pouvoir revenir en arrière.
public enum OldInstallers {
    public struct File: Sendable, Equatable {
        public var path: String
        public var size: UInt64
        public var modified: Date
    }

    static let extensions: Set<String> = ["dmg", "pkg", "mpkg", "iso", "xip", "ipsw"]
    public static let minimumAge: TimeInterval = 30 * 86_400

    /// Téléchargements et ses sous-dossiers directs.
    public static func find(home: String, now: Date = Date()) -> [File] {
        let downloads = home + "/Downloads"
        var folders = [downloads]
        for name in (try? FileManager.default.contentsOfDirectory(atPath: downloads)) ?? [] where !name.hasPrefix(".") {
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: downloads + "/" + name, isDirectory: &isDirectory), isDirectory.boolValue,
               !name.hasSuffix(".app") {
                folders.append(downloads + "/" + name)
            }
        }
        var files: [File] = []
        for folder in folders {
            for name in (try? FileManager.default.contentsOfDirectory(atPath: folder)) ?? []
            where extensions.contains((name as NSString).pathExtension.lowercased()) {
                let path = folder + "/" + name
                var info = stat()
                guard lstat(path, &info) == 0 else { continue }
                let modified = Date(timeIntervalSince1970: TimeInterval(info.st_mtimespec.tv_sec))
                guard now.timeIntervalSince(modified) >= minimumAge else { continue }
                // Un .pkg peut être un dossier (paquet) : on le mesure en entier.
                let size = (info.st_mode & S_IFMT) == S_IFDIR ? DiskUsage.measure(path).total : UInt64(info.st_blocks) * 512
                files.append(File(path: path, size: size, modified: modified))
            }
        }
        return files.sorted { $0.size > $1.size }
    }

    /// Une ligne « Vieux installeurs » dans « Tes fichiers », chaque fichier en dessous.
    public static func entry(_ files: [File], home: String, minimumSize: UInt64) -> StorageEntry? {
        let total = files.reduce(UInt64(0)) { $0 + $1.size }
        guard !files.isEmpty, total >= minimumSize else { return nil }
        let children = files.map { file in
            StorageEntry(id: "installer:" + file.path, title: L((file.path as NSString).lastPathComponent, (file.path as NSString).lastPathComponent),
                         explanation: L("Téléchargé \(Format.ago(file.modified, in: .fr)).", "Downloaded \(Format.ago(file.modified, in: .en))."),
                         kind: .personal, path: file.path, size: file.size, modified: file.modified)
        }
        return StorageEntry(id: "installers", title: L("Vieux installeurs", "Old installers"),
                            explanation: L("\(files.count) fichier\(files.count > 1 ? "s" : "") .dmg ou .pkg dans Téléchargements depuis plus d'un mois : l'app est installée, on n'en a plus besoin.",
                                           "\(files.count) .dmg or .pkg file\(files.count > 1 ? "s" : "") in Downloads for over a month: the app is installed, you no longer need them."),
                            kind: .personal, path: home + "/Downloads", size: total, children: children)
    }
}
