import Foundation

/// Les quatre rubriques affichées dans Vigie.
public enum ProcessCategory: String, CaseIterable, Identifiable, Sendable {
    case apps, dev, background, system

    public var id: String { rawValue }

    public var title: String {
        if Wording.simple {
            switch self {
            case .apps: return tr("Apps ouvertes", "Open apps")
            case .dev: return tr("Outils de développement", "Developer tools")
            case .background: return tr("Programmes discrets", "Quiet helpers")
            case .system: return tr("macOS", "macOS")
            }
        }
        switch self {
        case .apps: return tr("Apps", "Apps")
        case .dev: return tr("Dev & terminal", "Dev & terminal")
        case .background: return tr("Arrière-plan", "Background")
        case .system: return tr("Système", "System")
        }
    }

    public var help: String {
        if Wording.simple {
            switch self {
            case .apps:
                return tr("Les apps que tu as ouvertes. Les quitter libère de la mémoire ; tu les rouvres quand tu veux.",
                          "The apps you opened. Quitting them frees memory; reopen them whenever you like.")
            case .dev:
                return tr("Outils pour programmer.", "Programming tools.")
            case .background:
                return tr("Petits programmes sans fenêtre : icônes de la barre des menus, synchronisation, mises à jour.",
                          "Small programs without a window: menu bar icons, sync, updates.")
            case .system:
                return tr("Le fonctionnement de macOS lui-même. Rien à faire ici : Vigie n'y touche pas.",
                          "macOS itself at work. Nothing to do here: Vigie never touches it.")
            }
        }
        switch self {
        case .apps:
            return tr("Les apps ouvertes, chacune avec tous ses processus d'aide.",
                      "Open apps, each with all of its helper processes.")
        case .dev:
            return tr("Serveurs, agents et outils lancés depuis un terminal, un éditeur ou Claude, rangés par projet.",
                      "Servers, agents and tools started from a terminal, an editor or Claude, grouped by project.")
        case .background:
            return tr("Utilitaires sans fenêtre : barre des menus, synchronisation, agents.",
                      "Windowless utilities: menu bar apps, sync, agents.")
        case .system:
            return tr("macOS et les services lancés par l'administrateur. Vigie ne les ferme pas : ils redémarrent tout seuls.",
                      "macOS and services started by the administrator. Vigie never closes them: they restart on their own.")
        }
    }
}

public enum ActivationPolicy: Sendable, Equatable {
    /// App avec icône dans le Dock.
    case regular
    /// App de barre des menus, sans Dock.
    case accessory
    /// Processus d'aide enregistré, sans interface.
    case prohibited
}

/// Une app connue de macOS (NSWorkspace), transmise au cœur sans dépendre d'AppKit.
public struct RunningApp: Sendable, Equatable {
    public var pid: Int32
    public var bundlePath: String
    public var bundleID: String?
    public var name: String
    public var policy: ActivationPolicy

    public init(pid: Int32, bundlePath: String, bundleID: String?, name: String, policy: ActivationPolicy) {
        self.pid = pid
        self.bundlePath = bundlePath
        self.bundleID = bundleID
        self.name = name
        self.policy = policy
    }
}

public struct RawProcess: Sendable, Hashable, Identifiable {
    public var id: Int32 { pid }
    public var pid: Int32
    public var ppid: Int32
    public var uid: UInt32
    public var name: String
    public var path: String
    public var startTime: Date?
    /// Empreinte mémoire (la colonne « Mémoire » du Moniteur d'activité), en octets.
    public var memory: UInt64?
    public var cpuPercent: Double?
    /// Processus que macOS tient pour « responsable » (l'app qui a demandé ce service).
    public var responsiblePID: Int32?
    public var cwd: String?
    public var arguments: [String]
    public var listeningPorts: [Int]
    /// Ports qui écoutent sur tout le réseau (visibles des autres appareils du Wi-Fi), pas seulement sur ce Mac.
    public var exposedPorts: [Int] = []

    public init(
        pid: Int32, ppid: Int32, uid: UInt32, name: String, path: String,
        startTime: Date? = nil, memory: UInt64? = nil, cpuPercent: Double? = nil,
        responsiblePID: Int32? = nil, cwd: String? = nil, arguments: [String] = [], listeningPorts: [Int] = []
    ) {
        self.pid = pid
        self.ppid = ppid
        self.uid = uid
        self.name = name
        self.path = path
        self.startTime = startTime
        self.memory = memory
        self.cpuPercent = cpuPercent
        self.responsiblePID = responsiblePID
        self.cwd = cwd
        self.arguments = arguments
        self.listeningPorts = listeningPorts
    }
}

/// Un port TCP en écoute, et l'adresse sur laquelle il écoute.
public struct ListeningSocket: Sendable, Equatable, Hashable {
    public var port: Int
    public var address: String

    public init(port: Int, address: String) {
        self.port = port
        self.address = address
    }

    /// 127.0.0.1 ou ::1 : seul ce Mac peut s'y connecter. Toute autre adresse (0.0.0.0, ::, l'adresse du Mac sur le Wi-Fi)
    /// le rend joignable par les autres appareils du même réseau.
    public var isLoopback: Bool {
        address.hasPrefix("127.") || address == "::1" || address.hasPrefix("::ffff:127.")
    }

    public var isExposed: Bool { !isLoopback }
}

/// Détails coûteux, lus seulement pour les processus de dev.
public struct ProcessDetails: Sendable, Equatable {
    public var cwd: String?
    public var arguments: [String]
    public var listeningPorts: [Int]
    public var exposedPorts: [Int]

