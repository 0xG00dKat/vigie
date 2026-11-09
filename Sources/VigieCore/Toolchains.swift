import Foundation

/// Versions de Node.js, Python et Ruby installées par les gestionnaires de versions (nvm, fnm, volta, pyenv, uv,
/// rbenv, rvm, asdf, mise) et par Homebrew. On en accumule sans s'en rendre compte : chacune pèse de 50 à 300 Mo,
/// paquets globaux compris.
///
/// Jamais proposées : la version par défaut, une version en cours d'utilisation (un processus tourne dessus) et la
/// dernière version d'un langage. Une version demandée par un projet (`.nvmrc`, `.python-version`…) est signalée.
/// Celles des gestionnaires vont à la corbeille (ils ne gardent qu'un dossier par version) ; celles de Homebrew se
/// retirent avec `brew uninstall`, que Vigie donne à copier.
public struct RuntimeVersion: Sendable, Equatable, Identifiable {
    public enum Runtime: String, CaseIterable, Sendable {
        case node, python, ruby

        public var title: String {
            switch self {
            case .node: return "Node.js"
            case .python: return "Python"
            case .ruby: return "Ruby"
            }
        }

        /// Nom du langage dans asdf et mise.
        var pluginNames: [String] {
            switch self {
            case .node: return ["nodejs", "node"]
            case .python: return ["python"]
            case .ruby: return ["ruby"]
            }
        }

        /// Fichiers de version d'un projet.
        var projectFiles: [String] {
            switch self {
            case .node: return [".nvmrc", ".node-version"]
            case .python: return [".python-version"]
            case .ruby: return [".ruby-version"]
            }
        }
    }

    public var id: String { path }
    public var runtime: Runtime
    /// « 20.11.1 ».
    public var version: String
    public var manager: String
    public var path: String
    public var size: UInt64
    public var isDefault: Bool
    public var inUse: Bool
    /// Projets qui demandent cette version (`.nvmrc`…).
    public var usedBy: [String]
    /// Commande à copier quand Vigie ne retire pas la version elle-même (Homebrew).
    public var command: String?

    public init(runtime: Runtime, version: String, manager: String, path: String, size: UInt64 = 0, isDefault: Bool = false,
                inUse: Bool = false, usedBy: [String] = [], command: String? = nil) {
        self.runtime = runtime
        self.version = version
        self.manager = manager
        self.path = path
        self.size = size
        self.isDefault = isDefault
        self.inUse = inUse
        self.usedBy = usedBy
        self.command = command
    }

    /// Peut partir à la corbeille depuis Vigie.
    public var canTrash: Bool { command == nil && !isDefault && !inUse }

    /// Ancienne version Homebrew : `brew cleanup` la retire sans toucher à la version utilisée.
    public var isOldHomebrewVersion: Bool { command?.hasPrefix("brew cleanup ") == true }

    /// Ligne de stockage : cochable si elle peut aller à la corbeille, nettoyable par `brew cleanup` si c'est une
    /// ancienne version Homebrew, sinon seulement la commande à copier.
    public func entry(trashable: Bool) -> StorageEntry {
        var notes: [String] = []
        var notesEN: [String] = []
        if isDefault { notes.append("version par défaut"); notesEN.append("default version") }
        if inUse { notes.append("en cours d'utilisation"); notesEN.append("in use") }
        if !usedBy.isEmpty {
            notes.append("demandée par " + usedBy.joined(separator: ", "))
            notesEN.append("requested by " + usedBy.joined(separator: ", "))
        }
        if isOldHomebrewVersion { notes.append("ancienne version, remplacée"); notesEN.append("old version, replaced") }
        let fr = "Installée par \(manager)" + (notes.isEmpty ? "." : " · " + notes.joined(separator: " · ") + ".")
        let en = "Installed by \(manager)" + (notesEN.isEmpty ? "." : " · " + notesEN.joined(separator: " · ") + ".")
        let title = "\(runtime.title) \(version)"
        var entry = StorageEntry(id: (trashable ? "runtime-trash:" : "runtime:") + path, title: L(title, title), explanation: L(fr, en),
                                 kind: .appData, path: path, size: size, command: command)
        if isDefault { entry.note = L("par défaut", "default") }
        else if inUse { entry.note = L("en cours", "in use") }
        else if !usedBy.isEmpty {
            entry.note = L("demandée par \(usedBy.joined(separator: ", "))", "requested by \(usedBy.joined(separator: ", "))")
            entry.noteIsWarning = true
        } else if isOldHomebrewVersion { entry.note = L("ancienne version", "old version") }
        else if command != nil { entry.note = L("Homebrew : commande à copier", "Homebrew: command to copy") }
        else if !trashable && command == nil { entry.note = L("gardée", "kept") }
        return entry
    }
}

