import Foundation

/// Projets de dev pas touchés depuis six mois : leurs dépendances et leurs compilations prennent de la place pour
/// rien, et se recréent (`npm install`, une compilation). Ton code et l'historique `.git` ne sont jamais proposés.
///
/// Dernière activité : le dernier commit Git et la date des fichiers du projet (pas ses dépendances ni ses compilations).
/// Dossiers recréables proposés : `node_modules` (déjà trouvés par l'analyse), plus les dossiers de compilation
/// connus. `dist`, `build` et `coverage` ne le sont que si Git les ignore (un projet peut y ranger du vrai code).
public enum DormantProjects {
    public static let dormantAfter: TimeInterval = 180 * 86_400

    /// Toujours des compilations ou des environnements recréables, quel que soit le projet.
    static let generated: [(name: String, title: L)] = [
        (".next", L("Compilation Next.js", "Next.js build")), (".nuxt", L("Compilation Nuxt", "Nuxt build")),
        (".output", L("Compilation Nuxt/Nitro", "Nuxt/Nitro build")), (".svelte-kit", L("Compilation SvelteKit", "SvelteKit build")),
        (".turbo", L("Cache Turborepo", "Turborepo cache")), (".parcel-cache", L("Cache Parcel", "Parcel cache")),
        (".expo", L("Cache Expo", "Expo cache")), (".angular", L("Cache Angular", "Angular cache")),
    ]
    /// Recréables seulement si Git les ignore.
    static let ignoredOnly: [(name: String, title: L)] = [
        ("dist", L("Compilation (dist)", "Build output (dist)")), ("build", L("Compilation (build)", "Build output (build)")),
        ("coverage", L("Rapport de couverture des tests", "Test coverage report")), ("target", L("Compilation Rust ou Java (target)", "Rust or Java build (target)")),
        (".venv", L("Environnement Python", "Python environment")), ("venv", L("Environnement Python", "Python environment")),
    ]

    /// Projets endormis parmi ceux de l'analyse (les dossiers qui ont un `node_modules`).
    public static func find(in report: StorageReport, now: Date = Date()) -> [StorageEntry] {
        let projects = report.entries(of: .project).filter { $0.path.hasSuffix("/node_modules") }
        var found: [StorageEntry] = []
        for module in projects {
            let project = (module.path as NSString).deletingLastPathComponent
            let activity = lastActivity(project)
            guard let activity, now.timeIntervalSince(activity) > dormantAfter else { continue }
            let folders = regenerableFolders(project)
            let measured = folders.isEmpty ? [] : DiskUsage.measure(folders.map { DiskUsage.Request(path: project + "/" + $0.name) })
            var children = [StorageEntry(id: "dormant-part:" + module.path, title: L("Dépendances (node_modules)", "Dependencies (node_modules)"),
                                         explanation: module.explanation, kind: .project, path: module.path, size: module.size)]
            for (folder, result) in zip(folders, measured) where result.exists && result.total > 0 {
                children.append(StorageEntry(id: "dormant-part:" + project + "/" + folder.name, title: folder.title,
                                             explanation: L("Se recrée à la prochaine compilation.", "Rebuilt on the next build."),
                                             kind: .project, path: project + "/" + folder.name, size: result.total))
            }
            let git = FileManager.default.fileExists(atPath: project + "/.git") ? DiskUsage.measure(project + "/.git").total : 0
            found.append(entry(project: project, activity: activity, children: children, gitSize: git, now: now))
        }
        return found.sorted { $0.size > $1.size }
    }

