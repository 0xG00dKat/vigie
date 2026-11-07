import Foundation
import XCTest
@testable import VigieCore

/// Les tests historiques vérifient des textes français : ils fixent la langue avant chaque test.
class FrenchTestCase: XCTestCase {
    override func setUp() {
        super.setUp()
        Localization.current = .fr
    }
}

final class PathRulesTests: FrenchTestCase {
    func testBundleCandidatesGoFromOuterToInner() {
        let path = "/Applications/Opera.app/Contents/Frameworks/Opera Framework.framework/Helpers/Opera Helper.app/Contents/MacOS/Opera Helper"
        XCTAssertEqual(PathRules.bundleCandidates(path), [
            "/Applications/Opera.app",
            "/Applications/Opera.app/Contents/Frameworks/Opera Framework.framework/Helpers/Opera Helper.app",
        ])
        XCTAssertEqual(PathRules.bundleCandidates("/opt/homebrew/bin/node"), [])
    }

    func testProjectDirectories() {
        let home = "/Users/test"
        XCTAssertTrue(PathRules.isProjectDirectory("/Users/test/Desktop/blog", home: home))
        XCTAssertFalse(PathRules.isProjectDirectory("/Users/test", home: home))
        XCTAssertFalse(PathRules.isProjectDirectory("/", home: home))
        XCTAssertFalse(PathRules.isProjectDirectory("/Users/test/Library/Application Support/Claude", home: home))
        XCTAssertFalse(PathRules.isProjectDirectory("/Applications/Cursor.app/Contents/Resources", home: home))
    }

    func testDisplayNameUsesLaunchNameForVersionedBinaries() {
        let name = PathRules.devDisplayName(
            path: "/Users/test/.local/share/claude/versions/2.1.319",
            fallback: "2.1.319",
            arguments: ["claude", "--resume"]
        )
        XCTAssertEqual(name, "claude")
    }

    func testCleanNameRemovesDirectionMarks() {
        XCTAssertEqual(PathRules.cleanName("\u{200E}WhatsApp"), "WhatsApp")
    }
}

final class GroupBuilderTests: FrenchTestCase {
    let me: UInt32 = 501
    let home = "/Users/test"

    private func builder(apps: [RunningApp], details: [Int32: ProcessDetails] = [:], myPID: Int32 = 9999) -> GroupBuilder {
        GroupBuilder(
            runningApps: apps,
            myUID: me,
            myPID: myPID,
            homeDirectory: home,
            protectedBundleIDs: ["com.apple.finder"],
            details: { details[$0.pid] ?? .empty }
        )
    }

