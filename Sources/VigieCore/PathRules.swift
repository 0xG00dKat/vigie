import Foundation

/// Règles de classement fondées sur les chemins des exécutables.
public enum PathRules {
    public static func normalize(_ path: String) -> String {
        var result = path
        while result.count > 1, result.hasSuffix("/") { result.removeLast() }
        return result
    }

    /// Tous les paquets `.app` qui contiennent ce chemin, du plus extérieur au plus intérieur.
    /// `/Applications/Opera.app/Contents/Frameworks/…/Opera Helper.app/Contents/MacOS/Opera Helper`
    /// → `["/Applications/Opera.app", "/Applications/Opera.app/…/Opera Helper.app"]`
    public static func bundleCandidates(_ path: String) -> [String] {
        var result: [String] = []
        var searchRange = path.startIndex..<path.endIndex
        while let range = path.range(of: ".app/", range: searchRange) {
            let end = path.index(range.lowerBound, offsetBy: 4)
            result.append(String(path[path.startIndex..<end]))
            searchRange = range.upperBound..<path.endIndex
        }
        return result
    }

    private static let systemPrefixes = ["/System/", "/usr/", "/bin/", "/sbin/", "/Library/Apple/", "/private/", "/Library/Preferences/"]

    public static func isSystem(_ path: String) -> Bool {
        if path.hasPrefix("/usr/local/") { return false }
        return systemPrefixes.contains { path.hasPrefix($0) }
    }

    /// Emplacements typiques d'outils installés par l'utilisateur (Homebrew, npm, uv, binaires compilés…).
    public static func isDevLocation(_ path: String, home: String) -> Bool {
        let prefixes = [
            home + "/", "/opt/", "/usr/local/", "/nix/", "/Library/Frameworks/", "/Library/Java/",
            "/Library/Developer/", "/private/tmp/", "/private/var/folders/",
        ]
        return prefixes.contains { path.hasPrefix($0) } || path.contains("/Contents/Developer/")
    }

    /// Outils de dev installés avec macOS (dans /usr/bin…), à ranger quand même dans « Dev & terminal ».
    private static let devToolNames: Set<String> = [
        "python", "ruby", "perl", "php", "java", "ssh", "scp", "sftp", "rsync", "git", "make",
        "caffeinate", "sqlite3", "tmux", "screen", "vim", "nvim", "swift", "swift-build", "swift-frontend",
        "xcodebuild", "clang", "lldb", "sourcekit-lsp", "curl",
    ]

    public static func isDevTool(name: String) -> Bool {
        devToolNames.contains(name) || name.hasPrefix("python")
    }

    /// Un dossier de travail qui ressemble à un projet (et pas à `/`, au dossier perso ou aux données d'une app).
    public static func isProjectDirectory(_ cwd: String, home: String) -> Bool {
        let path = normalize(cwd)
        if path == "/" || path == home { return false }
        if path.hasPrefix(home + "/Library/") || path == home + "/Library" { return false }
        if path.contains(".app/") || path.hasSuffix(".app") { return false }
        if path.hasPrefix("/private/var/folders/") { return false }
        if isSystem(path) && !path.hasPrefix("/private/tmp/") { return false }
        return true
    }

    public static func abbreviate(_ path: String, home: String) -> String {
        if path == home { return "~" }
        if path.hasPrefix(home + "/") { return "~" + path.dropFirst(home.count) }
        return path
    }

    public static func lastComponent(_ path: String) -> String {
        (path as NSString).lastPathComponent
    }

    static func looksLikeVersion(_ name: String) -> Bool {
        !name.isEmpty && name.contains(".") && name.allSatisfy { $0.isNumber || $0 == "." }
    }

    /// Nom lisible d'un processus de dev. Claude Code, par exemple, s'exécute depuis
    /// `~/.local/share/claude/versions/2.1.319` : on préfère alors le nom sous lequel il a été lancé (`claude`).
    public static func devDisplayName(path: String, fallback: String, arguments: [String]) -> String {
        let base = path.isEmpty ? fallback : lastComponent(path)
        if looksLikeVersion(base), let first = arguments.first {
            let launched = lastComponent(first)
            if !launched.isEmpty { return launched }
        }
        return base
    }

    /// Nom du paquet sans « .app ».
    public static func bundleDisplayName(_ bundlePath: String) -> String {
        let last = lastComponent(bundlePath)
        return cleanName(last.hasSuffix(".app") ? String(last.dropLast(4)) : last)
    }

    /// Retire les caractères invisibles de direction (WhatsApp nomme son app « \u{200E}WhatsApp »).
    public static func cleanName(_ name: String) -> String {
        name.trimmingCharacters(in: CharacterSet.controlCharacters.union(.whitespacesAndNewlines))
    }
}
