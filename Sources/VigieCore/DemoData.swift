import Foundation

/// Un Mac fictif pour les captures d'écran du README (`Vigie --render image.png --demo`).
/// Les processus sont inventés mais passent par la vraie logique de regroupement.
public enum DemoData {
    public static let home = "/Users/demo"
    static let uid: UInt32 = 501

    public static func snapshot(now: Date = Date()) -> Snapshot {
        let english = Localization.current == .en
        var processes: [RawProcess] = []
        var details: [Int32: ProcessDetails] = [:]
        var nextPID: Int32 = 2000

        func ago(_ hours: Double) -> Date { now.addingTimeInterval(-hours * 3600) }
        @discardableResult
        func add(_ name: String, _ path: String, ppid: Int32 = 1, pid: Int32? = nil, uid: UInt32 = DemoData.uid,
                 mb: Double, cpu: Double = 0, hours: Double, responsible: Int32? = nil,
                 cwd: String? = nil, args: [String] = [], ports: [Int] = [], exposed: [Int] = []) -> Int32 {
            let id = pid ?? { nextPID += 1; return nextPID }()
            processes.append(RawProcess(
                pid: id, ppid: ppid, uid: uid, name: name, path: path, startTime: ago(hours),
                memory: UInt64(mb * 1_048_576), cpuPercent: cpu, responsiblePID: responsible
            ))
            if cwd != nil || !args.isEmpty || !ports.isEmpty {
                details[id] = ProcessDetails(cwd: cwd, arguments: args, listeningPorts: ports, exposedPorts: exposed)
            }
            return id
        }

        var apps: [RunningApp] = []
        func app(_ name: String, _ bundle: String, _ id: String, executable: String, pid: Int32,
                 mb: Double, cpu: Double = 0, hours: Double, policy: ActivationPolicy = .regular) {
            apps.append(RunningApp(pid: pid, bundlePath: bundle, bundleID: id, name: name, policy: policy))
            add(executable, bundle + "/Contents/MacOS/" + executable, pid: pid, mb: mb, cpu: cpu, hours: hours)
        }
        func helpers(_ count: Int, of parent: Int32, bundle: String, helper: String, mb: [Double], hours: Double) {
            for index in 0..<count {
                add(helper, "\(bundle)/Contents/Frameworks/\(helper).app/Contents/MacOS/\(helper)",
                    ppid: parent, mb: mb[index % mb.count], cpu: index == 0 ? 2.4 : 0, hours: hours)
            }
        }

        // Apps du Dock, avec leurs processus d'aide.
        app("Safari", URL(fileURLWithPath: "/Applications/Safari.app").resolvingSymlinksInPath().path, "com.apple.Safari", executable: "Safari", pid: 1001, mb: 410, cpu: 3.1, hours: 50)
        let webContent = "/System/Library/Frameworks/WebKit.framework/Versions/A/XPCServices/com.apple.WebKit.WebContent.xpc/Contents/MacOS/com.apple.WebKit.WebContent"
        for mb in [612.0, 388, 240, 196, 151, 120, 96, 74, 61] {
            add("com.apple.WebKit.WebContent", webContent, mb: mb, hours: 12, responsible: 1001)
        }

        let code = "/Applications/Visual Studio Code.app"
        app("Code", code, "com.microsoft.VSCode", executable: "Electron", pid: 1002, mb: 260, cpu: 1.2, hours: 6.2)
        helpers(7, of: 1002, bundle: code, helper: "Code Helper (Renderer)", mb: [520, 310, 180, 120], hours: 6.2)

        let slack = "/Applications/Slack.app"
        app("Slack", slack, "com.tinyspeck.slackmacgap", executable: "Slack", pid: 1003, mb: 180, hours: 74)
        helpers(5, of: 1003, bundle: slack, helper: "Slack Helper (Renderer)", mb: [410, 160, 90], hours: 74)

        let figma = "/Applications/Figma.app"
        app("Figma", figma, "com.figma.Desktop", executable: "Figma", pid: 1004, mb: 220, hours: 3.4)
        helpers(6, of: 1004, bundle: figma, helper: "Figma Helper (Renderer)", mb: [680, 240, 110], hours: 3.4)

        app("Spotify", "/Applications/Spotify.app", "com.spotify.client", executable: "Spotify", pid: 1005, mb: 210, cpu: 1.8, hours: 26)
        helpers(3, of: 1005, bundle: "/Applications/Spotify.app", helper: "Spotify Helper", mb: [190, 80], hours: 26)

        app("Mail", "/System/Applications/Mail.app", "com.apple.mail", executable: "Mail", pid: 1006, mb: 240, hours: 200)
        app("Notes", "/System/Applications/Notes.app", "com.apple.Notes", executable: "Notes", pid: 1007, mb: 130, hours: 200)
        app("Terminal", "/System/Applications/Utilities/Terminal.app", "com.apple.Terminal", executable: "Terminal", pid: 1008, mb: 95, hours: 30)
        app("Finder", "/System/Library/CoreServices/Finder.app", "com.apple.finder", executable: "Finder", pid: 1009, mb: 160, hours: 200)

        // Un site en développement, lancé depuis le Terminal.
        let site = home + (english ? "/code/my-site" : "/code/mon-site")
        let shell1 = add("zsh", "/bin/zsh", ppid: 1008, mb: 3, hours: 5)
        let pnpm = add("node", "/opt/homebrew/bin/node", ppid: shell1, mb: 82, hours: 4.1,
                       cwd: site, args: ["node", "/opt/homebrew/bin/pnpm", "dev"])
        let astro = add("node", "/opt/homebrew/bin/node", ppid: pnpm, mb: 340, cpu: 4.2, hours: 4.1,
                        cwd: site, args: ["node", site + "/node_modules/astro/astro.js", "dev", "--port", "4321"], ports: [4321])
        add("esbuild", site + "/node_modules/@esbuild/darwin-arm64/bin/esbuild", ppid: astro, mb: 24, hours: 4.1,
            cwd: site, args: ["esbuild", "--service=0.21.5", "--ping"])

        // Une API avec une session Claude Code ouverte dans le terminal de VS Code.
        let api = home + (english ? "/code/invoices-api" : "/code/api-factures")
        let shell2 = add("zsh", "/bin/zsh", ppid: 1002, mb: 3, hours: 2)
        let claude = add("claude", home + "/.local/share/claude/versions/2.1.0", ppid: shell2, mb: 310, cpu: 6.5, hours: 1.6,
                         cwd: api, args: ["claude"])
        add("node", "/opt/homebrew/bin/node", ppid: claude, mb: 64, hours: 1.6, cwd: api, args: ["node", "github-mcp/server.js", "mcp"])
        add("uv", home + "/.local/bin/uv", ppid: claude, mb: 38, hours: 1.6, cwd: api, args: ["uvx", "postgres-mcp", "--access-mode=restricted"])
        add("python3.13", "/opt/homebrew/bin/python3.13", ppid: shell2, mb: 118, cpu: 0.6, hours: 1.9,
            cwd: api, args: ["python3.13", "-m", "uvicorn", "app.main:app", "--reload", "--port", "8000"], ports: [8000])

        // Un serveur oublié, dont le terminal a été fermé il y a deux jours.
        add("python3", "/usr/bin/python3", mb: 19, hours: 52, cwd: home + "/code/prototype",
            args: ["python3", "-m", "http.server", "8080"], ports: [8080], exposed: [8080])

        // Une base de données lancée par Homebrew.
        add("postgres", "/opt/homebrew/opt/postgresql@16/bin/postgres", mb: 46, hours: 200,
            cwd: "/opt/homebrew/var/postgresql@16", args: ["postgres", "-D", "/opt/homebrew/var/postgresql@16"], ports: [5432])

        // Arrière-plan.
        app("Dropbox", "/Applications/Dropbox.app", "com.getdropbox.dropbox", executable: "Dropbox", pid: 1010, mb: 290, hours: 200, policy: .accessory)
        add("com.docker.backend", "/Applications/Docker.app/Contents/MacOS/com.docker.backend", mb: 180, hours: 200)
        add("com.docker.virtualization", "/Applications/Docker.app/Contents/MacOS/com.docker.virtualization", mb: 1450, cpu: 2.0, hours: 200)

        // Système : quelques centaines de services de macOS.
        add("kernel_task", "", pid: 0, uid: 0, mb: 0, cpu: 3.0, hours: 200)
        add("launchd", "/sbin/launchd", pid: 1, uid: 0, mb: 12, hours: 200)
        add("WindowServer", "/System/Library/PrivateFrameworks/SkyLight.framework/Resources/WindowServer", uid: 88, mb: 820, cpu: 5.1, hours: 200)
        let daemons = [
            "mds_stores", "mdworker_shared", "mdworker_shared", "mdworker_shared", "corespotlightd", "photoanalysisd",
            "cloudd", "bird", "nsurlsessiond", "trustd", "syspolicyd", "coreaudiod", "bluetoothd", "airportd", "locationd",
            "sharingd", "rapportd", "cfprefsd", "cfprefsd", "distnoted", "distnoted", "powerd", "logd", "mDNSResponder",
            "configd", "fseventsd", "tccd", "lsd", "runningboardd", "usernoted", "apsd", "identityservicesd", "akd",
            "accountsd", "suggestd", "routined", "mobileassetd", "contactsd", "remindd", "UserEventAgent",
        ]
        for index in 0..<640 {
            let name = daemons[index % daemons.count]
            add(name, "/usr/libexec/" + name, uid: index % 3 == 0 ? 0 : DemoData.uid, mb: Double(4 + (index * 7) % 60), hours: 200)
        }
        for _ in 0..<6 {
            add("MTLCompilerService", "/System/Library/Frameworks/Metal.framework/Versions/A/XPCServices/MTLCompilerService.xpc/Contents/MacOS/MTLCompilerService", mb: 22, hours: 30)
        }

        let builder = GroupBuilder(
            runningApps: apps,
            myUID: uid,
            myPID: 99_999,
            homeDirectory: home,
            protectedBundleIDs: SnapshotBuilder.protectedBundleIDs,
            details: { details[$0.pid] ?? .empty },
            bundleInfo: { BundleInfoCache.shared.info(for: $0) }
        )
        var children: [Int32: [Int32]] = [:]
        for process in processes where process.ppid > 0 {
            children[process.ppid, default: []].append(process.pid)
        }
        return Snapshot(
            groups: builder.build(processes),
            processCount: processes.count,
            memoryUsed: 21 * 1_073_741_824,
            memoryTotal: 32 * 1_073_741_824,
            date: now,
            children: children
        )
    }
}