    func testBrowserHelpersAreGroupedUnderTheirApp() {
        let apps = [
            RunningApp(pid: 100, bundlePath: "/Applications/Opera.app", bundleID: "com.operasoftware.Opera", name: "Opera", policy: .regular),
            // Les helpers Chromium sont enregistrés comme apps de barre des menus.
            RunningApp(pid: 101, bundlePath: "/Applications/Opera.app/Contents/Helpers/Opera Helper.app", bundleID: "com.operasoftware.Opera.helper", name: "Opera Helper", policy: .accessory),
        ]
        let processes = [
            RawProcess(pid: 100, ppid: 1, uid: me, name: "Opera", path: "/Applications/Opera.app/Contents/MacOS/Opera", memory: 1_000),
            RawProcess(pid: 101, ppid: 100, uid: me, name: "Opera Helper", path: "/Applications/Opera.app/Contents/Helpers/Opera Helper.app/Contents/MacOS/Opera Helper", memory: 500),
            RawProcess(pid: 102, ppid: 100, uid: me, name: "Opera Helper (Renderer)", path: "/Applications/Opera.app/Contents/Helpers/Opera Helper (Renderer).app/Contents/MacOS/Opera Helper (Renderer)", memory: 200),
        ]
        let groups = builder(apps: apps).build(processes)
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].title, "Opera")
        XCTAssertEqual(groups[0].category, .apps)
        XCTAssertEqual(groups[0].processes.count, 3)
        XCTAssertEqual(groups[0].memory, 1_700)
        XCTAssertEqual(groups[0].close, .quitApps([100]))
    }

    func testAppRunningFromTemporaryCloneStaysWithItsApp() {
        let apps = [RunningApp(pid: 100, bundlePath: "/Applications/Opera.app", bundleID: "com.operasoftware.Opera", name: "Opera", policy: .regular)]
        let processes = [
            RawProcess(pid: 100, ppid: 1, uid: me, name: "Opera", path: "/private/var/folders/x/X/code_sign_clone/Opera.app.bundle/Contents/MacOS/Opera"),
        ]
        let groups = builder(apps: apps).build(processes)
        XCTAssertEqual(groups.map(\.category), [.apps])
        XCTAssertEqual(groups.first?.title, "Opera")
    }

    func testDevProcessesGroupByProjectWithLauncherAndPorts() {
        let apps = [RunningApp(pid: 10, bundlePath: "/System/Applications/Utilities/Terminal.app", bundleID: "com.apple.Terminal", name: "Terminal", policy: .regular)]
        let processes = [
            RawProcess(pid: 10, ppid: 1, uid: me, name: "Terminal", path: "/System/Applications/Utilities/Terminal.app/Contents/MacOS/Terminal"),
            RawProcess(pid: 11, ppid: 10, uid: me, name: "zsh", path: "/bin/zsh"),
            RawProcess(pid: 12, ppid: 11, uid: me, name: "node", path: "/opt/homebrew/bin/node"),
            RawProcess(pid: 13, ppid: 12, uid: me, name: "esbuild", path: "/Users/test/blog/node_modules/esbuild/bin/esbuild"),
        ]
        let details: [Int32: ProcessDetails] = [
            12: ProcessDetails(cwd: "/Users/test/blog", arguments: ["node", "astro.mjs", "dev"], listeningPorts: [4321]),
            13: ProcessDetails(cwd: "/Users/test/blog", arguments: ["esbuild", "--service"]),
        ]
        let groups = builder(apps: apps, details: details).build(processes)
        let blog = groups.first { $0.category == .dev }
        XCTAssertEqual(blog?.title, "blog")
        XCTAssertEqual(blog?.location, "~/blog")
        XCTAssertEqual(blog?.ports, [4321])
        XCTAssertEqual(blog?.launchedBy, "Terminal")
        XCTAssertEqual(Set(blog?.processes.map(\.pid) ?? []), [12, 13])
        XCTAssertTrue(blog?.explanation.text.contains("Astro") ?? false)

        // Le shell reste rattaché au Terminal.
        let terminal = groups.first { $0.title == "Terminal" }
        XCTAssertEqual(Set(terminal?.processes.map(\.pid) ?? []), [10, 11])
    }

    func testMCPServerWithoutProjectFollowsItsSession() {
        let processes = [
            RawProcess(pid: 20, ppid: 1, uid: me, name: "claude", path: "/Users/test/.local/share/claude/versions/2.1.0"),
            RawProcess(pid: 21, ppid: 20, uid: me, name: "node", path: "/opt/homebrew/bin/node"),
        ]
        let details: [Int32: ProcessDetails] = [
            20: ProcessDetails(cwd: "/Users/test/site", arguments: ["claude"]),
            21: ProcessDetails(cwd: "/", arguments: ["node", "server.mjs", "mcp"]),
        ]
        let groups = builder(apps: [], details: details).build(processes)
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].title, "site")
        XCTAssertTrue(groups[0].isOrphan)
        XCTAssertEqual(groups[0].close, .signal([20, 21]))
    }

    func testSystemAndOtherUsersAreNeverClosable() {
        let processes = [
            RawProcess(pid: 30, ppid: 1, uid: 0, name: "mds", path: "/System/Library/Frameworks/CoreServices.framework/mds"),
            RawProcess(pid: 31, ppid: 1, uid: me, name: "cfprefsd", path: "/usr/sbin/cfprefsd"),
        ]
        let groups = builder(apps: []).build(processes)
        XCTAssertEqual(groups.count, 2)
        for group in groups {
            XCTAssertEqual(group.category, .system)
            XCTAssertFalse(group.close.isAllowed)
            XCTAssertTrue(group.isProtected)
        }
        XCTAssertEqual(groups.first { $0.title == "mds" }?.explanation.isGeneric, false)
    }

    func testFinderAndVigieAreProtected() {
        let apps = [
            RunningApp(pid: 40, bundlePath: "/System/Library/CoreServices/Finder.app", bundleID: "com.apple.finder", name: "Finder", policy: .regular),
            RunningApp(pid: 41, bundlePath: "/Users/test/Applications/Vigie.app", bundleID: "io.github.0xg00dkat.vigie", name: "Vigie", policy: .accessory),
        ]
        let processes = [
            RawProcess(pid: 40, ppid: 1, uid: me, name: "Finder", path: "/System/Library/CoreServices/Finder.app/Contents/MacOS/Finder"),
            RawProcess(pid: 41, ppid: 1, uid: me, name: "Vigie", path: "/Users/test/Applications/Vigie.app/Contents/MacOS/Vigie"),
        ]
        let groups = builder(apps: apps, myPID: 41).build(processes)
        XCTAssertEqual(groups.count, 2)
        for group in groups {
            XCTAssertTrue(group.isProtected, group.title)
            XCTAssertFalse(group.close.isAllowed, group.title)
        }
    }
}