    static func entry(project: String, activity: Date, children: [StorageEntry], gitSize: UInt64, now: Date) -> StorageEntry {
        let name = PathRules.lastComponent(project)
        let size = children.reduce(UInt64(0)) { $0 + $1.size }
        let kept = { (language: Language) -> String in
            let fr = language == .fr
            let git = gitSize > 0 ? (fr ? " et son historique .git (\(Format.bytes(gitSize, decimal: true, in: language)))" : " and its .git history (\(Format.bytes(gitSize, decimal: true, in: language)))") : ""
            return fr ? "Pas touché depuis \(Format.ago(activity, in: language, now: now).replacingOccurrences(of: "il y a ", with: "")). Les dépendances et les compilations se recréent (npm install, compilation). Ton code\(git) restent."
                      : "Untouched for \(Format.ago(activity, in: language, now: now).replacingOccurrences(of: " ago", with: "")). Dependencies and builds come back (npm install, a build). Your code\(git) stay."
        }
        return StorageEntry(id: "dormant:" + project, title: L(name, name), explanation: L(kept(.fr), kept(.en)), kind: .project,
                            path: project, size: size, children: children, modified: activity)
    }

    /// Git installé pour de vrai. `/usr/bin/git` seul n'est qu'un relais : sans les outils de développement d'Apple,
    /// l'appeler ouvrirait la fenêtre d'installation.
    static let git: String? = {
        let fm = FileManager.default
        for path in ["/opt/homebrew/bin/git", "/usr/local/bin/git"] where fm.isExecutableFile(atPath: path) { return path }
        let developer = ["/Library/Developer/CommandLineTools/usr/bin/git", "/Applications/Xcode.app/Contents/Developer/usr/bin/git"]
        return developer.contains { fm.isExecutableFile(atPath: $0) } ? "/usr/bin/git" : nil
    }()

    /// Ce qui ne dit rien de ton activité : dépendances, compilations, réglages du Finder, Git lui-même.
    static let ignoredForActivity: Set<String> = Set(["node_modules", ".git", ".DS_Store"] + generated.map(\.name) + ignoredOnly.map(\.name))
    /// Dossiers de code regardés un niveau plus bas (un fichier modifié dans `src` change la date de `src`, pas celle du projet).
    static let codeFolders: Set<String> = ["src", "app", "lib", "pages", "components", "packages", "apps"]

    /// Dernière activité : le dernier commit, et la date des fichiers et dossiers du projet (sans dépendances ni
    /// compilations). Pas la date du dossier du projet : elle change quand on le range ailleurs.
    public static func lastActivity(_ project: String) -> Date? {
        let fm = FileManager.default
        var dates: [Date] = []
        func modified(_ path: String) -> Date? {
            (try? URL(fileURLWithPath: path).resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        }
        for name in (try? fm.contentsOfDirectory(atPath: project)) ?? [] where !ignoredForActivity.contains(name) {
            let path = project + "/" + name
            if let date = modified(path) { dates.append(date) }
            if codeFolders.contains(name) {
                for child in (try? fm.contentsOfDirectory(atPath: path)) ?? [] where child != ".DS_Store" {
                    if let date = modified(path + "/" + child) { dates.append(date) }
                }
            }
        }
        if fm.fileExists(atPath: project + "/.git"), let git,
           let seconds = TimeInterval(StartupReader.run(git, ["-C", project, "log", "-1", "--format=%ct"])
               .trimmingCharacters(in: .whitespacesAndNewlines)) {
            dates.append(Date(timeIntervalSince1970: seconds))
        }
        return dates.max()
    }

    /// Dossiers recréables présents dans le projet (sans `node_modules`, déjà connu).
    static func regenerableFolders(_ project: String) -> [(name: String, title: L)] {
        let fm = FileManager.default
        var folders = generated.filter { fm.fileExists(atPath: project + "/" + $0.name) }
        let candidates = ignoredOnly.filter { fm.fileExists(atPath: project + "/" + $0.name) }
        if !candidates.isEmpty, fm.fileExists(atPath: project + "/.git"), let git {
            let output = StartupReader.run(git, ["-C", project, "check-ignore"] + candidates.map(\.name))
            let ignored = Set(output.split(separator: "\n").map { String($0).trimmingCharacters(in: CharacterSet(charactersIn: "/")) })
            folders += candidates.filter { ignored.contains($0.name) }
        }
        return folders
    }
}