extension DemoData {
    /// Docker fictif : un projet Compose et un conteneur isolé, avec un cache de construction qui grossit.
    public static func docker(now: Date = Date()) -> DockerStatus {
        let project = Localization.current == .en ? "invoices-api" : "api-factures"
        func ago(_ hours: Double) -> Date { now.addingTimeInterval(-hours * 3600) }
        let containers = [
            DockerContainer(id: "a1", name: "\(project)-db-1", image: "postgres:16", project: project, service: "db",
                            ports: [5433], startedAt: ago(2), cpuPercent: 0.4, memory: 96 * 1_048_576),
            DockerContainer(id: "a2", name: "\(project)-redis-1", image: "redis:7", project: project, service: "redis",
                            ports: [6379], startedAt: ago(2), cpuPercent: 0.2, memory: 14 * 1_048_576),
            DockerContainer(id: "b1", name: "minio", image: "minio/minio:latest",
                            ports: [9000, 9001], startedAt: ago(75), cpuPercent: 0.1, memory: 182 * 1_048_576),
        ]
        let gigabyte: UInt64 = 1_000_000_000
        let disk = DockerDiskUsage(
            images: .init(size: 6_200_000_000, reclaimable: 2_800_000_000, count: 9, active: 3),
            containers: .init(size: 120_000_000, reclaimable: 40_000_000, count: 5, active: 3),
            volumes: .init(size: 3_400_000_000, reclaimable: 900_000_000, count: 4, active: 2),
            buildCache: .init(size: 9_700_000_000, reclaimable: 9_700_000_000, count: 61, active: 0)
        )
        return DockerStatus(
            state: .running,
            containers: containers,
            stoppedContainers: 2,
            disk: disk,
            virtualDisk: DockerVirtualDisk(engine: "Docker Desktop", path: home + "/Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw",
                                           allocated: 24 * gigabyte, maximum: 64 * gigabyte),
            date: now
        )
    }