final class ExplainerTests: FrenchTestCase {
    func testDevDescriptions() {
        func describe(_ name: String, _ arguments: [String], ports: [Int] = []) -> String {
            Explainer.describeDevProcess(RawProcess(pid: 1, ppid: 0, uid: 0, name: name, path: "", arguments: arguments, listeningPorts: ports)).text
        }
        XCTAssertTrue(describe("node", ["node", "vite.js", "--port", "4200"]).contains("Vite"))
        XCTAssertTrue(describe("node", ["node", "rea.mjs", "mcp"]).contains("MCP"))
        XCTAssertTrue(describe("railway", ["railway", "mcp"]).contains("MCP"))
        // --mcp-config est une option de Claude Code, pas un serveur MCP.
        XCTAssertTrue(describe("claude", ["claude", "--mcp-config", "x.json", "--output-format", "stream-json"]).contains("Claude Code"))
        XCTAssertTrue(describe("python3", ["python3", "-m", "http.server", "8000"]).contains("serveur web"))
        XCTAssertTrue(describe("node", ["node", "server.js"], ports: [4321]).contains("Serveur"))
    }

    func testSecretsAreMasked() {
        let masked = Explainer.maskSecrets([
            "index.js", "--api-key", "crsr_FAUX0000000000000000", "--token=abc", "API_SECRET=xyz",
            "sk-FAUX-00000000000000", "--port", "4321",
        ])
        XCTAssertEqual(masked, ["index.js", "--api-key", "••••", "--token=••••", "API_SECRET=••••", "••••", "--port", "4321"])
    }
}

final class FormatTests: FrenchTestCase {
    func testBytes() {
        XCTAssertEqual(Format.bytes(683 * 1_048_576), "683 Mo")
        XCTAssertEqual(Format.bytes(UInt64(5.9 * 1_073_741_824)), "5,9 Go")
        XCTAssertEqual(Format.bytes(UInt64(48 * 1_073_741_824)), "48 Go")
    }

    func testUptime() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertEqual(Format.uptime(since: now.addingTimeInterval(-90), now: now), "depuis 1 min")
        XCTAssertEqual(Format.uptime(since: now.addingTimeInterval(-(3 * 3600 + 5 * 60)), now: now), "depuis 3 h 05")
        XCTAssertEqual(Format.uptime(since: now.addingTimeInterval(-(2 * 86_400 + 23 * 3600)), now: now), "depuis 2 j 23 h")
    }
}

final class LiveSystemTests: FrenchTestCase {
    func testSamplerSeesThisProcess() {
        let sampler = ProcessSampler()
        let processes = sampler.snapshot()
        XCTAssertGreaterThan(processes.count, 50)
        let me = processes.first { $0.pid == getpid() }
        XCTAssertNotNil(me)
        XCTAssertNotNil(me?.memory)
        XCTAssertFalse(me?.path.isEmpty ?? true)
        XCTAssertFalse(ProcessSampler.arguments(getpid()).isEmpty)
    }