    public init(cwd: String? = nil, arguments: [String] = [], listeningPorts: [Int] = [], exposedPorts: [Int] = []) {
        self.cwd = cwd
        self.arguments = arguments
        self.listeningPorts = listeningPorts
        self.exposedPorts = exposedPorts
    }

    public init(cwd: String?, arguments: [String], sockets: [ListeningSocket]) {
        self.init(cwd: cwd, arguments: arguments, listeningPorts: Array(Set(sockets.map(\.port))).sorted(),
                  exposedPorts: Array(Set(sockets.filter(\.isExposed).map(\.port))).sorted())
    }

    public static let empty = ProcessDetails()
}

public struct BundleInfo: Sendable, Equatable {
    public var name: String?
    public var bundleID: String?
    public var category: String?
    public var version: String?

    public init(name: String? = nil, bundleID: String? = nil, category: String? = nil, version: String? = nil) {
        self.name = name
        self.bundleID = bundleID
        self.category = category
        self.version = version
    }
}

public struct Explanation: Sendable, Equatable {
    public var text: String
    /// Vrai quand Vigie n'a qu'une description générique : le bouton « Demander à Claude » est alors mis en avant.
    public var isGeneric: Bool

    public init(_ text: String, isGeneric: Bool = false) {
        self.text = text
        self.isGeneric = isGeneric
    }
}

public enum CloseMethod: Sendable, Equatable {
    /// Fermeture normale d'app, comme ⌘Q (l'app peut demander d'enregistrer).
    case quitApps([Int32])
    /// SIGTERM : demande d'arrêt propre à un processus sans interface.
    case signal([Int32])
    case notAllowed(String)

    public var isAllowed: Bool {
        if case .notAllowed = self { return false }
        return true
    }

    public var pids: [Int32] {
        switch self {
        case .quitApps(let pids), .signal(let pids): return pids
        case .notAllowed: return []
        }
    }
}

public struct ProcessGroup: Identifiable, Sendable {
    public var id: String
    public var category: ProcessCategory
    public var title: String
    /// Dossier du projet (dev) ou emplacement de l'app, abrégé avec ~.
    public var location: String?
    public var explanation: Explanation
    public var bundlePath: String?
    public var bundleID: String?
    /// Exécutable représentatif (le plus gros processus du groupe).
    public var executablePath: String?
    /// Dossier de travail complet pour les groupes de dev rangés par projet.
    public var directory: String?
    public var processes: [RawProcess]
    public var memory: UInt64
    public var cpuPercent: Double
    public var ports: [Int]
    /// Ports visibles sur le réseau (pas seulement sur ce Mac).
    public var exposedPorts: [Int]
    public var startTime: Date?
    /// App depuis laquelle les processus ont été lancés (Terminal, Cursor, Claude…).
    public var launchedBy: String?
    /// Processus de dev dont le parent a disparu (souvent le reste d'une session terminée).
    public var isOrphan: Bool
    public var close: CloseMethod
    public var isProtected: Bool

    public init(
        id: String, category: ProcessCategory, title: String, location: String? = nil, explanation: Explanation,
        bundlePath: String? = nil, bundleID: String? = nil, executablePath: String? = nil, directory: String? = nil,
        processes: [RawProcess], launchedBy: String? = nil, isOrphan: Bool = false,
        close: CloseMethod, isProtected: Bool
    ) {
        self.id = id
        self.category = category
        self.title = title
        self.location = location
        self.explanation = explanation
        self.bundlePath = bundlePath
        self.bundleID = bundleID
        self.executablePath = executablePath
        self.directory = directory
        let sorted = processes.sorted { ($0.memory ?? 0) > ($1.memory ?? 0) }
        self.processes = sorted
        self.memory = sorted.reduce(0) { $0 + ($1.memory ?? 0) }
        self.cpuPercent = sorted.reduce(0) { $0 + ($1.cpuPercent ?? 0) }
        self.ports = Array(Set(sorted.flatMap(\.listeningPorts))).sorted()
        self.exposedPorts = Array(Set(sorted.flatMap(\.exposedPorts))).sorted()
        self.startTime = sorted.compactMap(\.startTime).min()
        self.launchedBy = launchedBy
        self.isOrphan = isOrphan
        self.close = close
        self.isProtected = isProtected
    }
}

public struct Snapshot: Sendable {
    public var groups: [ProcessGroup]
    public var processCount: Int
    public var memoryUsed: UInt64
    public var memoryTotal: UInt64
    public var date: Date
    /// pid parent → pids enfants, pour arrêter un processus avec ses enfants.
    public var children: [Int32: [Int32]]

    public init(groups: [ProcessGroup], processCount: Int, memoryUsed: UInt64, memoryTotal: UInt64, date: Date, children: [Int32: [Int32]]) {
        self.groups = groups
        self.processCount = processCount
        self.memoryUsed = memoryUsed
        self.memoryTotal = memoryTotal
        self.date = date
        self.children = children
    }

    public func groups(in category: ProcessCategory) -> [ProcessGroup] {
        groups.filter { $0.category == category }
    }

    /// Descendants d'un processus (sans lui-même).
    public func descendants(of pid: Int32) -> [Int32] {
        var result: [Int32] = []
        var queue = children[pid] ?? []
        var seen = Set<Int32>()
        while let next = queue.popLast() {
            guard seen.insert(next).inserted else { continue }
            result.append(next)
            queue.append(contentsOf: children[next] ?? [])
        }
        return result
    }
}
