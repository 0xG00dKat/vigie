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
                 cwd: String? = nil, args: [String] = [], ports: [Int] = []) -> Int32 {
            let id = pid ?? { nextPID += 1; return nextPID }()
            processes.append(RawProcess(
                pid: id, ppid: ppid, uid: uid, name: name, path: path, startTime: ago(hours),
                memory: UInt64(mb * 1_048_576), cpuPercent: cpu, responsiblePID: responsible
            ))
            if cwd != nil || !args.isEmpty || !ports.isEmpty {
                details[id] = ProcessDetails(cwd: cwd, arguments: args, listeningPorts: ports)
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
            args: ["python3", "-m", "http.server", "8080"], ports: [8080])

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