    func testListeningPortIsDetected() throws {
        let socket = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        XCTAssertGreaterThan(socket, 0)
        defer { close(socket) }
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        address.sin_port = 0
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(socket, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        XCTAssertEqual(bound, 0)
        XCTAssertEqual(Darwin.listen(socket, 1), 0)
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(socket, $0, &length) }
        }
        let port = Int(UInt16(bigEndian: address.sin_port))
        XCTAssertTrue(ProcessSampler.listeningPorts(getpid()).contains(port))
    }

    func testSigtermStopsAChildProcess() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sleep")
        process.arguments = ["30"]
        try process.run()
        let pid = process.processIdentifier
        XCTAssertTrue(ProcessSignals.isAlive(pid))
        XCTAssertEqual(ProcessSignals.send(SIGTERM, to: [pid, 1, getpid()]), [pid])
        process.waitUntilExit()
        XCTAssertEqual(process.terminationReason, .uncaughtSignal)
        XCTAssertFalse(ProcessSignals.isAlive(pid))
    }
}

final class DemoDataTests: FrenchTestCase {
    func testDemoIsGroupedLikeARealMac() {
        let snapshot = DemoData.snapshot()
        func group(_ title: String) -> ProcessGroup? { snapshot.groups.first { $0.title == title } }

        // Les onglets Safari (services WebKit) sont rattachés à Safari.
        XCTAssertEqual(group("Safari")?.category, .apps)
        XCTAssertEqual(group("Safari")?.processes.count, 10)

        let site = group("mon-site")
        XCTAssertEqual(site?.category, .dev)
        XCTAssertEqual(site?.ports, [4321])
        XCTAssertEqual(site?.launchedBy, "Terminal")

        let api = group("api-factures")
        XCTAssertEqual(api?.launchedBy, "Code")
        XCTAssertTrue(api?.explanation.text.contains("Session Claude Code") ?? false)
        XCTAssertTrue(api?.explanation.text.contains("2 serveurs MCP") ?? false)

        XCTAssertEqual(group("prototype")?.isOrphan, true)
        XCTAssertEqual(group("Dropbox")?.category, .background)
        XCTAssertTrue(snapshot.groups.filter { $0.category == .system }.allSatisfy { !$0.close.isAllowed })
        XCTAssertEqual(snapshot.groups.reduce(0) { $0 + $1.processes.count }, snapshot.processCount)
    }
}

final class EnglishTests: XCTestCase {
    override func setUp() {
        super.setUp()
        Localization.current = .en
    }

    override func tearDown() {
        Localization.current = .fr
        super.tearDown()
    }

    func testFormats() {
        XCTAssertEqual(Format.bytes(683 * 1_048_576), "683 MB")
        XCTAssertEqual(Format.bytes(UInt64(5.9 * 1_073_741_824)), "5.9 GB")
        XCTAssertEqual(Format.count(1079), "1,079")
        XCTAssertEqual(Format.cpu(12.4), "12% CPU")
        XCTAssertEqual(Format.processes(1), "1 process")
        XCTAssertEqual(Format.processes(4), "4 processes")
        let now = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertEqual(Format.uptime(since: now.addingTimeInterval(-(3 * 3600 + 5 * 60)), now: now), "up 3h 05m")
        XCTAssertEqual(Format.uptime(since: now.addingTimeInterval(-(2 * 86_400 + 23 * 3600)), now: now), "up 2d 23h")
    }

    func testExplanationsAndCategories() {
        XCTAssertEqual(ProcessCategory.background.title, "Background")
        let vite = Explainer.describeDevProcess(RawProcess(pid: 1, ppid: 0, uid: 0, name: "node", path: "", arguments: ["node", "vite.js"]))
        XCTAssertEqual(vite.text, "Vite dev server (local website or web app).")
        XCTAssertEqual(Explainer.forSystem(name: "WindowServer", path: "", isOtherUser: true).text, "Draws everything on your screen.")
    }

    func testDemoInEnglish() {
        let snapshot = DemoData.snapshot()
        let api = snapshot.groups.first { $0.title == "invoices-api" }
        XCTAssertNotNil(snapshot.groups.first { $0.title == "my-site" })
        XCTAssertEqual(api?.explanation.text, "Python web server · Claude Code session · 2 MCP servers (agent tools).")
    }

    func testClaudeQuestionFollowsLanguage() {
        let group = DemoData.snapshot().groups.first { $0.title == "Safari" }!
        let english = ClaudeExplainer.subject(for: group, language: .en)
        let french = ClaudeExplainer.subject(for: group, language: .fr)
        XCTAssertTrue(english.prompt.hasPrefix("What is the app “Safari”"))
        XCTAssertTrue(english.key.hasPrefix("en|"))
        XCTAssertTrue(french.prompt.hasPrefix("Qu'est-ce que l'application « Safari »"))
        XCTAssertFalse(french.key.hasPrefix("en|"))
    }
}