    /// Disque fictif : confortable par défaut, presque plein avec `low: true` (pour montrer l'alerte).
    public static func disk(low: Bool = false) -> DiskStatus {
        let total: UInt64 = 494_000_000_000
        return DiskStatus(available: low ? 58_000_000_000 : 182_000_000_000, total: total)
    }
}

extension DemoData {
    /// Analyse de stockage fictive, pour les captures et les tests.
    public static func storage(now: Date = Date()) -> StorageReport {
        let gigabyte: UInt64 = 1_000_000_000
        func cacheChild(_ parent: String, _ name: String, _ size: UInt64, kind: StorageKind = .cache) -> StorageEntry {
            let info = StorageCatalog.child(name, parentKind: kind)
            return StorageEntry(id: parent + "/" + name, title: L(name, name), explanation: info.explanation, kind: kind,
                                path: home + "/" + parent + "/" + name, size: size, command: info.command)
        }
        let location = { (id: String) in StorageCatalog.locations.first { $0.id == id }! }
        func entry(_ id: String, _ size: UInt64, children: [StorageEntry] = []) -> StorageEntry {
            let known = location(id)
            return StorageEntry(id: id, title: known.title, explanation: known.explanation, kind: known.kind,
                                path: home + "/" + known.path, size: size, command: known.command, children: children)
        }
        func project(_ name: String, _ size: UInt64, monthsAgo: Double) -> StorageEntry {
            StorageEntry(id: "project:" + name, title: L(name, name),
                         explanation: L("Dépendances JavaScript du projet : npm install (ou pnpm install) les réinstalle.",
                                        "The project's JavaScript dependencies: npm install (or pnpm install) reinstalls them."),
                         kind: .project, path: home + "/code/" + name + "/node_modules", size: size,
                         modified: now.addingTimeInterval(-monthsAgo * 30 * 86_400))
        }
        func footprint(_ title: L, _ explanation: L, _ relative: String, _ size: UInt64, isProtected: Bool = false,
                       kind: StorageKind = .appData, prefix: String = "footprint:") -> StorageEntry {
            StorageEntry(id: prefix + home + "/Library/" + relative, title: title, explanation: explanation, kind: kind,
                         path: home + "/Library/" + relative, size: size, isProtected: isProtected)
        }
        func application(_ name: String, id: String, appSize: UInt64, daysAgo: Double, data: [StorageEntry]) -> StorageEntry {
            let dataSize = data.reduce(UInt64(0)) { $0 + $1.size }
            let lastUsed = now.addingTimeInterval(-daysAgo * 86_400)
            let summary = { (language: Language) in
                StorageScanner.applicationSummary(appSize: appSize, dataSize: dataSize, places: data.count, lastUsed: lastUsed,
                                                  in: language, now: now)
            }
            return StorageEntry(id: "application:/Applications/\(name).app", title: L(name, name), explanation: L(summary(.fr), summary(.en)),
                                kind: .application, path: "/Applications/\(name).app", size: appSize + dataSize, children: data,
                                modified: lastUsed)
        }
        func leftover(_ id: String, _ title: L, _ relative: String, _ size: UInt64) -> StorageEntry {
            let child = footprint(title, L("Reste d'une app qui n'est plus installée.", "Left by an app that is no longer installed."),
                                  relative, size, kind: .leftover, prefix: "leftover-file:")
            return StorageEntry(id: "leftover:" + id, title: L(id, id),
                                explanation: L("Restes d'une app qui n'est plus installée. À la corbeille, tu peux revenir en arrière.",
                                               "Left by an app that is no longer installed. They go to the Trash, so you can undo."),
                                kind: .leftover, path: child.path, size: size, children: [child])
        }
        let english = Localization.current == .en
        return StorageReport(entries: [
            entry("dotcache", 14 * gigabyte, children: [cacheChild(".cache", "uv", 9_600_000_000), cacheChild(".cache", "huggingface", 3_100_000_000)]),
            entry("caches", 11 * gigabyte, children: [
                cacheChild("Library/Caches", "Google", 2_400_000_000), cacheChild("Library/Caches", "ms-playwright", 1_300_000_000),
                cacheChild("Library/Caches", "Homebrew", 1_100_000_000),
            ]),
            entry("npm", 8_700_000_000),
            entry("pnpm-store", 7_400_000_000),
            entry("derived-data", 5_200_000_000),
            project(english ? "my-site" : "mon-site", 1_900_000_000, monthsAgo: 0.2),
            project("old-landing", 1_400_000_000, monthsAgo: 9),
            project("hackathon-2025", 1_100_000_000, monthsAgo: 14),
            entry("rustup", 2_900_000_000),
            // Apps avec leurs dossiers éparpillés dans la bibliothèque, regroupés comme dans l'analyse réelle.
            application("Claude", id: "com.anthropic.claudefordesktop", appSize: 640_000_000, daysAgo: 0.1, data: [
                footprint(AppFootprint.dataTitle, AppFootprint.dataExplanation, "Application Support/Claude", 6_300_000_000),
                footprint(L("Journaux", "Logs"), L("Historique technique de l'app.", "The app's technical history."), "Logs/Claude", 42_000_000),
                footprint(AppFootprint.cacheTitle, AppFootprint.cacheExplanation, "Caches/com.anthropic.claudefordesktop", 18_000_000),
                footprint(L("Réglages", "Settings"), L("Tes réglages pour cette app.", "Your settings for this app."),
                          "Preferences/com.anthropic.claudefordesktop.plist", 12_000),
            ]),
            application("Docker", id: "com.docker.docker", appSize: 2_100_000_000, daysAgo: 1, data: [
                StorageEntry(id: "footprint:docker", title: L("Disque virtuel de Docker", "Docker virtual disk"),
                             explanation: L("Images, conteneurs et volumes de Docker : détail et nettoyage dans la section Docker.",
                                            "Docker images, containers and volumes: details and cleanup in the Docker section."),
                             kind: .appData, path: home + "/Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw",
                             size: 24 * gigabyte, command: "docker system prune"),
                footprint(L("Dossier privé de l'app", "App's private folder"),
                          L("Données que macOS range à part pour cette app (documents, caches, réglages).", "Data macOS keeps apart for this app (documents, caches, settings)."),
                          "Containers/com.docker.docker", 0, isProtected: true),
            ]),
            application("Figma", id: "com.figma.Desktop", appSize: 410_000_000, daysAgo: 6, data: [
                footprint(AppFootprint.dataTitle, AppFootprint.dataExplanation, "Application Support/Figma", 1_200_000_000),
                footprint(AppFootprint.cacheTitle, AppFootprint.cacheExplanation, "Caches/com.figma.Desktop", 260_000_000),
            ]),
            application(english ? "Old Game" : "Vieux Jeu", id: "com.example.oldgame", appSize: 3_400_000_000, daysAgo: 240, data: [
                footprint(AppFootprint.dataTitle, AppFootprint.dataExplanation, "Application Support/Old Game", 900_000_000),
            ]),
            // Restes d'une app supprimée, et ce que macOS range dans « Données système ».
            StorageEntry(id: "leftover:com.spotify.client", title: L("com.spotify.client", "com.spotify.client"),
                         explanation: L("Restes d'une app qui n'est plus installée : 3 dossiers (données, caches, réglages). À la corbeille, tu peux revenir en arrière.",
                                        "Left by an app that is no longer installed: 3 folders (data, caches, settings). They go to the Trash, so you can undo."),
                         kind: .leftover, path: home + "/Library/Caches/com.spotify.client", size: 612_000_000, children: [
                            footprint(L("Cache", "Cache"), L("Reste d'une app qui n'est plus installée.", "Left by an app that is no longer installed."),
                                      "Caches/com.spotify.client", 540_000_000, kind: .leftover, prefix: "leftover-file:"),
                            footprint(L("Données", "Data"), L("Reste d'une app qui n'est plus installée.", "Left by an app that is no longer installed."),
                                      "Application Support/com.spotify.client", 72_000_000, kind: .leftover, prefix: "leftover-file:"),
                            footprint(L("Réglages", "Settings"), L("Reste d'une app qui n'est plus installée.", "Left by an app that is no longer installed."),
                                      "Preferences/com.spotify.client.plist", 8_000, kind: .leftover, prefix: "leftover-file:"),
                         ]),
            leftover("org.mozilla.firefox", L("Profils et cache", "Profiles and cache"), "Application Support/Firefox", 184_000_000),
            leftover("com.setapp.DesktopClient", L("Données", "Data"), "Application Support/Setapp", 22_000_000),
            ] + SystemAssets.entries(from: [("com_apple_MobileAsset_iOSSimulatorRuntime", 18_400_000_000),
                                            ("com_apple_MobileAsset_UAF_Siri_Understanding", 5_800_000_000),
                                            ("com_apple_MobileAsset_UAF_FM_GenerativeModels", 3_600_000_000),
                                            ("com_apple_MobileAsset_AppleDeveloperDocumentation", 3_200_000_000),
                                            ("com_apple_MobileAsset_Font8", 900_000_000)], minimumSize: 50_000_000) + [
            entry("downloads", 6_800_000_000),
        ] + largeFiles(now: now) + [
            StorageEntry(id: "trash", title: location("trash").title, explanation: location("trash").explanation, kind: .personal,
                         path: home + "/.Trash", size: 0, isProtected: true),
        ].sorted { $0.size > $1.size }, localSnapshots: 2, date: now)
    }
}