public enum Toolchains {
    struct Location {
        var runtime: RuntimeVersion.Runtime
        var manager: String
        var folder: String
        /// Le dossier d'une version → le numéro (« v20.11.1 » → « 20.11.1 »).
        var version: (String) -> String?
        var command: ((String, String) -> String)?
    }

    static func plainVersion(_ name: String) -> String? {
        let trimmed = name.hasPrefix("v") ? String(name.dropFirst()) : name
        return trimmed.first?.isNumber == true ? trimmed : nil
    }

    /// « cpython-3.12.1-macos-aarch64-none » → « 3.12.1 ».
    static func uvVersion(_ name: String) -> String? {
        let parts = name.split(separator: "-")
        guard parts.count > 1, parts[0] == "cpython" || parts[0] == "pypy" else { return nil }
        return String(parts[1])
    }

    public static let homebrewCellars = ["/opt/homebrew/Cellar", "/usr/local/Cellar"]

    static func locations(home: String, cellars: [String] = homebrewCellars) -> [Location] {
        var all: [Location] = [
            Location(runtime: .node, manager: "nvm", folder: home + "/.nvm/versions/node", version: plainVersion),
            Location(runtime: .node, manager: "fnm", folder: home + "/.local/share/fnm/node-versions", version: plainVersion),
            Location(runtime: .node, manager: "fnm", folder: home + "/Library/Application Support/fnm/node-versions", version: plainVersion),
            Location(runtime: .node, manager: "volta", folder: home + "/.volta/tools/image/node", version: plainVersion),
            Location(runtime: .python, manager: "pyenv", folder: home + "/.pyenv/versions", version: plainVersion),
            Location(runtime: .python, manager: "uv", folder: home + "/.local/share/uv/python", version: uvVersion),
            Location(runtime: .ruby, manager: "rbenv", folder: home + "/.rbenv/versions", version: plainVersion),
            Location(runtime: .ruby, manager: "rvm", folder: home + "/.rvm/rubies", version: { name in
                name.hasPrefix("ruby-") ? String(name.dropFirst(5)) : nil
            }),
            Location(runtime: .ruby, manager: "chruby", folder: home + "/.rubies", version: { name in
                name.hasPrefix("ruby-") ? String(name.dropFirst(5)) : plainVersion(name)
            }),
        ]
        for runtime in RuntimeVersion.Runtime.allCases {
            for plugin in runtime.pluginNames {
                all.append(Location(runtime: runtime, manager: "asdf", folder: home + "/.asdf/installs/" + plugin, version: plainVersion))
                all.append(Location(runtime: runtime, manager: "mise", folder: home + "/.local/share/mise/installs/" + plugin, version: plainVersion))
            }
        }
        // Homebrew : une formule par version majeure (node@20, python@3.12…), un dossier par version installée.
        for cellar in cellars {
            let formulas = (try? FileManager.default.contentsOfDirectory(atPath: cellar)) ?? []
            for formula in formulas {
                let runtime: RuntimeVersion.Runtime?
                if formula == "node" || formula.hasPrefix("node@") { runtime = .node }
                else if formula.hasPrefix("python@") { runtime = .python }
                else if formula == "ruby" || formula.hasPrefix("ruby@") { runtime = .ruby }
                else { runtime = nil }
                guard let runtime else { continue }
                // Une ancienne version restée à côté de la version liée : `brew cleanup` ne retire que les anciennes.
                let linked = (try? FileManager.default.destinationOfSymbolicLink(atPath: (cellar as NSString).deletingLastPathComponent + "/opt/" + formula))
                    .map { PathRules.lastComponent($0) }
                all.append(Location(runtime: runtime, manager: "Homebrew", folder: cellar + "/" + formula, version: plainVersion,
                                    command: { name, _ in
                                        linked != nil && linked != name ? "brew cleanup \(formula)" : "brew uninstall \(formula)"
                                    }))
            }
        }
        return all
    }

    /// Toutes les versions trouvées, sans leur taille (voir `measure`).
    /// `runningPaths` : exécutables des processus en cours (une version utilisée ne se retire pas).
    /// `projects` : dossiers de projets où chercher `.nvmrc`, `.python-version`…
    public static func find(home: String = NSHomeDirectory(), runningPaths: [String] = [], projects: [String] = [],
                            cellars: [String] = homebrewCellars) -> [RuntimeVersion] {
        let fm = FileManager.default
        let defaults = defaultVersions(home: home)
        let wanted = projectVersions(projects)
        var found: [RuntimeVersion] = []
        for location in locations(home: home, cellars: cellars) {
            for name in ((try? fm.contentsOfDirectory(atPath: location.folder)) ?? []).sorted() {
                let path = location.folder + "/" + name
                // Un lien (« cpython-3.11 » → « cpython-3.11.15 ») n'est pas une version de plus.
                guard let type = try? fm.attributesOfItem(atPath: path)[.type] as? FileAttributeType, type == .typeDirectory,
                      let version = location.version(name) else { continue }
                let isDefault = defaults[location.runtime]?.contains { matches(version, $0) } ?? false
                let inUse = runningPaths.contains { $0.hasPrefix(path + "/") }
                let usedBy = wanted.filter { $0.runtime == location.runtime && matches(version, $0.version) }.map(\.project)
                found.append(RuntimeVersion(runtime: location.runtime, version: version, manager: location.manager, path: path,
                                            isDefault: isDefault, inUse: inUse, usedBy: Array(Set(usedBy)).sorted(),
                                            command: location.command?(name, version)))
            }
        }
        return found
    }