final class TranslationTests: XCTestCase {
    func testEveryBuiltInTextHasBothLanguagesWithTheRightPunctuation() {
        for text in Explainer.allTranslations {
            XCTAssertFalse(text.fr.isEmpty, text.en)
            XCTAssertFalse(text.en.isEmpty, text.fr)
            // Une traduction oubliée ou copiée garde la typographie de l'autre langue.
            XCTAssertFalse(text.en.contains(" :") || text.en.contains("« ") || text.en.contains(" ;"), "Anglais suspect : \(text.en)")
            XCTAssertFalse(text.fr.contains("“") || text.fr.contains("”"), "Français suspect : \(text.fr)")
        }
    }

    func testSystemLanguageDetection() {
        XCTAssertEqual(Localization.systemLanguage(preferred: ["en-FR", "fr-FR"]), .en)
        XCTAssertEqual(Localization.systemLanguage(preferred: ["fr-FR", "en-US"]), .fr)
        XCTAssertEqual(Localization.systemLanguage(preferred: ["de-DE", "fr-CA"]), .fr)
        XCTAssertEqual(Localization.systemLanguage(preferred: ["de-DE"]), .en)
    }
}

final class DockerTests: FrenchTestCase {
    func testSizes() {
        XCTAssertEqual(DockerReader.parseSize("2.735GB"), 2_735_000_000)
        XCTAssertEqual(DockerReader.parseSize("512kB"), 512_000)
        XCTAssertEqual(DockerReader.parseSize("38.5MiB"), 40_370_176)
        XCTAssertEqual(DockerReader.parseSize("0B"), 0)
        XCTAssertNil(DockerReader.parseSize("beaucoup"))
    }

    func testPorts() {
        XCTAssertEqual(DockerReader.parsePorts("0.0.0.0:5432->5432/tcp, [::]:5432->5432/tcp"), [5432])
        XCTAssertEqual(DockerReader.parsePorts("0.0.0.0:9000-9001->9000-9001/tcp, 6379/tcp"), [9000, 9001])
        XCTAssertEqual(DockerReader.parsePorts(""), [])
    }

    func testContainersStatsAndStartTimes() {
        let ps = """
        {"Command":"\\"docker-entrypoint.s…\\"","ID":"3f2a1b9c8d7e","Image":"postgres:16","Labels":"com.docker.compose.project=shop,com.docker.compose.service=db,com.docker.compose.version=2.29.1","Names":"shop-db-1","Ports":"0.0.0.0:5432->5432/tcp","State":"running","Status":"Up 3 hours"}
        {"ID":"9a8b7c6d5e4f","Image":"minio/minio","Labels":"","Names":"minio","Ports":"0.0.0.0:9000-9001->9000-9001/tcp","State":"running","Status":"Up 2 days"}
        """
        let containers = DockerReader.parseContainers(ps)
        XCTAssertEqual(containers.map(\.name), ["shop-db-1", "minio"])
        XCTAssertEqual(containers[0].project, "shop")
        XCTAssertEqual(containers[0].service, "db")
        XCTAssertNil(containers[1].project)
        XCTAssertEqual(containers[1].ports, [9000, 9001])

        let stats = DockerReader.parseStats("""
        {"CPUPerc":"1.25%","ID":"3f2a1b9c8d7e","MemUsage":"38.5MiB / 7.654GiB","Name":"shop-db-1"}
        """)
        XCTAssertEqual(stats["shop-db-1"]?.cpu, 1.25)
        XCTAssertEqual(stats["shop-db-1"]?.memory, 40_370_176)

        let started = DockerReader.parseStartTimes("/shop-db-1 2026-11-04T09:12:34.123456789Z\n/minio 2026-11-02T08:00:00Z")
        XCTAssertEqual(started["shop-db-1"]?.timeIntervalSince1970 ?? 0, 1_793_783_554.123, accuracy: 0.01)
        XCTAssertNotNil(started["minio"])
    }