extension DemoData {
    /// Règles fictives : une alerte de mémoire et une fermeture du soir.
    public static func rules() -> [VigieRule] {
        [VigieRule(appName: "Slack", kind: .memoryAbove(bytes: 3_000_000_000)),
         VigieRule(appName: "Slack", kind: .quitAt(hour: 19, minute: 0)),
         VigieRule(appName: "Figma", kind: .memoryAbove(bytes: 4_000_000_000), isEnabled: false)]
    }

    /// Historique fictif sur 90 jours : le disque se remplit (surtout Docker et les caches de uv), Slack pèse lourd
    /// l'après-midi, une analyse du stockage par semaine.
    public static func history(now: Date = Date()) -> [HistoryPoint] {
        let gigabyte: UInt64 = 1_000_000_000
        let total: UInt64 = 494 * gigabyte
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        var points: [HistoryPoint] = []
        for day in stride(from: 90, through: 0, by: -1) {
            let start = today.addingTimeInterval(-Double(day) * 86_400)
            // Lente montée, un grand ménage il y a 50 jours, puis une montée plus rapide (Docker).
            let base = day > 50 ? 250 + Double(90 - day) * 0.4 : 236 + Double(50 - day) * 1.1
            let hours = day <= 1 ? Array(0..<24) : day <= 14 ? [9, 12, 15, 18, 21] : [15]
            for hour in hours {
                let date = start.addingTimeInterval(Double(hour) * 3600)
                guard date <= now else { continue }
                let wobble = Double((day * 7 + hour) % 5) * 0.3
                let slack = hour >= 12 && hour < 18 ? 2_300_000_000 : 1_500_000_000
                points.append(HistoryPoint(date: date, diskUsed: UInt64((base + wobble) * Double(gigabyte)), diskTotal: total,
                                           memoryUsed: UInt64((17 + Double((day + hour) % 6)) * 1_073_741_824), memoryTotal: 32 * 1_073_741_824,
                                           apps: [.init(name: "Slack", memory: UInt64(slack)), .init(name: "Safari", memory: 1_200_000_000),
                                                  .init(name: "Figma", memory: 900_000_000)]))
            }
            if day % 7 == 0 {
                let docker = UInt64((10 + Double(50 - min(day, 50)) * 0.28) * Double(gigabyte))
                let uv = UInt64((4 + Double(90 - day) * 0.06) * Double(gigabyte))
                points.append(HistoryPoint(date: start.addingTimeInterval(20 * 3600), diskUsed: UInt64(base * Double(gigabyte)), diskTotal: total,
                                           storage: [.init(id: "docker", title: L("Disque virtuel de Docker", "Docker virtual disk"), size: docker),
                                                     .init(id: "dotcache", title: L("Caches des outils de dev", "Dev tool caches"), size: uv),
                                                     .init(id: "npm", title: L("Cache npm", "npm cache"), size: 8_700_000_000)]))
            }
        }
        return points.filter { $0.date <= now }.sorted { $0.date < $1.date }
    }