    /// Taille de chaque version (en une passe parallèle).
    public static func measure(_ versions: [RuntimeVersion]) -> [RuntimeVersion] {
        let results = DiskUsage.measure(versions.map { DiskUsage.Request(path: $0.path) })
        return zip(versions, results).map { version, result in
            var version = version
            version.size = result.total
            return version
        }
    }

    /// Langages qui ont plus d'une version installée : ce qu'on peut alléger.
    public static func duplicates(_ versions: [RuntimeVersion]) -> [RuntimeVersion.Runtime: [RuntimeVersion]] {
        Dictionary(grouping: versions, by: \.runtime).filter { $0.value.count > 1 }
    }

    /// Ce qui peut partir à la corbeille : chaque gestionnaire garde au moins une version (celle par défaut ou en
    /// cours d'utilisation, sinon la plus récente), et un langage installé une seule fois n'est jamais proposé.
    public static func trashable(_ versions: [RuntimeVersion]) -> [RuntimeVersion] {
        var result: [RuntimeVersion] = []
        for (_, same) in duplicates(versions) {
            for (_, managed) in Dictionary(grouping: same, by: \.manager) {
                let candidates = managed.filter(\.canTrash)
                guard !candidates.isEmpty else { continue }
                let kept = managed.contains { $0.isDefault || $0.inUse } ? nil : candidates.max { compare($0.version, $1.version) }
                result += candidates.filter { $0.path != kept?.path }
            }
        }
        return result.sorted { $0.size > $1.size }
    }

    /// « 20 » correspond à « 20.11.1 » ; « lts/* » ou « system » ne correspondent à rien.
    static func matches(_ version: String, _ wanted: String) -> Bool {
        let clean = wanted.trimmingCharacters(in: .whitespacesAndNewlines)
        let plain = clean.hasPrefix("v") ? String(clean.dropFirst()) : clean
        guard plain.first?.isNumber == true else { return false }
        return version == plain || version.hasPrefix(plain + ".")
    }

    static func compare(_ a: String, _ b: String) -> Bool {
        a.compare(b, options: .numeric) == .orderedAscending
    }

    /// Versions par défaut de chaque gestionnaire.
    static func defaultVersions(home: String) -> [RuntimeVersion.Runtime: [String]] {
        func read(_ path: String) -> String? { try? String(contentsOfFile: path, encoding: .utf8) }
        var result: [RuntimeVersion.Runtime: [String]] = [:]
        if let nvm = read(home + "/.nvm/alias/default") { result[.node, default: []].append(nvm) }
        if let target = try? FileManager.default.destinationOfSymbolicLink(atPath: home + "/.local/share/fnm/aliases/default") {
            result[.node, default: []].append(PathRules.lastComponent(target))
        }
        if let data = read(home + "/.volta/tools/user/platform.json")?.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let node = (json["node"] as? [String: Any])?["runtime"] as? String {
            result[.node, default: []].append(node)
        }
        for line in (read(home + "/.pyenv/version") ?? "").split(separator: "\n") { result[.python, default: []].append(String(line)) }
        for line in (read(home + "/.rbenv/version") ?? "").split(separator: "\n") { result[.ruby, default: []].append(String(line)) }
        for line in (read(home + "/.tool-versions") ?? "").split(separator: "\n") {
            let parts = line.split(separator: " ")
            guard parts.count >= 2 else { continue }
            for runtime in RuntimeVersion.Runtime.allCases where runtime.pluginNames.contains(String(parts[0])) {
                result[runtime, default: []] += parts.dropFirst().map(String.init)
            }
        }
        // mise : `node = "20"` dans ~/.config/mise/config.toml.
        for line in (read(home + "/.config/mise/config.toml") ?? "").split(separator: "\n") {
            let parts = line.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2 else { continue }
            let value = parts[1].trimmingCharacters(in: CharacterSet(charactersIn: "\"' "))
            for runtime in RuntimeVersion.Runtime.allCases where runtime.pluginNames.contains(parts[0]) {
                result[runtime, default: []].append(value)
            }
        }
        return result
    }