    func testDiskUsage() {
        let usage = DockerReader.parseDiskUsage("""
        {"Active":"2","Reclaimable":"1.209GB (44%)","Size":"2.735GB","TotalCount":"5","Type":"Images"}
        {"Active":"2","Reclaimable":"0B (0%)","Size":"12.3MB","TotalCount":"3","Type":"Containers"}
        {"Active":"1","Reclaimable":"420MB (30%)","Size":"1.4GB","TotalCount":"2","Type":"Local Volumes"}
        {"Active":"0","Reclaimable":"8.1GB","Size":"8.1GB","TotalCount":"44","Type":"Build Cache"}
        """)
        XCTAssertEqual(usage?.images.size, 2_735_000_000)
        XCTAssertEqual(usage?.images.reclaimable, 1_209_000_000)
        XCTAssertEqual(usage?.containers.count, 3)
        XCTAssertEqual(usage?.containers.active, 2)
        XCTAssertEqual(usage?.volumes.size, 1_400_000_000)
        XCTAssertEqual(usage?.buildCache.reclaimable, 8_100_000_000)
        XCTAssertNil(DockerReader.parseDiskUsage("Cannot connect to the Docker daemon"))
    }

    func testComposeProjectsAreGrouped() {
        let groups = DemoData.docker().groups
        XCTAssertEqual(groups.count, 2)
        let project = groups.first { $0.project == "api-factures" }
        XCTAssertEqual(project?.containers.count, 2)
        XCTAssertEqual(project?.ports, [5433, 6379])
        XCTAssertEqual(groups.first { $0.project == nil }?.title, "minio")
    }
}

final class DiskTests: XCTestCase {
    func testThresholds() {
        XCTAssertFalse(DemoData.disk().isLow)
        XCTAssertTrue(DemoData.disk(low: true).isLow)
        XCTAssertEqual(DemoData.disk(low: true).freePercent, 11)
    }

    func testAlertFiresOnceUntilSpaceComesBack() {
        let total: UInt64 = 1000
        var state = DiskAlertState()
        XCTAssertFalse(state.update(with: DiskStatus(available: 300, total: total)))
        XCTAssertTrue(state.update(with: DiskStatus(available: 140, total: total)), "passage sous 15 %")
        XCTAssertFalse(state.update(with: DiskStatus(available: 120, total: total)), "pas de répétition")
        XCTAssertFalse(state.update(with: DiskStatus(available: 160, total: total)), "16 % : toujours armé")
        XCTAssertFalse(state.update(with: DiskStatus(available: 140, total: total)))
        XCTAssertFalse(state.update(with: DiskStatus(available: 200, total: total)), "20 % : réarmé")
        XCTAssertTrue(state.update(with: DiskStatus(available: 100, total: total)), "nouveau passage sous 15 %")
    }

    func testReadsTheRealStartupDisk() {
        let disk = DiskReader.read()
        XCTAssertNotNil(disk)
        XCTAssertGreaterThan(disk?.total ?? 0, disk?.available ?? 0)
    }
}

final class NestedAppTests: FrenchTestCase {
    private func build(_ apps: [RunningApp], _ processes: [RawProcess]) -> [ProcessGroup] {
        GroupBuilder(runningApps: apps, myUID: 501, myPID: 9999, homeDirectory: "/Users/test", protectedBundleIDs: []).build(processes)
    }