    /// Versions fictives : trois Node avec nvm (20 par défaut, 18 demandée par « old-landing »), deux Python avec
    /// pyenv, une ancienne version Homebrew ; deux paquets npm globaux ; un volume Docker orphelin.
    public static func toolchains() -> (versions: [RuntimeVersion], packages: [GlobalPackage], volumes: [DockerVolume]) {
        let versions = [
            RuntimeVersion(runtime: .node, version: "22.3.0", manager: "nvm", path: home + "/.nvm/versions/node/v22.3.0", size: 212_000_000),
            RuntimeVersion(runtime: .node, version: "20.11.1", manager: "nvm", path: home + "/.nvm/versions/node/v20.11.1", size: 318_000_000, isDefault: true, inUse: true),
            RuntimeVersion(runtime: .node, version: "18.19.0", manager: "nvm", path: home + "/.nvm/versions/node/v18.19.0", size: 186_000_000, usedBy: ["old-landing"]),
            RuntimeVersion(runtime: .node, version: "16.20.2", manager: "nvm", path: home + "/.nvm/versions/node/v16.20.2", size: 164_000_000),
            RuntimeVersion(runtime: .python, version: "3.12.2", manager: "pyenv", path: home + "/.pyenv/versions/3.12.2", size: 248_000_000, isDefault: true),
            RuntimeVersion(runtime: .python, version: "3.10.13", manager: "pyenv", path: home + "/.pyenv/versions/3.10.13", size: 231_000_000),
            RuntimeVersion(runtime: .python, version: "3.13.1", manager: "Homebrew", path: "/opt/homebrew/Cellar/python@3.13/3.13.1", size: 92_000_000,
                           command: "brew cleanup python@3.13"),
            RuntimeVersion(runtime: .python, version: "3.13.4", manager: "Homebrew", path: "/opt/homebrew/Cellar/python@3.13/3.13.4", size: 94_000_000,
                           command: "brew uninstall python@3.13"),
            RuntimeVersion(runtime: .ruby, version: "3.3.0", manager: "rbenv", path: home + "/.rbenv/versions/3.3.0", size: 121_000_000, isDefault: true),
        ]
        let packages = [
            GlobalPackage(name: "@angular/cli", path: home + "/.nvm/versions/node/v20.11.1/lib/node_modules/@angular/cli", size: 168_000_000, owner: "nvm 20.11.1"),
            GlobalPackage(name: "vercel", path: "/opt/homebrew/lib/node_modules/vercel", size: 155_000_000, owner: "Homebrew"),
        ]
        let volumes = [
            DockerVolume(name: "old-shop_postgres-data", size: 1_300_000_000, project: "old-shop"),
            DockerVolume(name: "b412739a1502959c01a4102551662a0adb8ca542e5c25f082a8b0e2f3a8ee92b", size: 76_000_000, isAnonymous: true),
        ]
        return (versions, packages, volumes)
    }

