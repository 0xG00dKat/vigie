import CryptoKit
import Darwin
import Foundation

// MARK: - Gros fichiers : type et filtres

/// Ce qu'est un gros fichier, pour les filtres (« Vidéos », « Archives »…).
public enum FileCategory: String, CaseIterable, Sendable, Codable {
    case video, image, audio, archive, document, other

    public init(path: String) {
        switch (path as NSString).pathExtension.lowercased() {
        case "mp4", "mov", "mkv", "avi", "m4v", "webm", "mts", "braw", "mpg", "mpeg", "wmv", "flv":
            self = .video
        case "jpg", "jpeg", "png", "heic", "heif", "tif", "tiff", "raw", "dng", "cr2", "cr3", "nef", "arw", "orf", "raf", "gif", "bmp", "webp", "exr", "psb":
            self = .image
        case "wav", "aif", "aiff", "flac", "mp3", "m4a", "aac", "ogg", "caf":
            self = .audio
        case "zip", "rar", "7z", "tar", "gz", "tgz", "xz", "bz2", "dmg", "iso", "img", "sparseimage", "sparsebundle", "pkg", "mpkg", "xip", "ipsw":
            self = .archive
        case "pdf", "doc", "docx", "pages", "key", "ppt", "pptx", "xls", "xlsx", "numbers", "psd", "ai", "indd", "sketch", "fig", "epub", "txt", "csv":
            self = .document
        default:
            self = .other
        }
    }

    public var title: String {
        switch self {
        case .video: return tr("Vidéos", "Videos")
        case .image: return tr("Images", "Images")
        case .audio: return tr("Audio", "Audio")
        case .archive: return tr("Archives et installeurs", "Archives and installers")
        case .document: return tr("Documents", "Documents")
        case .other: return tr("Autres", "Other")
        }
    }

    public var shortTitle: String {
        switch self {
        case .archive: return tr("Archives", "Archives")
        default: return title
        }
    }
}

public extension StorageEntry {
    var fileCategory: FileCategory { FileCategory(path: path) }

    /// Pas ouvert depuis six mois (dernière ouverture d'après Spotlight, sinon dernière modification).
    func isUnused(now: Date = Date()) -> Bool {
        guard let date = lastUsed ?? modified else { return false }
        return now.timeIntervalSince(date) > LargeFiles.unusedAfter
    }
}

/// Filtres de la page Gros fichiers : un type, et « pas ouverts depuis 6 mois ».
public struct LargeFileFilter: Sendable, Equatable {
    /// Types choisis (aucun : tous).
    public var categories: Set<FileCategory>
    public var unusedOnly: Bool

    public init(categories: Set<FileCategory> = [], unusedOnly: Bool = false) {
        self.categories = categories
        self.unusedOnly = unusedOnly
    }

    public init(category: FileCategory?, unusedOnly: Bool = false) {
        self.init(categories: category.map { [$0] } ?? [], unusedOnly: unusedOnly)
    }

    public var isActive: Bool { !categories.isEmpty || unusedOnly }

    public func matches(_ entry: StorageEntry, now: Date = Date()) -> Bool {
        if !categories.isEmpty, !categories.contains(entry.fileCategory) { return false }
        if unusedOnly && !entry.isUnused(now: now) { return false }
        return true
    }

    public func apply(_ entries: [StorageEntry], now: Date = Date()) -> [StorageEntry] {
        entries.filter { matches($0, now: now) }
    }
}

public enum LargeFiles {
    /// Six mois.
    public static let unusedAfter: TimeInterval = 180 * 86_400

    /// Dans iCloud Drive (Bureau et Documents synchronisés, ou le dossier iCloud Drive lui-même).
    public static func isInICloud(_ path: String) -> Bool {
        let values = try? URL(fileURLWithPath: path).resourceValues(forKeys: [.isUbiquitousItemKey])
        return values?.isUbiquitousItem ?? false
    }

    /// Place qui revient vraiment en supprimant ce fichier : sur APFS, une copie faite dans le Finder (« clone »)
    /// partage ses blocs avec l'original et ne libère presque rien. nil : macOS ne sait pas le dire.
    public static func privateSize(_ path: String) -> UInt64? {
        var list = attrlist()
        list.bitmapcount = u_short(ATTR_BIT_MAP_COUNT)
        list.commonattr = attrgroup_t(ATTR_CMN_RETURNED_ATTRS)
        list.forkattr = attrgroup_t(ATTR_CMNEXT_PRIVATESIZE)
        var buffer = [UInt8](repeating: 0, count: 64)
        let status = buffer.withUnsafeMutableBytes { raw in
            getattrlist(path, &list, raw.baseAddress, raw.count, UInt32(FSOPT_ATTR_CMN_EXTENDED | FSOPT_NOFOLLOW))
        }
        guard status == 0 else { return nil }
        return buffer.withUnsafeBytes { raw -> UInt64? in
            // Longueur (4 octets), attributs renvoyés (5 × 4 octets), puis la taille privée.
            let returned = raw.load(fromByteOffset: 4 + 16, as: UInt32.self) // forkattr
            guard returned & UInt32(ATTR_CMNEXT_PRIVATESIZE) != 0 else { return nil }
            return UInt64(max(0, raw.loadUnaligned(fromByteOffset: 24, as: Int64.self)))
        }
    }
}