    func testDockerDesktopWindowAndEngineAreOneApp() {
        let docker = "/Applications/Docker.app"
        let window = docker + "/Contents/MacOS/Docker Desktop.app"
        let apps = [
            RunningApp(pid: 10, bundlePath: docker, bundleID: "com.docker.docker", name: "Docker", policy: .accessory),
            RunningApp(pid: 11, bundlePath: window, bundleID: "com.electron.dockerdesktop", name: "Docker Desktop", policy: .regular),
        ]
        let processes = [
            RawProcess(pid: 10, ppid: 1, uid: 501, name: "Docker", path: docker + "/Contents/MacOS/Docker"),
            RawProcess(pid: 11, ppid: 10, uid: 501, name: "Docker Desktop", path: window + "/Contents/MacOS/Docker Desktop"),
            RawProcess(pid: 12, ppid: 10, uid: 501, name: "com.docker.backend", path: docker + "/Contents/MacOS/com.docker.backend"),
        ]
        let groups = build(apps, processes)
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].title, "Docker Desktop")
        XCTAssertEqual(groups[0].category, .apps)
        XCTAssertEqual(groups[0].processes.count, 3)
        XCTAssertEqual(Set(groups[0].close.pids), [10, 11])
        XCTAssertTrue(groups[0].explanation.text.contains("conteneurs"))
    }

    func testSimulatorStaysSeparateWhenXcodeIsClosed() {
        let simulator = "/Applications/Xcode.app/Contents/Developer/Applications/Simulator.app"
        let apps = [RunningApp(pid: 20, bundlePath: simulator, bundleID: "com.apple.iphonesimulator", name: "Simulator", policy: .regular)]
        let processes = [RawProcess(pid: 20, ppid: 1, uid: 501, name: "Simulator", path: simulator + "/Contents/MacOS/Simulator")]
        let groups = build(apps, processes)
        XCTAssertEqual(groups.map(\.title), ["Simulator"])
        XCTAssertEqual(groups[0].close, .quitApps([20]))
    }
}

final class UpdateTests: FrenchTestCase {
    func testVersions() {
        XCTAssertEqual(Version("v0.2.0")?.description, "0.2.0")
        XCTAssertTrue(Version("0.2.0")! < Version("0.10.0")!, "comparaison numérique, pas alphabétique")
        XCTAssertTrue(Version("0.2")! == Version("0.2.0")!)
        XCTAssertTrue(Version("1.0.0-beta.1")! == Version("1.0.0")!)
        XCTAssertNil(Version("dernière"))
    }

    func testParsesGitHubLatestRelease() throws {
        let json = """
        {"tag_name":"v0.3.0","name":"Vigie 0.3.0","draft":false,"prerelease":false,
         "html_url":"https://github.com/0xG00dKat/vigie/releases/tag/v0.3.0",
         "published_at":"2026-12-01T10:00:00Z",
         "body":"## Nouveautés\\n- **Docker** : arrêt des conteneurs\\n- Alerte `disque`\\n",
         "assets":[{"name":"Vigie-0.3.0.zip","browser_download_url":"https://github.com/0xG00dKat/vigie/releases/download/v0.3.0/Vigie-0.3.0.zip"}]}
        """
        let release = try XCTUnwrap(UpdateChecker.parseLatest(Data(json.utf8)))
        XCTAssertEqual(release.version.description, "0.3.0")
        XCTAssertEqual(release.name, "Vigie 0.3.0")
        XCTAssertEqual(release.downloadURL?.lastPathComponent, "Vigie-0.3.0.zip")
        XCTAssertEqual(release.summary, "Nouveautés · Docker : arrêt des conteneurs · Alerte disque")
        XCTAssertNotNil(release.publishedAt)

        let draft = json.replacingOccurrences(of: "\"draft\":false", with: "\"draft\":true")
        XCTAssertNil(UpdateChecker.parseLatest(Data(draft.utf8)), "un brouillon n'est pas une version publiée")
    }

    func testSummaryFollowsLanguage() {
        let release = ReleaseInfo(
            version: Version("0.2.0")!, tag: "v0.2.0", name: "Vigie 0.2.0",
            notes: "**Français**\n- Vigie parle anglais\n- Section Docker\n\n**English**\n- Vigie speaks English\n- Docker section",
            pageURL: URL(string: "https://example.com")!, downloadURL: nil, publishedAt: nil
        )
        XCTAssertEqual(release.summary(in: .fr), "Vigie parle anglais · Section Docker")
        XCTAssertEqual(release.summary(in: .en), "Vigie speaks English · Docker section")
    }

    func testAutomaticCheckAtMostOncePerDay() {
        let now = Date()
        XCTAssertTrue(UpdateChecker.shouldCheckAutomatically(enabled: true, lastCheck: nil, now: now))
        XCTAssertFalse(UpdateChecker.shouldCheckAutomatically(enabled: true, lastCheck: now.addingTimeInterval(-3600), now: now))
        XCTAssertTrue(UpdateChecker.shouldCheckAutomatically(enabled: true, lastCheck: now.addingTimeInterval(-25 * 3600), now: now))
        XCTAssertFalse(UpdateChecker.shouldCheckAutomatically(enabled: false, lastCheck: nil, now: now))
    }
}