    /// Versions demandées par les projets (`.nvmrc`, `.python-version`, `.ruby-version`, `.tool-versions`).
    static func projectVersions(_ projects: [String]) -> [(project: String, runtime: RuntimeVersion.Runtime, version: String)] {
        var result: [(String, RuntimeVersion.Runtime, String)] = []
        for project in projects {
            let name = PathRules.lastComponent(project)
            for runtime in RuntimeVersion.Runtime.allCases {
                for file in runtime.projectFiles {
                    if let text = try? String(contentsOfFile: project + "/" + file, encoding: .utf8) {
                        result.append((name, runtime, text.trimmingCharacters(in: .whitespacesAndNewlines)))
                    }
                }
            }
            for line in ((try? String(contentsOfFile: project + "/.tool-versions", encoding: .utf8)) ?? "").split(separator: "\n") {
                let parts = line.split(separator: " ")
                guard parts.count >= 2 else { continue }
                for runtime in RuntimeVersion.Runtime.allCases where runtime.pluginNames.contains(String(parts[0])) {
                    result.append((name, runtime, String(parts[1])))
                }
            }
        }
        return result
    }
}

// MARK: - Paquets npm globaux

/// Un paquet installé avec `npm install -g` : des outils en ligne de commande oubliés depuis longtemps.
public struct GlobalPackage: Sendable, Equatable, Identifiable {
    public var id: String { path }
    public var name: String
    public var path: String
    public var size: UInt64
    /// Node qui l'a installé (« Homebrew », « nvm 20.11.1 »).
    public var owner: String

    public init(name: String, path: String, size: UInt64, owner: String) {
        self.name = name
        self.path = path
        self.size = size
        self.owner = owner
    }

    public var removeCommand: String { "npm uninstall -g \(name)" }

    /// Le npm du Node qui l'a installé (pour le retirer du bon endroit).
    public var npmPath: String? {
        guard let range = path.range(of: "/lib/node_modules/") else { return nil }
        let npm = String(path[..<range.lowerBound]) + "/bin/npm"
        return FileManager.default.isExecutableFile(atPath: npm) ? npm : nil
    }

    /// Nom de paquet npm valide (rien d'autre n'est jamais passé à la commande).
    public var hasSafeName: Bool {
        name.range(of: #"^(@[a-z0-9][a-z0-9._~-]*/)?[a-z0-9][a-z0-9._~-]*$"#, options: .regularExpression) != nil
    }

    public var entry: StorageEntry {
        StorageEntry(id: "npm-global:" + path, title: L(name, name),
                     explanation: L("Paquet npm global, installé par \(owner). « \(removeCommand) » le retire.",
                                    "Global npm package, installed by \(owner). “\(removeCommand)” removes it."),
                     kind: .appData, path: path, size: size, command: removeCommand)
    }
}

extension Toolchains {
    /// Paquets fournis avec Node lui-même : jamais listés.
    static let bundledPackages: Set<String> = ["npm", "corepack"]

    /// Paquets globaux de chaque Node installé (Homebrew, et chaque version des gestionnaires).
    public static func globalPackages(home: String = NSHomeDirectory(), versions: [RuntimeVersion]? = nil,
                                      cellars: [String] = homebrewCellars) -> [GlobalPackage] {
        var roots: [(path: String, owner: String)] = [("/opt/homebrew/lib/node_modules", "Homebrew"), ("/usr/local/lib/node_modules", "Homebrew")]
        let nodes = (versions ?? find(home: home, cellars: cellars)).filter { $0.runtime == .node && $0.manager != "Homebrew" }
        for node in nodes {
            let lib = node.manager == "fnm" ? node.path + "/installation/lib/node_modules" : node.path + "/lib/node_modules"
            roots.append((lib, "\(node.manager) \(node.version)"))
        }
        let fm = FileManager.default
        var found: [(name: String, path: String, owner: String)] = []
        for root in roots {
            for name in ((try? fm.contentsOfDirectory(atPath: root.path)) ?? []).sorted() where !name.hasPrefix(".") && !bundledPackages.contains(name) {
                if name.hasPrefix("@") {
                    for scoped in ((try? fm.contentsOfDirectory(atPath: root.path + "/" + name)) ?? []).sorted() where !scoped.hasPrefix(".") {
                        found.append((name + "/" + scoped, root.path + "/" + name + "/" + scoped, root.owner))
                    }
                } else {
                    found.append((name, root.path + "/" + name, root.owner))
                }
            }
        }
        let sizes = DiskUsage.measure(found.map { DiskUsage.Request(path: $0.path) })
        return zip(found, sizes).map { GlobalPackage(name: $0.name, path: $0.path, size: $1.total, owner: $0.owner) }
            .sorted { $0.size > $1.size }
    }
}