// MARK: - Doublons

/// Un fichier présent plusieurs fois, au contenu identique octet pour octet.
public struct DuplicateGroup: Sendable, Identifiable, Equatable {
    public struct File: Sendable, Equatable, Identifiable {
        public var id: String { path }
        public var path: String
        public var modified: Date
        /// Place libérée en le supprimant (moins que la taille si c'est un clone APFS).
        public var freed: UInt64

        public init(path: String, modified: Date, freed: UInt64) {
            self.path = path
            self.modified = modified
            self.freed = freed
        }
    }

    /// Empreinte du contenu (SHA-256).
    public var id: String
    /// Taille d'une copie.
    public var size: UInt64
    /// La copie conseillée à garder en premier.
    public var files: [File]

    public init(id: String, size: UInt64, files: [File]) {
        self.id = id
        self.size = size
        self.files = files
    }

    public var name: String { PathRules.lastComponent(files.first?.path ?? "") }

    /// Place libérée en gardant `keep` (la copie conseillée par défaut) et en jetant les autres.
    public func freed(keeping keep: String? = nil) -> UInt64 {
        let kept = keep ?? files.first?.path
        return files.filter { $0.path != kept }.reduce(0) { $0 + $1.freed }
    }

    public func others(keeping keep: String? = nil) -> [String] {
        let kept = keep ?? files.first?.path
        return files.map(\.path).filter { $0 != kept }
    }
}

/// Cherche les doublons dans tes dossiers : même taille, puis même début et même fin, puis même contenu complet
/// (SHA-256). Deux fichiers ne sont jamais dits identiques sur leur nom ou leur taille seuls.
///
/// Jamais proposés : les fichiers d'un projet de code (un dossier `.git` au-dessus : ils font partie du projet),
/// les apps, les bibliothèques Photos ou Musique, les fichiers à plusieurs liens physiques, et les fichiers restés
/// dans iCloud (les lire les téléchargerait).
public enum DuplicateFinder {
    public static let minimumSize: UInt64 = 1_000_000

    public static func roots(home: String = NSHomeDirectory()) -> [String] {
        ["Desktop", "Documents", "Downloads", "Movies", "Pictures", "Music"].map { home + "/" + $0 }
    }

    /// `progress` : de 0 à 1 (la lecture des dossiers, puis la comparaison des contenus).
    public static func find(roots: [String], minimumSize: UInt64 = minimumSize, limit: Int = 200,
                            progress: (@Sendable (Double) -> Void)? = nil) -> [DuplicateGroup] {
        progress?(0)
        let listed = DiskUsage.measure(roots.map { DiskUsage.Request(path: $0, largeFileMinimum: minimumSize) })
            .flatMap(\.largeFiles)
        progress?(0.2)
        var insideProject: [String: Bool] = [:]
        let candidates = listed.filter { !isInsideCodeProject($0.path, roots: roots, cache: &insideProject) }
        return group(candidates.map(\.path), limit: limit) { progress?(0.2 + 0.8 * $0) }
    }

    /// Regroupe les fichiers donnés par contenu identique.
    public static func group(_ paths: [String], limit: Int = 200, progress: ((Double) -> Void)? = nil) -> [DuplicateGroup] {
        struct Candidate {
            var path: String
            var length: UInt64
            var modified: Date
        }
        // Même taille exacte (en octets). Un fichier à plusieurs liens physiques n'est jamais proposé :
        // en jeter un nom ne libère rien.
        var bySize: [UInt64: [Candidate]] = [:]
        for path in Set(paths).sorted() {
            var info = stat()
            guard lstat(path, &info) == 0, info.st_mode & S_IFMT == S_IFREG, info.st_size > 0, info.st_nlink == 1 else { continue }
            // Fichier resté dans iCloud (« sans données ») : le lire le téléchargerait.
            if info.st_flags & UInt32(SF_DATALESS) != 0 { continue }
            let modified = Date(timeIntervalSince1970: TimeInterval(info.st_mtimespec.tv_sec))
            bySize[UInt64(info.st_size), default: []].append(Candidate(path: path, length: UInt64(info.st_size), modified: modified))
        }
        let sameSize = bySize.values.filter { $0.count > 1 }

        // Même début et même fin : écarte vite les fichiers de même taille mais différents.
        var sampled: [[Candidate]] = []
        for candidates in sameSize {
            var bySample: [String: [Candidate]] = [:]
            for candidate in candidates {
                guard let sample = sampleDigest(candidate.path, length: candidate.length) else { continue }
                bySample[sample, default: []].append(candidate)
            }
            sampled.append(contentsOf: bySample.values.filter { $0.count > 1 })
        }

        // Contenu complet.
        let totalBytes = max(1, sampled.reduce(UInt64(0)) { $0 + $1.reduce(0) { $0 + $1.length } })
        var hashedBytes: UInt64 = 0
        var groups: [DuplicateGroup] = []
        for candidates in sampled {
            var byDigest: [String: [Candidate]] = [:]
            for candidate in candidates {
                if let digest = fullDigest(candidate.path) {
                    byDigest[digest, default: []].append(candidate)
                }
                hashedBytes += candidate.length
                progress?(Double(hashedBytes) / Double(totalBytes))
            }
            for (digest, same) in byDigest where same.count > 1 {
                let files = same.map { candidate in
                    DuplicateGroup.File(path: candidate.path, modified: candidate.modified,
                                        freed: LargeFiles.privateSize(candidate.path) ?? candidate.length)
                }
                groups.append(DuplicateGroup(id: digest, size: same[0].length, files: orderedForKeeping(files)))
            }
        }
        progress?(1)
        return Array(groups.sorted { $0.freed() > $1.freed() }.prefix(limit))
    }

