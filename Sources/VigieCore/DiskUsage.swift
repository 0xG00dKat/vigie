import Darwin
import Foundation

/// Place occupée sur le disque, comme `du`, mais en parallèle et en une seule passe.
///
/// `du` lit un dossier à la fois, sur un seul cœur : le Bureau d'un développeur (des millions de petits
/// fichiers dans les `node_modules`) prenait 40 s. Ici, plusieurs fils se partagent les dossiers à lire,
/// chaque dossier est lu d'un coup avec `getattrlistbulk` (nom, type, date, taille allouée, liens),
/// et la même passe trouve les `node_modules` et les gros fichiers.
public enum DiskUsage {
    public struct Request: Sendable {
        public var path: String
        /// Taille de chaque sous-dossier direct (comme `du -d 1`).
        public var breakdown: Bool
        /// Repère les dossiers `node_modules` (les plus hauts) et mesure chacun.
        public var findNodeModules: Bool
        /// Repère les fichiers d'au moins cette taille (hors dossiers cachés, `Library`, paquets et `node_modules`).
        public var largeFileMinimum: UInt64?
        /// Recherche de projets seulement : ne descend pas dans les dossiers cachés ni `Library` (hors `node_modules`).
        public var skipHidden: Bool
        /// Explorateur : taille de chaque dossier jusqu'à cette profondeur (0 : rien), et ses fichiers d'au moins
        /// `explorerFileMinimum`. Une seule lecture suffit alors pour descendre de plusieurs niveaux.
        public var recordDepth = 0
        public var explorerFileMinimum: UInt64 = 20_000_000

        public init(path: String, breakdown: Bool = false, findNodeModules: Bool = false,
                    largeFileMinimum: UInt64? = nil, skipHidden: Bool = false) {
            self.path = path
            self.breakdown = breakdown
            self.findNodeModules = findNodeModules
            self.largeFileMinimum = largeFileMinimum
            self.skipHidden = skipHidden
        }
    }

    public struct LargeFile: Sendable, Equatable {
        public var path: String
        public var size: UInt64
        public var modified: Date
    }

    public struct Result: Sendable {
        public var exists = true
        public var total: UInt64 = 0
        /// Sous-dossiers directs, du plus gros au plus petit (si `breakdown`).
        public var children: [(name: String, size: UInt64)] = []
        public var nodeModules: [(path: String, size: UInt64)] = []
        public var largeFiles: [LargeFile] = []
        /// macOS a refusé la lecture d'au moins un dossier.
        public var denied = false
        /// Explorateur (`recordDepth`) : taille de chaque dossier mémorisé, par chemin.
        public var directorySizes: [String: UInt64] = [:]
        /// Explorateur : fichiers d'au moins `explorerFileMinimum` dans les dossiers mémorisés.
        public var explorerFiles: [(path: String, size: UInt64)] = []
    }

    /// Bibliothèques gérées par une app (Photos, Musique, iMovie, Final Cut…) : leurs fichiers ne se trient pas
    /// dans le Finder, ils ne sont donc jamais listés comme gros fichiers ni comme doublons.
    static let libraryPackages: Set<String> = ["photoslibrary", "photolibrary", "musiclibrary", "imovielibrary", "tvlibrary",
                                                "fcpbundle", "logicx", "band", "aplibrary", "migratedphotolibrary", "theater"]

    static func isLibraryPackage(_ name: String) -> Bool {
        guard let dot = name.lastIndex(of: ".") else { return false }
        return libraryPackages.contains(name[name.index(after: dot)...].lowercased())
    }

    /// Au-delà d'un fil par cœur, le noyau de macOS ne lit pas plus vite (mesuré : plateau dès 8 fils).
    public static var defaultThreads: Int { min(16, max(4, ProcessInfo.processInfo.activeProcessorCount)) }

    /// Mesure toutes les demandes ensemble. Les demandes avancent à tour de rôle : les petites se terminent
    /// vite, sans attendre un gros dossier. `completed` reçoit chaque résultat dès qu'il est prêt.
    public static func measure(_ requests: [Request], threads: Int = defaultThreads,
                               completed: (@Sendable (Int, Result) -> Void)? = nil) -> [Result] {
        guard !requests.isEmpty else { return [] }
        let walk = Walk(requests: requests, completed: completed)
        walk.run(threads: threads)
        return walk.finals.map { $0 ?? Result() }
    }