    /// Projets endormis fictifs : deux vieux projets, leurs dépendances et leurs compilations.
    public static func dormantProjects(now: Date = Date()) -> [StorageEntry] {
        func project(_ name: String, months: Double, modules: UInt64, builds: [(String, String, UInt64)], git: UInt64) -> StorageEntry {
            let path = home + "/code/" + name
            var children = [StorageEntry(id: "dormant-part:" + path + "/node_modules", title: L("Dépendances (node_modules)", "Dependencies (node_modules)"),
                                         explanation: L("", ""), kind: .project, path: path + "/node_modules", size: modules)]
            for (folder, title, size) in builds {
                children.append(StorageEntry(id: "dormant-part:" + path + "/" + folder, title: L(title, title),
                                             explanation: L("Se recrée à la prochaine compilation.", "Rebuilt on the next build."),
                                             kind: .project, path: path + "/" + folder, size: size))
            }
            return DormantProjects.entry(project: path, activity: now.addingTimeInterval(-months * 30 * 86_400), children: children,
                                         gitSize: git, now: now)
        }
        return [
            project("old-landing", months: 9, modules: 1_400_000_000, builds: [(".next", "Next.js", 610_000_000)], git: 48_000_000),
            project("hackathon-2025", months: 14, modules: 1_100_000_000, builds: [("dist", "dist", 35_000_000)], git: 12_000_000),
        ].sorted { $0.size > $1.size }
    }

    /// Ports fictifs : ceux des processus de dev (le serveur Python oublié écoute sur tout le réseau, comme
    /// `http.server` par défaut), les conteneurs publiés par Docker, et AirPlay sur 5000 et 7000.
    public static func ports(groups: [ProcessGroup], containers: [DockerContainer]) -> [PortEntry] {
        var entries = PortMap.build(groups: groups, containers: containers) { process in
            if process.name == "com.docker.backend" {
                return containers.flatMap(\.ports).map { ListeningSocket(port: $0, address: "127.0.0.1") }
            }
            return process.listeningPorts.map { ListeningSocket(port: $0, address: process.exposedPorts.contains($0) ? "0.0.0.0" : "127.0.0.1") }
        }
        for port in [5000, 7000] {
            entries.append(PortEntry(port: port, addresses: ["::"], pid: 410, processName: "ControlCenter",
                                     groupTitle: Localization.current == .en ? "Control Center" : "Centre de contrôle", category: .system))
        }
        return entries.sorted { ($0.port, $0.pid) < ($1.port, $1.pid) }
    }