    /// La copie à garder d'abord : pas un nom de copie (« (1) », « copie »), pas dans Téléchargements,
    /// la plus ancienne (souvent l'originale), puis le chemin le plus court.
    public static func orderedForKeeping(_ files: [DuplicateGroup.File]) -> [DuplicateGroup.File] {
        files.sorted { a, b in
            let (copyA, copyB) = (looksLikeCopy(a.path), looksLikeCopy(b.path))
            if copyA != copyB { return !copyA }
            let (downloadA, downloadB) = (a.path.contains("/Downloads/"), b.path.contains("/Downloads/"))
            if downloadA != downloadB { return !downloadA }
            if a.modified != b.modified { return a.modified < b.modified }
            if a.path.count != b.path.count { return a.path.count < b.path.count }
            return a.path < b.path
        }
    }

    /// « photo (1).jpg », « rapport copie.pdf », « notes copy 2.txt », « film-1.mov » ne sont pas l'original.
    public static func looksLikeCopy(_ path: String) -> Bool {
        let stem = ((PathRules.lastComponent(path) as NSString).deletingPathExtension).lowercased()
        if stem.range(of: #"\s\(\d+\)$"#, options: .regularExpression) != nil { return true }
        if stem.range(of: #"\s(copie|copy|kopie|copia)(\s\d+)?$"#, options: .regularExpression) != nil { return true }
        if stem.range(of: #"-\d$"#, options: .regularExpression) != nil { return true }
        return false
    }

    /// Un dossier `.git` entre le fichier et la racine de la recherche : le fichier fait partie d'un projet de code.
    static func isInsideCodeProject(_ path: String, roots: [String], cache: inout [String: Bool]) -> Bool {
        guard let root = roots.first(where: { path.hasPrefix($0 + "/") }) else { return false }
        var folder = (path as NSString).deletingLastPathComponent
        var visited: [String] = []
        var answer = false
        while folder.count > root.count {
            if let known = cache[folder] { answer = known; break }
            visited.append(folder)
            if FileManager.default.fileExists(atPath: folder + "/.git") { answer = true; break }
            folder = (folder as NSString).deletingLastPathComponent
        }
        // Tous les dossiers parcourus partagent la réponse (un projet contient ses sous-dossiers).
        for item in visited { cache[item] = answer }
        return answer
    }

    // MARK: Lecture

    static let sampleSize = 64 * 1024

    static func sampleDigest(_ path: String, length: UInt64) -> String? {
        let fd = open(path, O_RDONLY)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        _ = fcntl(fd, F_NOCACHE, 1)
        var hasher = SHA256()
        var buffer = [UInt8](repeating: 0, count: sampleSize)
        let offsets: [off_t] = length > UInt64(sampleSize * 2) ? [0, off_t(length) - off_t(sampleSize)] : [0]
        for offset in offsets {
            let count = buffer.withUnsafeMutableBytes { pread(fd, $0.baseAddress, sampleSize, offset) }
            guard count >= 0 else { return nil }
            hasher.update(data: buffer[0..<count])
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    static func fullDigest(_ path: String) -> String? {
        let fd = open(path, O_RDONLY)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        _ = fcntl(fd, F_NOCACHE, 1)
        var hasher = SHA256()
        let chunk = 1 << 20
        var buffer = [UInt8](repeating: 0, count: chunk)
        while true {
            let count = buffer.withUnsafeMutableBytes { read(fd, $0.baseAddress, chunk) }
            if count < 0 { return nil }
            if count == 0 { break }
            hasher.update(data: buffer[0..<count])
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