    public static func measure(_ path: String, breakdown: Bool = false) -> Result {
        measure([Request(path: path, breakdown: breakdown)], threads: 4)[0]
    }
}

// MARK: - Parcours parallèle

private final class Walk: @unchecked Sendable {
    struct Task {
        var path: String
        var depth: Int
        /// Sous-dossier direct auquel la place est comptée (`breakdown`), -1 sinon.
        var child: Int
        /// `node_modules` auquel la place est comptée, -1 sinon.
        var module: Int
        /// Dans un dossier caché, `Library` ou un paquet : pas de recherche de projets ni de gros fichiers.
        var hidden: Bool
        /// Explorateur : dossiers mémorisés qui contiennent celui-ci (lui compris), pour leur ajouter sa place.
        var recorded: [Int] = []
    }

    struct State {
        var result = DiskUsage.Result()
        var childSizes: [UInt64] = []
        var childNames: [String] = []
        var modulePaths: [String] = []
        var moduleSizes: [UInt64] = []
        /// Fichiers à plusieurs liens déjà comptés (pnpm en met partout) : comptés une fois, comme `du`.
        var linked = Set<UInt64>()
        var recordedPaths: [String] = []
        var recordedSizes: [UInt64] = []
        var explorerFiles: [(path: String, size: UInt64)] = []
        /// Dossiers en file ou en cours de lecture.
        var pending = 0
        /// Dossiers à lire (le dernier ajouté d'abord, pour rester près de ce qui vient d'être lu).
        var stack: [Task] = []
    }

    let requests: [DiskUsage.Request]
    let completed: (@Sendable (Int, DiskUsage.Result) -> Void)?
    var states: [State]
    var finals: [DiskUsage.Result?]
    /// Demandes qui ont des dossiers à lire, servies à tour de rôle.
    var ready: [Int] = []
    var readyHead = 0
    var isReady: [Bool]
    var queued = 0
    var active = 0
    var threadCount = 1
    let condition = NSCondition()

    init(requests: [DiskUsage.Request], completed: (@Sendable (Int, DiskUsage.Result) -> Void)?) {
        self.requests = requests
        self.completed = completed
        states = Array(repeating: State(), count: requests.count)
        finals = Array(repeating: nil, count: requests.count)
        isReady = Array(repeating: false, count: requests.count)
        for (index, request) in requests.enumerated() {
            var info = stat()
            var result = DiskUsage.Result()
            if lstat(request.path, &info) != 0 {
                result.exists = errno == EPERM || errno == EACCES
                result.denied = result.exists
            } else if (info.st_mode & S_IFMT) == S_IFDIR {
                states[index].pending = 1
                states[index].stack = [Task(path: request.path, depth: 0, child: -1, module: -1, hidden: false)]
                ready.append(index)
                isReady[index] = true
                queued += 1
                continue
            } else {
                // Un fichier seul (réglages, disque virtuel…) : sa taille allouée.
                result.total = UInt64(info.st_blocks) * 512
            }
            finals[index] = result
            completed?(index, result)
        }
    }

    func run(threads: Int) {
        threadCount = max(1, threads)
        let group = DispatchGroup()
        for _ in 0..<threadCount {
            group.enter()
            let thread = Thread { [self] in
                worker()
                group.leave()
            }
            thread.stackSize = 1 << 20
            thread.start()
        }
        group.wait()
    }

    /// Prochain dossier à lire, en passant d'une demande à l'autre. Appelé sous le verrou.
    private func next() -> (Int, Task)? {
        while readyHead < ready.count {
            let request = ready[readyHead]
            readyHead += 1
            guard let task = states[request].stack.popLast() else {
                isReady[request] = false
                continue
            }
            if states[request].stack.isEmpty {
                isReady[request] = false
            } else {
                ready.append(request)
            }
            if readyHead > 4096 && readyHead * 2 > ready.count {
                ready.removeFirst(readyHead)
                readyHead = 0
            }
            queued -= 1
            return (request, task)
        }
        return nil
    }