    /// Gros fichiers fictifs : vidéos, archives, images disque, un document, avec leur dernière ouverture.
    static func largeFiles(now: Date) -> [StorageEntry] {
        let english = Localization.current == .en
        let files: [(String, UInt64, Double, Double?)] = [
            // (chemin relatif, taille, modifié il y a N jours, ouvert il y a N jours)
            (english ? "Movies/Wedding - full edit.mov" : "Movies/Mariage - montage complet.mov", 18_400_000_000, 420, 400),
            (english ? "Movies/Screen recording 2025-03-14.mov" : "Movies/Enregistrement de l'écran 2025-03-14.mov", 6_200_000_000, 300, nil),
            ("Downloads/Xcode_26.xip", 4_700_000_000, 240, 240),
            (english ? "Desktop/Holidays 2026.mp4" : "Desktop/Vacances 2026.mp4", 3_100_000_000, 60, 12),
            ("Downloads/ubuntu-24.04-desktop-arm64.iso", 2_800_000_000, 380, nil),
            (english ? "Documents/Photos backup.zip" : "Documents/Sauvegarde photos.zip", 2_300_000_000, 700, 690),
            ("Downloads/Figma-Installer.dmg", 410_000_000, 210, 210),
            (english ? "Documents/Thesis - final.pdf" : "Documents/Mémoire - version finale.pdf", 240_000_000, 25, 3),
            (english ? "Desktop/Poster print.psd" : "Desktop/Affiche impression.psd", 180_000_000, 90, 40),
            ("Documents/model-7b-q4.gguf", 4_100_000_000, 150, 150),
        ]
        return StorageScanner.largeFileEntries(files.map { relative, size, modifiedDays, _ in
            DiskUsage.LargeFile(path: home + "/" + relative, size: size, modified: now.addingTimeInterval(-modifiedDays * 86_400))
        }, details: false).map { entry in
            var entry = entry
            if let file = files.first(where: { home + "/" + $0.0 == entry.path }), let opened = file.3 {
                entry.lastUsed = now.addingTimeInterval(-opened * 86_400)
            }
            entry.inICloud = entry.path.contains("/Documents/") || entry.path.contains("/Desktop/")
            return entry
        }
    }

    /// Doublons fictifs : une vidéo copiée sur le Bureau, des photos téléchargées deux fois, un PDF en trois exemplaires.
    public static func duplicates(now: Date = Date()) -> [DuplicateGroup] {
        let english = Localization.current == .en
        func group(_ id: String, _ size: UInt64, _ copies: [(String, Double)], clone: Int? = nil) -> DuplicateGroup {
            let files = copies.enumerated().map { index, copy in
                DuplicateGroup.File(path: home + "/" + copy.0, modified: now.addingTimeInterval(-copy.1 * 86_400),
                                    freed: index == clone ? size / 200 : size)
            }
            return DuplicateGroup(id: id, size: size, files: DuplicateFinder.orderedForKeeping(files))
        }
        return [
            group("demo-1", 3_100_000_000, [(english ? "Desktop/Holidays 2026.mp4" : "Desktop/Vacances 2026.mp4", 60),
                                            (english ? "Movies/Holidays 2026.mp4" : "Movies/Vacances 2026.mp4", 58)]),
            group("demo-2", 1_200_000_000, [(english ? "Documents/Photos backup.zip" : "Documents/Sauvegarde photos.zip", 700),
                                            (english ? "Downloads/Photos backup (1).zip" : "Downloads/Sauvegarde photos (1).zip", 20)]),
            group("demo-3", 240_000_000, [(english ? "Documents/Thesis - final.pdf" : "Documents/Mémoire - version finale.pdf", 25),
                                          (english ? "Desktop/Thesis - final copy.pdf" : "Desktop/Mémoire - version finale copie.pdf", 24),
                                          (english ? "Downloads/Thesis - final.pdf" : "Downloads/Mémoire - version finale.pdf", 22)]),
            group("demo-4", 38_000_000, [("Pictures/IMG_4821.HEIC", 400), ("Downloads/IMG_4821.HEIC", 30), ("Desktop/IMG_4821 (1).HEIC", 29)]),
            group("demo-5", 12_000_000, [(english ? "Documents/Lease.pdf" : "Documents/Bail.pdf", 500),
                                         (english ? "Documents/Lease copy.pdf" : "Documents/Bail copie.pdf", 480)], clone: 1),
        ]
    }

    /// Analyse de référence fictive, trois jours plus tôt : les caches des outils de dev ont pris 6 Go (surtout uv),
    /// Docker 8 Go, et « mon-site » n'existait pas. Sert à montrer « ce qui a grossi ».
    public static func storagePrevious(now: Date = Date()) -> StorageReport {
        var report = storage(now: now)
        let gigabyte: UInt64 = 1_000_000_000
        report.date = now.addingTimeInterval(-3 * 86_400)
        report.entries = report.entries.compactMap { entry in
            var entry = entry
            switch entry.id {
            case "dotcache":
                entry.size -= 6 * gigabyte
                entry.children = entry.children.map { child in
                    var child = child
                    if child.title.fr == "uv" { child.size -= 6 * gigabyte }
                    return child
                }
            case "application:/Applications/Docker.app":
                entry.size -= 8 * gigabyte
                entry.children = entry.children.map { child in
                    var child = child
                    if child.id == "footprint:docker" { child.size -= 8 * gigabyte }
                    return child
                }
            case _ where entry.kind == .project && entry.modified.map({ now.timeIntervalSince($0) < 30 * 86_400 }) == true:
                return nil
            default:
                break
            }
            return entry
        }
        return report
    }
}