    private func worker() {
        let bufferSize = 256 * 1024
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: bufferSize, alignment: 16)
        defer { buffer.deallocate() }
        condition.lock()
        while true {
            while queued == 0 && active > 0 { condition.wait() }
            guard let (index, task) = next() else {
                condition.broadcast()
                condition.unlock()
                return
            }
            active += 1
            condition.unlock()

            let request = requests[index]
            let listing = Listing.read(task.path, buffer: buffer, size: bufferSize,
                                       largeFileMinimum: task.hidden || task.module >= 0 ? nil : request.largeFileMinimum,
                                       fileMinimum: task.depth < request.recordDepth ? request.explorerFileMinimum : nil)

            condition.lock()
            let before = queued
            let done = update(&states[index], index: index, task: task, request: request, listing: listing)
            var final: DiskUsage.Result?
            if done {
                final = finish(index)
                finals[index] = final
            }
            active -= 1
            // Un fil réveillé par dossier ajouté ; tous à la fin, pour qu'ils s'arrêtent.
            if queued == 0 && active == 0 {
                condition.broadcast()
            } else {
                for _ in 0..<min(queued - before, threadCount) { condition.signal() }
            }
            if let final, let completed {
                condition.unlock()
                completed(index, final)
                condition.lock()
            }
        }
    }

    /// Résultat d'une demande terminée ; sa mémoire (liens, piles) est libérée. Appelé sous le verrou.
    private func finish(_ index: Int) -> DiskUsage.Result {
        let state = states[index]
        states[index] = State()
        var result = state.result
        result.children = zip(state.childNames, state.childSizes).map { ($0, $1) }.sorted { $0.1 > $1.1 }
        result.nodeModules = zip(state.modulePaths, state.moduleSizes).map { ($0, $1) }
        result.largeFiles.sort { $0.size > $1.size }
        result.directorySizes = Dictionary(zip(state.recordedPaths, state.recordedSizes), uniquingKeysWith: { first, _ in first })
        result.explorerFiles = state.explorerFiles
        return result
    }

    /// Ajoute un dossier lu à sa demande et met ses sous-dossiers en file. Appelé sous le verrou ;
    /// l'état est modifié sur place (une copie dupliquerait l'ensemble des liens à chaque dossier).
    private func update(_ state: inout State, index: Int, task: Task, request: DiskUsage.Request, listing: Listing) -> Bool {
        var added = listing.size
        for (id, size) in listing.linked where state.linked.insert(id).inserted {
            added += size
        }
        state.result.total += added
        for index in task.recorded { state.recordedSizes[index] += added }
        for file in listing.files { state.explorerFiles.append((task.path + "/" + file.name, file.size)) }
        if task.child >= 0 { state.childSizes[task.child] += added }
        if task.module >= 0 { state.moduleSizes[task.module] += added }
        if listing.denied { state.result.denied = true }
        for file in listing.largeFiles {
            state.result.largeFiles.append(DiskUsage.LargeFile(path: task.path + "/" + file.name, size: file.size, modified: file.modified))
        }

        for name in listing.directories {
            let path = task.path + "/" + name
            let hiddenName = name.hasPrefix(".") || name == "Library"
            if request.skipHidden && hiddenName && task.module < 0 { continue }
            var child = task.child
            if task.depth == 0 && request.breakdown {
                child = state.childNames.count
                state.childNames.append(name)
                state.childSizes.append(0)
            }
            var module = task.module
            if module < 0 && request.findNodeModules && !task.hidden && name == "node_modules" && task.depth < 8 {
                module = state.modulePaths.count
                state.modulePaths.append(path)
                state.moduleSizes.append(0)
            }
            let hidden = task.hidden || hiddenName || name.hasSuffix(".app") || name == "node_modules" || DiskUsage.isLibraryPackage(name)
            var recorded = task.recorded
            if task.depth + 1 <= request.recordDepth {
                recorded.append(state.recordedPaths.count)
                state.recordedPaths.append(path)
                state.recordedSizes.append(0)
            }
            state.stack.append(Task(path: path, depth: task.depth + 1, child: child, module: module, hidden: hidden, recorded: recorded))
            state.pending += 1
            queued += 1
        }
        if !state.stack.isEmpty && !isReady[index] {
            isReady[index] = true
            ready.append(index)
        }
        state.pending -= 1
        return state.pending == 0
    }
}