extension DemoData {
    /// Explorateur fictif : le dossier personnel et sa bibliothèque.
    public static func explorer(_ path: String) -> FolderListing? {
        let gigabyte: UInt64 = 1_000_000_000
        func listing(_ path: String, _ items: [(String, Double, Bool)], other: UInt64) -> FolderListing {
            let entries = items.map { FolderListing.Item(name: $0.0, path: path + "/" + $0.0, size: UInt64($0.1 * Double(gigabyte)), isDirectory: $0.2) }
            return FolderListing(path: path, size: entries.reduce(other) { $0 + $1.size }, items: entries, other: other)
        }
        switch path {
        case home:
            return listing(home, [("Library", 96, true), ("Desktop", 41, true), ("code", 23, true), ("Movies", 18, true), (".cache", 14, true),
                                  (".npm", 8.7, true), ("Downloads", 6.8, true), ("Documents", 4.1, true), (".rustup", 2.9, true),
                                  ("Pictures", 2.3, true), (".local", 1.6, true), ("Music", 0.9, true), (".docker", 0.6, true),
                                  ("go", 0.4, true), (".vscode", 0.3, true), (".config", 0.2, true), ("Public", 0.01, true)],
                           other: 120_000_000)
        case home + "/Library":
            return listing(path, [("Containers", 31, true), ("Application Support", 24, true), ("Caches", 11, true), ("Developer", 9.8, true),
                                  ("pnpm", 7.4, true), ("Group Containers", 5.1, true), ("Mail", 3.2, true), ("Logs", 0.8, true)],
                           other: 3_700_000_000)
        default:
            return nil
        }
    }
}

extension DemoData {
    /// Vitesse et batterie fictives : mémoire un peu juste, batterie à 78 % en bonne santé, Zoom qui empêche la veille.
    public static func performance() -> PerformanceStatus {
        PerformanceStatus(
            memory: MemoryStatus(pressure: .warning, swapUsed: 3_600_000_000),
            battery: BatteryStatus(percent: 78, charging: false, onPower: false, minutesRemaining: 252, health: 91, cycles: 414),
            thermal: .normal,
            blockers: [
                SleepBlocker(pid: 4100, name: "zoom.us", seconds: 3_840, kind: "PreventUserIdleDisplaySleep", reason: "Réunion en cours",
                             isSystem: false, keepsDisplayOn: true),
                SleepBlocker(pid: 380, name: "coreaudiod", seconds: 600, kind: "PreventUserIdleSystemSleep", reason: "Audio",
                             isSystem: true, keepsDisplayOn: false),
            ])
    }

    /// Puissance moyenne (watts) des groupes du Mac fictif.
    public static func energyRates() -> [String: Double] {
        var rates: [String: Double] = [:]
        for group in snapshot().groups where group.category != .system {
            rates[group.id] = group.cpuPercent / 8 + Double(group.memory) / 2_000_000_000
        }
        return rates
    }

    /// L'app qui s'emballe dans la démo : Figma, depuis 12 minutes.
    public static func busiest() -> BusyApp? {
        guard let figma = snapshot().groups.first(where: { $0.title == "Figma" }) else { return nil }
        return BusyApp(id: figma.id, name: figma.title, averageCPU: 86, minutes: 12)
    }
}

extension DemoData {
    /// Ce qui démarre avec le Mac fictif.
    public static func startupItems() -> [StartupItem] {
        [
            StartupItem(label: "com.example.sauvegarde", scope: .user, plistPath: home + "/Library/LaunchAgents/com.example.sauvegarde.plist",
                        program: home + "/.local/bin/sauvegarde.sh", ownerName: nil, ownerPath: nil, kind: .script, pid: 812, isEnabled: true),
            StartupItem(label: "com.google.keystone.agent", scope: .user, plistPath: home + "/Library/LaunchAgents/com.google.keystone.agent.plist",
                        program: nil, ownerName: "Google Chrome", ownerPath: "/Applications/Google Chrome.app", kind: .updater, pid: nil, isEnabled: true),
            StartupItem(label: "com.spotify.client.startuphelper", scope: .appHelper, plistPath: nil, program: nil, ownerName: "Spotify",
                        ownerPath: "/Applications/Spotify.app", kind: .helper, pid: 903, isEnabled: true),
            StartupItem(label: "com.docker.vmnetd", scope: .system, plistPath: "/Library/LaunchDaemons/com.docker.vmnetd.plist", program: nil,
                        ownerName: "Docker", ownerPath: "/Applications/Docker.app", kind: .service, pid: nil, isEnabled: true),
            StartupItem(label: "com.docker.helper", scope: .appHelper, plistPath: nil, program: nil,
                        ownerName: "Docker", ownerPath: "/Applications/Docker.app", kind: .helper, pid: 1204, isEnabled: true),
            StartupItem(label: "com.docker.socket", scope: .system, plistPath: "/Library/LaunchDaemons/com.docker.socket.plist", program: nil,
                        ownerName: "Docker", ownerPath: "/Applications/Docker.app", kind: .service, pid: nil, isEnabled: false),
        ]
    }
}