// MARK: - Lecture d'un dossier

/// Contenu d'un dossier, lu d'un coup avec `getattrlistbulk`.
private struct Listing {
    var size: UInt64 = 0
    var linked: [(UInt64, UInt64)] = []
    var directories: [String] = []
    var largeFiles: [(name: String, size: UInt64, modified: Date)] = []
    /// Fichiers d'au moins `fileMinimum` (explorateur).
    var files: [(name: String, size: UInt64)] = []
    var denied = false

    // Valeurs de <sys/attr.h> et <sys/vnode.h>, écrites ici car certaines ne passent pas en Swift.
    private static let returnedAttributes: UInt32 = 0x8000_0000
    private static let commonName: UInt32 = 0x0000_0001
    private static let commonType: UInt32 = 0x0000_0008
    private static let commonModified: UInt32 = 0x0000_0400
    private static let commonFileID: UInt32 = 0x0200_0000
    private static let fileLinkCount: UInt32 = 0x0000_0001
    private static let fileAllocatedSize: UInt32 = 0x0000_0004
    private static let typeRegular: UInt32 = 1
    private static let typeDirectory: UInt32 = 2

    static func read(_ path: String, buffer: UnsafeMutableRawPointer, size: Int, largeFileMinimum: UInt64?, fileMinimum: UInt64? = nil) -> Listing {
        var listing = Listing()
        let descriptor = open(path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else {
            listing.denied = errno == EPERM || errno == EACCES
            return listing
        }
        defer { close(descriptor) }
        var request = attrlist()
        request.bitmapcount = u_short(ATTR_BIT_MAP_COUNT)
        request.commonattr = returnedAttributes | commonName | commonType | commonModified | commonFileID
        request.fileattr = fileLinkCount | fileAllocatedSize
        while true {
            let count = getattrlistbulk(descriptor, &request, buffer, size, 0)
            if count < 0 {
                if errno == EPERM || errno == EACCES { listing.denied = true }
                break
            }
            if count == 0 { break }
            var entry = buffer
            for _ in 0..<count {
                let length = Int(entry.loadUnaligned(as: UInt32.self))
                var field = entry + 4
                let returned = field.loadUnaligned(as: attribute_set_t.self)
                field += MemoryLayout<attribute_set_t>.size
                var name = ""
                if returned.commonattr & commonName != 0 {
                    let reference = field.loadUnaligned(as: attrreference_t.self)
                    name = String(cString: (field + Int(reference.attr_dataoffset)).assumingMemoryBound(to: CChar.self))
                    field += MemoryLayout<attrreference_t>.size
                }
                var type: UInt32 = 0
                if returned.commonattr & commonType != 0 {
                    type = field.loadUnaligned(as: UInt32.self)
                    field += 4
                }
                var modified: Int = 0
                if returned.commonattr & commonModified != 0 {
                    modified = field.loadUnaligned(as: timespec.self).tv_sec
                    field += MemoryLayout<timespec>.size
                }
                var fileID: UInt64 = 0
                if returned.commonattr & commonFileID != 0 {
                    fileID = field.loadUnaligned(as: UInt64.self)
                    field += 8
                }
                var links: UInt32 = 1
                if returned.fileattr & fileLinkCount != 0 {
                    links = field.loadUnaligned(as: UInt32.self)
                    field += 4
                }
                var allocated: UInt64 = 0
                if returned.fileattr & fileAllocatedSize != 0 {
                    allocated = UInt64(max(0, field.loadUnaligned(as: Int64.self)))
                    field += 8
                }
                entry += length

                if type == typeDirectory {
                    listing.directories.append(name)
                } else {
                    if links > 1 && type == typeRegular {
                        listing.linked.append((fileID, allocated))
                    } else {
                        listing.size += allocated
                    }
                    if type == typeRegular, let minimum = fileMinimum, allocated >= minimum {
                        listing.files.append((name, allocated))
                    }
                    if type == typeRegular, let minimum = largeFileMinimum, allocated >= minimum {
                        listing.largeFiles.append((name, allocated, Date(timeIntervalSince1970: TimeInterval(modified))))
                    }
                }
            }
        }
        return listing
    }
}
