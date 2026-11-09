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

    /// « Copier les infos » : de quoi signaler un serveur bloqué, sans arguments ni nom d'utilisateur.
    func testCopiedDetailsOfADevServer() throws {
        let now = Date()
        let api = try XCTUnwrap(DemoData.snapshot(now: now).groups.first { $0.title == "invoices-api" })
        let text = GroupReport.text(for: api, in: .fr, now: now)
        let main = try XCTUnwrap(GroupReport.mainProcess(of: api))
        XCTAssertFalse(main.listeningPorts.isEmpty, "le processus cité d'abord est celui qui écoute")
        let lines = text.components(separatedBy: "\n")
        XCTAssertTrue(lines[0].hasPrefix("invoices-api — projet ~/"), lines[0])
        XCTAssertTrue(lines[1].hasPrefix("PID \(main.pid) · port"), lines[1])
        XCTAssertTrue(text.contains("Lancé il y a"), text)
        XCTAssertEqual(lines.last, "Pour l'arrêter : kill \(main.pid)")
        XCTAssertFalse(text.contains(DemoData.home), "chemin abrégé avec ~")
        // Les nombres (un port passé en argument) peuvent figurer légitimement dans le texte.
        for argument in main.arguments.dropFirst() where argument.count > 3 && Int(argument) == nil {
            XCTAssertFalse(text.contains(argument), "pas d'arguments : \(argument)")
        }
        XCTAssertTrue(GroupReport.text(for: api, in: .en, now: now).contains("To stop it: kill \(main.pid)"))
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
         "html_url":"https://github.com/example/vigie/releases/tag/v0.3.0",
         "published_at":"2026-12-01T10:00:00Z",
         "body":"## Nouveautés\\n- **Docker** : arrêt des conteneurs\\n- Alerte `disque`\\n",
         "assets":[{"name":"Vigie-0.3.0.zip","browser_download_url":"https://github.com/example/vigie/releases/download/v0.3.0/Vigie-0.3.0.zip"}]}
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

final class SystemExplanationTests: FrenchTestCase {
    func testServiceNamedAfterItsClientApp() {
        let explanation = Explainer.forSystem(name: "com.apple.SafariPlatformSupport.Helper", path: "/System/Library/x.xpc",
                                              isOtherUser: false, title: "AutoFill (Opera)")
        XCTAssertEqual(explanation.text, "Remplissage automatique des mots de passe et des formulaires. Utilisé par Opera.")
        XCTAssertFalse(explanation.isGeneric)
    }

    func testXPCBundleNameIsRecognized() {
        XCTAssertEqual(PathRules.bundleDisplayName("/System/Library/Frameworks/AppKit.framework/XPCServices/com.apple.appkit.xpc.openAndSavePanelService.xpc"),
                       "com.apple.appkit.xpc.openAndSavePanelService")
    }

    func testFamilies() {
        let subscriber = Explainer.forSystem(name: "ScreenSharingSubscriber",
                                             path: "/System/Library/PrivateFrameworks/RemoteManagement.framework/XPCServices/ScreenSharingSubscriber.xpc/Contents/MacOS/ScreenSharingSubscriber",
                                             isOtherUser: false)
        XCTAssertTrue(subscriber.text.contains("profils de configuration"))

        let widgets = Explainer.forSystem(name: "Weather", path: "/System/Applications/Weather.app", isOtherUser: false, title: "Weather")
        XCTAssertEqual(widgets.text, "Widgets et raccourcis de l'app Weather d'Apple : ils tournent même quand l'app est fermée.")

        // Un service inconnu garde une description générique plutôt qu'un rôle inventé.
        let unknown = Explainer.forSystem(name: "SetStoreUpdateService",
                                          path: "/System/Library/PrivateFrameworks/CascadeSets.framework/Versions/A/XPCServices/SetStoreUpdateService.xpc/Contents/MacOS/SetStoreUpdateService",
                                          isOtherUser: false)
        XCTAssertTrue(unknown.isGeneric)
    }
}

final class StorageTests: FrenchTestCase {
    func testParseDu() {
        let output = "1024\t/Users/test/.cache/uv\n512\t/Users/test/.cache/pip\n2048\t/Users/test/.cache\n"
        let parsed = StorageScanner.parseDu(output, root: "/Users/test/.cache")
        XCTAssertEqual(parsed.total, 2048 * 1024)
        XCTAssertEqual(parsed.children.map(\.name), ["uv", "pip"])
        XCTAssertEqual(parsed.children.first?.size, 1024 * 1024)
    }

    func testCatalogHasNoOverlap() {
        // Un dossier ne doit être compté qu'une fois : aucun emplacement n'est dans un autre.
        let paths = StorageCatalog.locations.map(\.path) + StorageCatalog.appSupport.map { "Library/Application Support/" + $0.folder }
        for path in paths {
            for other in paths where other != path {
                XCTAssertFalse(path.hasPrefix(other + "/"), "\(path) est dans \(other)")
            }
        }
        XCTAssertEqual(Set(StorageCatalog.locations.map(\.id)).count, StorageCatalog.locations.count)
    }

    func testFindsProjectNodeModulesWithoutDescendingIntoThem() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("vigie-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = ["site/node_modules/react/node_modules", "monorepo/apps/web/node_modules", ".hidden/node_modules", "Library/node_modules"]
        for path in paths {
            try FileManager.default.createDirectory(at: root.appendingPathComponent(path), withIntermediateDirectories: true)
        }
        // Le dossier temporaire passe par un raccourci (/var → /private/var) : on compare la fin des chemins.
        let found = StorageScanner.findNodeModules(roots: [root.path])
            .compactMap { $0.components(separatedBy: root.lastPathComponent + "/").last }.sorted()
        XCTAssertEqual(found, ["monorepo/apps/web/node_modules", "site/node_modules"])
    }

    func testMeasuresARealFolder() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("vigie-mesure-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root.appendingPathComponent("a"), withIntermediateDirectories: true)
        try Data(count: 2_000_000).write(to: root.appendingPathComponent("a/fichier"))
        let measure = try XCTUnwrap(StorageScanner.measure(root.path, breakdown: true))
        XCTAssertGreaterThanOrEqual(measure.total, 1_900_000)
        XCTAssertEqual(measure.children.first?.name, "a")
        XCTAssertFalse(measure.denied)
    }

    func testChildExplanationsAndDemo() {
        XCTAssertEqual(StorageCatalog.child("uv", parentKind: .cache).command, "uv cache clean")
        XCTAssertTrue(StorageCatalog.child("pen-updater", parentKind: .cache).explanation.fr.contains("Mises à jour"))
        let report = DemoData.storage()
        XCTAssertEqual(report.entries(of: .project).count, 3)
        XCTAssertTrue(report.entries.contains { $0.isProtected })
        XCTAssertGreaterThan(report.cacheTotal, 30_000_000_000)
    }
}

final class DiskUsageTests: FrenchTestCase {
    /// Le compteur parallèle donne la même taille que `du`, compte une fois les fichiers à plusieurs liens
    /// (comme pnpm) et trouve projets et gros fichiers dans la même passe.
    func testMatchesDuAndFindsProjectsAndLargeFiles() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("vigie-compteur-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        func write(_ relative: String, _ bytes: Int) throws {
            let url = root.appendingPathComponent(relative)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(repeating: 7, count: bytes).write(to: url)
        }
        try write("site/node_modules/react/index.js", 300_000)
        try write("site/node_modules/react/node_modules/inner/a.js", 200_000)
        try write("site/src/app.js", 50_000)
        try write(".hidden/node_modules/x.js", 10_000)
        try write("films/gros.mov", 2_000_000)
        try write(".cache/gros-cache.bin", 2_000_000)
        try write("lien/original.bin", 400_000)
        try FileManager.default.linkItem(at: root.appendingPathComponent("lien/original.bin"),
                                         to: root.appendingPathComponent("site/node_modules/react/lien.bin"))
        for index in 0..<40 { try write("beaucoup/\(index)/f.txt", 5_000) }

        let result = DiskUsage.measure([DiskUsage.Request(path: root.path, breakdown: true, findNodeModules: true,
                                                          largeFileMinimum: 1_000_000)])[0]
        let du = try XCTUnwrap(StorageScanner.measureWithDu(root.path))
        XCTAssertEqual(result.total, du.total, "même taille que du, lien compté une fois")
        XCTAssertEqual(Set(result.children.map(\.name)), ["site", "films", "lien", "beaucoup", ".hidden", ".cache"])
        let modules = result.nodeModules.map { $0.path.components(separatedBy: root.lastPathComponent + "/").last ?? "" }
        XCTAssertEqual(modules, ["site/node_modules"], "ni le node_modules imbriqué, ni celui du dossier caché")
        XCTAssertGreaterThan(result.nodeModules.first?.size ?? 0, 500_000)
        XCTAssertEqual(result.largeFiles.map { PathRules.lastComponent($0.path) }, ["gros.mov"], "pas les fichiers des dossiers cachés")
        XCTAssertFalse(result.denied)
    }

    func testSingleFileAndMissingPath() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("vigie-fichier-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: file) }
        try Data(repeating: 1, count: 100_000).write(to: file)
        let results = DiskUsage.measure([DiskUsage.Request(path: file.path), DiskUsage.Request(path: file.path + "-absent")])
        XCTAssertGreaterThanOrEqual(results[0].total, 100_000)
        XCTAssertTrue(results[0].exists)
        XCTAssertFalse(results[1].exists)
    }
}

final class StorageReportStoreTests: FrenchTestCase {
    func testKeepsTheReportForADay() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("vigie-stockage-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let analyzed = Date(timeIntervalSince1970: 1_800_000_000)
        var report = DemoData.storage(now: analyzed)
        report.date = analyzed
        StorageReportStore.save(report, to: url)
        XCTAssertEqual(StorageReportStore.load(from: url, now: analyzed.addingTimeInterval(3 * 3600)), report)
        XCTAssertNil(StorageReportStore.load(from: url, now: analyzed.addingTimeInterval(25 * 3600)), "plus de 24 h : oubliée")
        XCTAssertNil(StorageReportStore.load(from: url.appendingPathExtension("absent")))
    }

    func testElapsedTime() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertEqual(Format.elapsed(since: now.addingTimeInterval(-20), in: .fr, now: now), "à l'instant")
        XCTAssertEqual(Format.elapsed(since: now.addingTimeInterval(-12 * 60), in: .fr, now: now), "il y a 12 min")
        XCTAssertEqual(Format.elapsed(since: now.addingTimeInterval(-3 * 3600 - 60), in: .fr, now: now), "il y a 3 h")
        XCTAssertEqual(Format.elapsed(since: now.addingTimeInterval(-3 * 3600), in: .en, now: now), "3 h ago")
    }
}

final class DiskDiagnosisTests: FrenchTestCase {
    /// L'alerte dit ce qui a grossi (et pourquoi : le sous-dossier responsable) et quoi vider en priorité.
    func testSaysWhatGrewAndWhatToClear() {
        let now = Date()
        let diagnosis = DiskDiagnosis.make(report: DemoData.storage(now: now), previous: DemoData.storagePrevious(now: now))
        XCTAssertEqual(diagnosis.growth.map(\.title.fr), ["Docker", "Caches des outils de dev", "mon-site"])
        XCTAssertEqual(diagnosis.growth[0].increase, 8_000_000_000)
        XCTAssertEqual(diagnosis.growth[1].mainly?.fr, "uv")
        XCTAssertTrue(diagnosis.growth[2].isNew)
        XCTAssertEqual(diagnosis.growthLine(in: .fr, now: now),
                       "A grossi depuis 3 jours : Docker +8,0 Go (surtout Disque virtuel de Docker), Caches des outils de dev +6,0 Go (surtout uv), mon-site +1,9 Go (nouveau).")
        XCTAssertEqual(diagnosis.reclaimableLine(in: .fr),
                       "À vider en priorité : Caches des outils de dev 14 Go, Caches des apps 11 Go, Cache npm 8,7 Go.")
        XCTAssertTrue(diagnosis.growthLine(in: .en, now: now)?.hasPrefix("Grew in the last 3 days: Docker +8.0 GB") == true)
    }

    func testWithoutReferenceOnlySaysWhatToClear() {
        let diagnosis = DiskDiagnosis.make(report: DemoData.storage(), previous: nil)
        XCTAssertNil(diagnosis.growthLine())
        XCTAssertNotNil(diagnosis.reclaimableLine())
    }

    /// La référence : l'analyse d'avant tout de suite s'il n'y en a pas, puis seulement une de 6 h de plus.
    func testReferenceRotation() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("vigie-reference-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("stockage.json")
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        func report(hours: Double) -> StorageReport {
            var report = DemoData.storage(now: start)
            report.date = start.addingTimeInterval(hours * 3600)
            return report
        }
        XCTAssertNil(StorageReportStore.save(report(hours: 0), to: url))
        XCTAssertEqual(StorageReportStore.save(report(hours: 1), to: url)?.date, report(hours: 0).date, "première référence")
        XCTAssertEqual(StorageReportStore.save(report(hours: 3), to: url)?.date, report(hours: 0).date, "moins de 6 h : référence gardée")
        XCTAssertEqual(StorageReportStore.save(report(hours: 10), to: url)?.date, report(hours: 3).date, "6 h de plus : l'analyse d'avant devient la référence")
        XCTAssertEqual(StorageReportStore.loadPrevious(for: url)?.date, report(hours: 3).date)
    }
}

final class StorageCleanerTests: FrenchTestCase {
    let home = "/Users/test"

    func entry(_ id: String, _ path: String, _ kind: StorageKind, command: String? = nil, size: UInt64 = 1_000, isProtected: Bool = false) -> StorageEntry {
        StorageEntry(id: id, title: L(id, id), explanation: L("", ""), kind: kind, path: path, size: size, command: command, isProtected: isProtected)
    }

    /// Ce que Vigie a le droit de nettoyer, et comment.
    func testWhatCanBeCleaned() {
        XCTAssertEqual(StorageCleaner.cleanup(for: entry("npm", home + "/.npm", .cache, command: "npm cache clean --force"), home: home),
                       .command("npm cache clean --force"))
        XCTAssertEqual(StorageCleaner.cleanup(for: entry("docker", home + "/Library/Containers/x/Docker.raw", .appData, command: "docker system prune"), home: home),
                       .command("docker system prune -f"), "version sans question")
        XCTAssertEqual(StorageCleaner.cleanup(for: entry("derived-data", home + "/Library/Developer/Xcode/DerivedData", .cache), home: home), .delete)
        XCTAssertEqual(StorageCleaner.cleanup(for: entry("caches/Google", home + "/Library/Caches/Google", .cache), home: home), .delete)
        XCTAssertEqual(StorageCleaner.cleanup(for: entry("project:x", home + "/code/x/node_modules", .project), home: home), .trash)
        XCTAssertEqual(StorageCleaner.cleanup(for: entry("footprint:" + home + "/Library/Caches/com.app", home + "/Library/Caches/com.app", .appData), home: home), .delete)
        // Jamais :
        XCTAssertNil(StorageCleaner.cleanup(for: entry("caches", home + "/Library/Caches", .cache), home: home), "pas tout ~/Library/Caches d'un bloc")
        XCTAssertNil(StorageCleaner.cleanup(for: entry("dotcache", home + "/.cache", .cache), home: home))
        XCTAssertNil(StorageCleaner.cleanup(for: entry("rustup", home + "/.rustup", .appData, command: "rustup toolchain list"), home: home), "une commande qui liste ne nettoie pas")
        XCTAssertNil(StorageCleaner.cleanup(for: entry("footprint:" + home + "/Library/Application Support/X", home + "/Library/Application Support/X", .appData), home: home))
        XCTAssertNil(StorageCleaner.cleanup(for: entry("desktop", home + "/Desktop", .personal), home: home))
        XCTAssertNil(StorageCleaner.cleanup(for: entry("application:/Applications/X.app", "/Applications/X.app", .application), home: home))
        // Un gros fichier : à la corbeille seulement, jamais supprimé pour de bon.
        XCTAssertEqual(StorageCleaner.cleanup(for: entry("file:x", home + "/Downloads/x.dmg", .largeFile), home: home), .trash)
        XCTAssertNil(StorageCleaner.cleanup(for: entry("caches/Y", home + "/Library/Caches/Y", .cache, isProtected: true), home: home))
        XCTAssertNil(StorageCleaner.cleanup(for: entry("caches/Z", "/Library/Caches/Z", .cache), home: home), "hors du dossier personnel")
        XCTAssertNil(StorageCleaner.cleanup(for: entry("caches/W", home + "/Library/Caches/../../Documents", .cache), home: home))
    }

    /// Le même dossier, à deux endroits, et les lignes qui le contiennent : tout est corrigé.
    func testReportAfterCleaning() {
        let cache = home + "/Library/Caches/com.operasoftware.Opera"
        var caches = entry("caches", home + "/Library/Caches", .cache, size: 10_000)
        caches.children = [entry("caches/opera", cache, .cache, size: 4_000)]
        var opera = entry("application:/Applications/Opera.app", "/Applications/Opera.app", .application, size: 9_000)
        opera.children = [entry("footprint:" + cache, cache, .appData, size: 4_000)]
        let report = StorageReport(entries: [caches, opera], localSnapshots: 0)
        let cleaned = report.afterCleaning(path: cache, freed: 4_000, removed: true)
        XCTAssertEqual(cleaned.entries.map(\.size), [6_000, 5_000])
        XCTAssertTrue(cleaned.entries.allSatisfy { $0.children.isEmpty })

        let projects = StorageReport(entries: [entry("desktop", home + "/Desktop", .personal, size: 10_000),
                                               entry("project:x", home + "/Desktop/x/node_modules", .project, size: 3_000)], localSnapshots: 0)
        let afterTrash = projects.afterCleaning(path: home + "/Desktop/x/node_modules", freed: 3_000, removed: true)
        XCTAssertEqual(afterTrash.entries.map(\.id), ["desktop"])
        XCTAssertEqual(afterTrash.entries[0].size, 7_000, "le Bureau qui le contenait maigrit aussi")
    }

    /// Corbeille, journaux, vieux installeurs : la bonne action pour chacun.
    func testTrashLogsAndInstallers() {
        XCTAssertEqual(StorageCleaner.cleanup(for: entry("trash", home + "/.Trash", .personal, isProtected: true), home: home), .emptyTrash,
                       "protégée, mais le Finder sait la vider")
        XCTAssertNil(StorageCleaner.cleanup(for: entry("logs", home + "/Library/Logs", .cache), home: home), "pas tout le dossier d'un bloc")
        XCTAssertEqual(StorageCleaner.cleanup(for: entry("logs/DiagnosticReports", home + "/Library/Logs/DiagnosticReports", .cache), home: home), .delete)
        var installers = entry("installers", home + "/Downloads", .personal)
        installers.children = [entry("installer:a", home + "/Downloads/Zoom.pkg", .personal), entry("installer:b", home + "/Downloads/vieux/Figma.dmg", .personal)]
        XCTAssertEqual(StorageCleaner.cleanup(for: installers, home: home), .trashAll([home + "/Downloads/Zoom.pkg", home + "/Downloads/vieux/Figma.dmg"]))
        XCTAssertEqual(StorageCleaner.cleanup(for: installers.children[0], home: home), .trash)
        XCTAssertNil(StorageCleaner.cleanup(for: entry("downloads", home + "/Downloads", .personal), home: home), "jamais tout Téléchargements")
    }

    /// Seuls les installeurs de plus d'un mois, dans Téléchargements et ses sous-dossiers directs.
    func testFindsOldInstallers() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("vigie-installeurs-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: home) }
        let downloads = home.appendingPathComponent("Downloads")
        try FileManager.default.createDirectory(at: downloads.appendingPathComponent("logiciels"), withIntermediateDirectories: true)
        let old = Date().addingTimeInterval(-60 * 86_400)
        for (name, date) in [("Zoom.pkg", old), ("logiciels/Figma.dmg", old), ("Récent.dmg", Date()), ("photo.jpg", old)] {
            let url = downloads.appendingPathComponent(name)
            try Data(repeating: 1, count: 300_000).write(to: url)
            try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
        }
        let files = OldInstallers.find(home: home.path)
        XCTAssertEqual(Set(files.map { ($0.path as NSString).lastPathComponent }), ["Zoom.pkg", "Figma.dmg"])
        let entry = try XCTUnwrap(OldInstallers.entry(files, home: home.path, minimumSize: 0))
        XCTAssertEqual(entry.children.count, 2)
        XCTAssertTrue(entry.explanation.fr.hasPrefix("2 fichiers"))
    }

    func testDeletesAFolderAndReportsTheFreedSpace() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("vigie-nettoyage-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("sous"), withIntermediateDirectories: true)
        try Data(repeating: 3, count: 2_000_000).write(to: folder.appendingPathComponent("sous/cache.bin"))
        let result = StorageCleaner.run(.delete, path: folder.path)
        XCTAssertGreaterThanOrEqual(try result.get(), 2_000_000)
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.path))
    }

    func testReportsAFailingCommand() {
        XCTAssertNil(StorageCleaner.runCommand("true"))
        XCTAssertNotNil(StorageCleaner.runCommand("echo 'cache introuvable' >&2; exit 3"))
        XCTAssertEqual(StorageCleaner.runCommand("echo 'cache introuvable' >&2; exit 3"), "cache introuvable")
    }
}

final class AppRemovalTests: FrenchTestCase {
    func child(_ title: String, _ path: String, size: UInt64, isProtected: Bool = false, sharedWith: [String]? = nil) -> StorageEntry {
        var entry = StorageEntry(id: "footprint:" + path, title: L(title, title), explanation: L("", ""), kind: .appData, path: path,
                                 size: size, isProtected: isProtected)
        entry.sharedWith = sharedWith
        return entry
    }

    /// Désinstaller : l'app et ses dossiers cochés, sauf un dossier protégé ou partagé avec une autre app.
    func testUninstallItems() {
        let word = StorageEntry(id: "application:/Applications/Microsoft Word.app", title: L("Microsoft Word", "Microsoft Word"),
                                explanation: L("", ""), kind: .application, path: "/Applications/Microsoft Word.app", size: 3_000,
                                children: [child("Cache", "/Users/test/Library/Caches/com.microsoft.Word", size: 500),
                                           child("Dossier partagé", "/Users/test/Library/Group Containers/UBF8T346G9.Office", size: 0,
                                                 isProtected: true, sharedWith: ["Microsoft Excel"]),
                                           child("Dossier privé", "/Users/test/Library/Containers/com.microsoft.Word", size: 0, isProtected: true)])
        let items = AppUninstaller.items(for: word)
        XCTAssertEqual(items.map(\.selected), [true, true, false, false])
        XCTAssertEqual(items[0].size, 2_500, "l'app seule, sans ses dossiers")
        XCTAssertEqual(items[2].blocked?.fr, "partagé avec Microsoft Excel")
        XCTAssertEqual(items[3].blocked?.fr, "protégé : accès complet au disque")
        let finder = StorageEntry(id: "application:/System/Applications/Notes.app", title: L("Notes", "Notes"), explanation: L("", ""),
                                  kind: .application, path: "/System/Applications/Notes.app", size: 1)
        XCTAssertFalse(AppUninstaller.canUninstall(finder), "jamais une app de macOS")
    }

    /// Restes : seuls les noms en forme d'identifiant d'une app absente, pas ceux d'un éditeur encore installé,
    /// ni Apple, ni les bibliothèques, ni les outils en ligne de commande.
    func testFindsLeftoversOfDeletedApps() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("vigie-restes-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: home) }
        let library = home.appendingPathComponent("Library")
        for folder in ["Caches/com.spotify.client", "Application Support/com.spotify.client", "Caches/com.google.Keystone",
                       "Caches/com.apple.Safari", "Caches/org.swift.swiftpm", "Caches/com.vercel.cli", "Application Support/Notion",
                       "Caches/org.sparkle-project.Sparkle", "Caches/com.figma.Desktop.helper"] {
            try FileManager.default.createDirectory(at: library.appendingPathComponent(folder), withIntermediateDirectories: true)
        }
        try FileManager.default.createDirectory(at: library.appendingPathComponent("Preferences"), withIntermediateDirectories: true)
        try Data("x".utf8).write(to: library.appendingPathComponent("Preferences/com.spotify.client.plist"))
        let leftovers = LeftoverFinder.find(home: home.path, installed: ["com.google.Chrome", "com.figma.Desktop"])
        XCTAssertEqual(leftovers.map(\.id), ["com.spotify.client"])
        XCTAssertEqual(leftovers[0].paths.count, 3)
        XCTAssertNil(LeftoverFinder.identifier(from: "node.js"))
        XCTAssertEqual(LeftoverFinder.identifier(from: "com.example.app.savedState"), "com.example.app")
    }

    func testSafeCleanupSkipsSlowAndPersonalItems() {
        let items = SafeCleanup.items(in: DemoData.storage(), home: DemoData.home)
        let titles = items.map(\.title.fr)
        XCTAssertTrue(titles.contains("uv"))
        XCTAssertTrue(titles.contains("Cache npm"))
        XCTAssertFalse(titles.contains("huggingface"), "modèles d'IA : longs à retélécharger")
        XCTAssertFalse(titles.contains("Caches des outils de dev"), "jamais un dossier entier")
        XCTAssertTrue(items.allSatisfy { $0.kind == .cache })
    }

    func testSystemAssetsAreGroupedAndReadOnly() {
        let entries = SystemAssets.entries(from: [("com_apple_MobileAsset_iOSSimulatorRuntime", 20_000_000_000),
                                                  ("com_apple_MobileAsset_UAF_Siri_Understanding", 5_000_000_000),
                                                  ("com_apple_MobileAsset_UAF_FM_Visual", 1_000_000_000),
                                                  ("com_apple_MobileAsset_Font8", 10_000_000)], minimumSize: 50_000_000)
        XCTAssertEqual(entries.map(\.id), ["system:simulator-runtimes", "system:intelligence"])
        XCTAssertEqual(entries[1].size, 6_000_000_000)
        XCTAssertTrue(entries.allSatisfy { StorageCleaner.cleanup(for: $0) == nil })
    }

    func testLeftoverCleanupTrashesEveryFolder() {
        let home = "/Users/test"
        var leftover = StorageEntry(id: "leftover:com.x.app", title: L("com.x.app", "com.x.app"), explanation: L("", ""), kind: .leftover,
                                    path: home + "/Library/Caches/com.x.app", size: 2)
        leftover.children = [StorageEntry(id: "leftover-file:a", title: L("Cache", "Cache"), explanation: L("", ""), kind: .leftover,
                                          path: home + "/Library/Caches/com.x.app", size: 1),
                             StorageEntry(id: "leftover-file:b", title: L("Données", "Data"), explanation: L("", ""), kind: .leftover,
                                          path: home + "/Library/Application Support/com.x.app", size: 1)]
        XCTAssertEqual(StorageCleaner.cleanup(for: leftover, home: home),
                       .trashAll([home + "/Library/Caches/com.x.app", home + "/Library/Application Support/com.x.app"]))
        XCTAssertEqual(StorageCleaner.cleanup(for: leftover.children[0], home: home), .trash)
    }
}

final class ExplorerTests: FrenchTestCase {
    /// Surfaces proportionnelles, tout dans le cadre, sans chevauchement.
    func testTreemapLayout() {
        let sizes: [Double] = [500, 250, 120, 80, 30, 15, 5]
        let frame = CGRect(x: 0, y: 0, width: 400, height: 300)
        let rects = Treemap.layout(sizes, in: frame)
        let total = sizes.reduce(0, +)
        for (size, rect) in zip(sizes, rects) {
            XCTAssertEqual(Double(rect.width * rect.height), size / total * 120_000, accuracy: 1)
            XCTAssertTrue(frame.insetBy(dx: -0.01, dy: -0.01).contains(rect), "\(rect) sort du cadre")
        }
        for i in rects.indices {
            for j in rects.indices where j > i {
                XCTAssertLessThan(rects[i].intersection(rects[j]).width * rects[i].intersection(rects[j]).height, 0.5)
            }
        }
        XCTAssertGreaterThan(rects[0].width / rects[0].height, 0.3, "le plus gros reste à peu près carré")
    }

    /// Une seule mesure donne la taille des dossiers sur plusieurs niveaux et les gros fichiers.
    func testFolderListingFromOneMeasure() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("vigie-explorer-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        func write(_ relative: String, _ bytes: Int) throws {
            let url = root.appendingPathComponent(relative)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(repeating: 1, count: bytes).write(to: url)
        }
        try write("Films/gros.mov", 3_000_000)
        try write("Films/court.mov", 10_000)
        try write("Code/projet/src/a.swift", 400_000)
        try write("Code/projet/build/sortie.bin", 1_500_000)
        try write("notes.txt", 2_000)
        var request = DiskUsage.Request(path: root.path)
        request.recordDepth = 3
        request.explorerFileMinimum = 1_000_000
        let result = DiskUsage.measure([request])[0]
        let top = try XCTUnwrap(FolderListing.make(path: root.path, from: result, root: root.path))
        XCTAssertEqual(top.items.map(\.name), ["Films", "Code"])
        XCTAssertEqual(top.size, try XCTUnwrap(StorageScanner.measureWithDu(root.path)).total)
        let code = try XCTUnwrap(FolderListing.make(path: root.path + "/Code/projet", from: result, root: root.path))
        XCTAssertEqual(code.items.map(\.name), ["build", "src"])
        let films = try XCTUnwrap(FolderListing.make(path: root.path + "/Films", from: result, root: root.path))
        XCTAssertEqual(films.items.map(\.name), ["gros.mov"], "un gros fichier listé, le petit compté à part")
        XCTAssertGreaterThan(films.other, 0)
        XCTAssertNil(FolderListing.make(path: root.path + "/Code/projet/src/x", from: result, root: root.path), "au-delà : nouvelle mesure")
    }
}

final class MacHealthTests: FrenchTestCase {
    let total: UInt64 = 500_000_000_000

    func disk(free percent: Double) -> DiskStatus {
        DiskStatus(available: UInt64(Double(total) * percent / 100), total: total)
    }

    /// Vert, orange, rouge selon la place libre ; une seule action, et seulement si elle vaut la peine.
    func testLevelsAndAction() {
        let good = MacHealth.evaluate(disk: disk(free: 40), reclaimable: 200_000_000, language: .fr)
        XCTAssertEqual(good.level, .good)
        XCTAssertEqual(good.title, "Ton Mac va bien")
        XCTAssertNil(good.action, "200 Mo ne valent pas un bouton")

        let goodWithCleanup = MacHealth.evaluate(disk: disk(free: 40), reclaimable: 34_000_000_000, language: .fr)
        XCTAssertEqual(goodWithCleanup.action, .freeSpace(34_000_000_000))
        XCTAssertEqual(goodWithCleanup.actionTitle(language: .fr), "Libérer 34 Go sans risque")

        let filling = MacHealth.evaluate(disk: disk(free: 18), reclaimable: 34_000_000_000, language: .fr)
        XCTAssertEqual(filling.level, .attention)
        XCTAssertEqual(filling.title, "Ton disque se remplit")
        XCTAssertTrue(filling.message.hasPrefix("Il reste 18 %"), filling.message)

        let full = MacHealth.evaluate(disk: disk(free: 9), reclaimable: nil, language: .fr)
        XCTAssertEqual(full.level, .critical)
        XCTAssertEqual(full.action, .scan, "pas d'analyse récente : la lancer")
        XCTAssertNil(MacHealth.evaluate(disk: disk(free: 60), reclaimable: nil, language: .fr).action, "tout va bien : rien à proposer")
        XCTAssertEqual(MacHealth.evaluate(disk: disk(free: 9), reclaimable: nil, language: .en).title, "Disk almost full")
    }
}

final class PerformanceTests: FrenchTestCase {
    /// Ce qui empêche vraiment la veille ; « UserIsActive » (tu utilises le Mac) n'en fait pas partie.
    func testParsesSleepAssertions() {
        let text = """
        Listed by owning process:
           pid 29397(Claude): [0x00095e7500019ac2] 00:00:17 NoIdleSleepAssertion named: "Electron"
           pid 625(bluetoothd): [0x000491d5000982b9] 00:03:57 UserIsActive named: "Bluetooth LE HID Activity"
           pid 4100(zoom.us): [0x0001] 01:04:00 PreventUserIdleDisplaySleep named: "Réunion"
           pid 575(powerd): [0x000912ce000189d4] 05:23:05 PreventUserIdleSystemSleep named: "Powerd - Prevent sleep while display is on"
        """
        let blockers = PerformanceReader.parseAssertions(text)
        XCTAssertEqual(blockers.map(\.name), ["Claude", "zoom.us", "powerd"])
        XCTAssertEqual(blockers[1].seconds, 3_840)
        XCTAssertTrue(blockers[1].keepsDisplayOn)
        XCTAssertEqual(blockers[0].reason, "Electron")
        XCTAssertTrue(blockers[2].isSystem)
        XCTAssertFalse(blockers[0].isSystem)
    }

    func testSpeedHealth() {
        let calm = MemoryStatus(pressure: .normal, swapUsed: 0)
        XCTAssertEqual(MacHealth.speed(memory: calm, thermal: .normal, busiest: nil, language: .fr).title, "Ton Mac est rapide")
        let chrome = BusyApp(id: "app:chrome", name: "Chrome", averageCPU: 92, minutes: 10)
        let busy = MacHealth.speed(memory: calm, thermal: .normal, busiest: chrome, language: .fr)
        XCTAssertEqual(busy.title, "Une app fait travailler ton Mac")
        XCTAssertEqual(busy.action, .quit(id: "app:chrome", name: "Chrome"))
        XCTAssertEqual(busy.actionTitle(language: .fr), "Quitter Chrome")
        XCTAssertEqual(MacHealth.speed(memory: calm, thermal: .normal, busiest: BusyApp(id: "x", name: "X", averageCPU: 92, minutes: 1), language: .fr).level,
                       .good, "une pointe d'une minute n'est pas une alerte")
        let tight = MacHealth.speed(memory: MemoryStatus(pressure: .warning, swapUsed: 3_600_000_000), thermal: .normal, busiest: nil, language: .fr)
        XCTAssertEqual(tight.title, "Ton Mac manque de mémoire")
        XCTAssertTrue(tight.message.contains("3,6 Go"), tight.message)
        XCTAssertEqual(MacHealth.speed(memory: calm, thermal: .critical, busiest: chrome, language: .fr).level, .critical)
    }

    /// La carte principale montre le plus urgent des deux.
    func testWorstOfDiskAndSpeed() {
        let diskOK = MacHealth(level: .good, title: "disque", message: "", action: nil)
        let slow = MacHealth(level: .attention, title: "vitesse", message: "", action: .showMemory)
        XCTAssertEqual(MacHealth.worst(diskOK, slow)?.title, "vitesse")
        let diskFull = MacHealth(level: .critical, title: "plein", message: "", action: .scan)
        XCTAssertEqual(MacHealth.worst(diskFull, slow)?.title, "plein")
        XCTAssertEqual(MacHealth.worst(nil, slow)?.title, "vitesse")
    }

    /// Prévenir au bon moment, et pas deux fois dans l'heure.
    func testSpeedAlerts() {
        let now = Date()
        let calm = MemoryStatus(pressure: .normal, swapUsed: 0)
        let figma = BusyApp(id: "app:figma", name: "Figma", averageCPU: 88, minutes: 6)
        func input(busy: BusyApp? = nil, memory: MemoryStatus = MemoryStatus(pressure: .normal, swapUsed: 0), thermal: ThermalLevel = .normal,
                   blockers: [SleepBlocker] = [], onBattery: Bool = false) -> SpeedAlertPolicy.Input {
            SpeedAlertPolicy.Input(busiest: busy, memory: memory, memoryHog: "Safari", thermal: thermal, blockers: blockers, onBattery: onBattery)
        }
        XCTAssertTrue(SpeedAlertPolicy.alerts(for: input(), lastSent: [:], now: now, language: .fr).isEmpty)

        let busy = SpeedAlertPolicy.alerts(for: input(busy: figma), lastSent: [:], now: now, language: .fr)
        XCTAssertEqual(busy.map(\.title), ["Figma fait travailler ton Mac"])
        XCTAssertEqual(busy.first?.quitGroupID, "app:figma")
        XCTAssertTrue(SpeedAlertPolicy.alerts(for: input(busy: BusyApp(id: "app:figma", name: "Figma", averageCPU: 88, minutes: 3)),
                                              lastSent: [:], now: now, language: .fr).isEmpty, "trois minutes : pas encore")
        XCTAssertTrue(SpeedAlertPolicy.alerts(for: input(busy: figma), lastSent: ["busy:app:figma": now.addingTimeInterval(-600)],
                                              now: now, language: .fr).isEmpty, "déjà prévenu il y a dix minutes")
        XCTAssertEqual(SpeedAlertPolicy.alerts(for: input(busy: figma), lastSent: ["busy:app:figma": now.addingTimeInterval(-4000)],
                                               now: now, language: .fr).count, 1, "plus d'une heure : on peut reprévenir")

        let memory = SpeedAlertPolicy.alerts(for: input(memory: MemoryStatus(pressure: .critical, swapUsed: 6_000_000_000)), lastSent: [:], now: now, language: .fr)
        XCTAssertEqual(memory.first?.body, "Il range des choses sur le disque et devient lent. Safari en prend le plus.")
        XCTAssertTrue(SpeedAlertPolicy.alerts(for: input(memory: MemoryStatus(pressure: .warning, swapUsed: 0)), lastSent: [:], now: now, language: .fr).isEmpty,
                      "orange : visible dans Vigie, pas de notification")

        let zoom = SleepBlocker(pid: 1, name: "zoom.us", seconds: 2_700, kind: "PreventUserIdleDisplaySleep", reason: "", isSystem: false, keepsDisplayOn: true)
        let audio = SleepBlocker(pid: 2, name: "coreaudiod", seconds: 9_000, kind: "PreventUserIdleSystemSleep", reason: "", isSystem: true, keepsDisplayOn: false)
        XCTAssertEqual(SpeedAlertPolicy.alerts(for: input(blockers: [zoom, audio], onBattery: true), lastSent: [:], now: now, language: .fr).map(\.title),
                       ["Zoom empêche ton Mac de dormir"])
        XCTAssertTrue(SpeedAlertPolicy.alerts(for: input(blockers: [zoom], onBattery: false), lastSent: [:], now: now, language: .fr).isEmpty, "branché : pas grave")

        let hot = SpeedAlertPolicy.alerts(for: input(busy: figma, thermal: .hot), lastSent: [:], now: now, language: .fr)
        XCTAssertEqual(hot.map(\.key), ["thermal"], "chaleur et app occupée : une seule alerte")
    }

    func testRealReadings() {
        let status = PerformanceReader.read(includeBlockers: false)
        XCTAssertNotNil(MemoryPressure(rawValue: status.memory.pressure.rawValue))
        XCTAssertNotNil(PerformanceReader.energy(getpid()), "énergie de notre propre processus lisible")
    }
}

final class StartupTests: FrenchTestCase {
    let apps = [InstalledApp(id: "com.bjango.istatmenus", name: "iStat Menus", path: "/Applications/iStat Menus.app"),
                InstalledApp(id: "com.docker.docker", name: "Docker", path: "/Applications/Docker.app"),
                InstalledApp(id: "com.google.Chrome", name: "Google Chrome", path: "/Applications/Google Chrome.app")]

    func testParsesLaunchctl() {
        let list = "PID\tStatus\tLabel\n90855\t0\tcom.example.ledger\n-\t0\tcom.example.cleanup\n"
        let running = StartupReader.parseList(list)
        XCTAssertEqual(running["com.example.ledger"] ?? nil, 90855)
        XCTAssertNotNil(running["com.example.cleanup"])
        XCTAssertNil(running["com.example.cleanup"] ?? nil, "ne tourne pas")
        let disabled = StartupReader.parseDisabled("\tdisabled services = {\n\t\t\"com.docker.helper\" => enabled\n\t\t\"com.x.agent\" => disabled\n\t}")
        XCTAssertEqual(disabled, ["com.docker.helper": true, "com.x.agent": false])
    }

    /// Chaque agent relié à l'app qui l'a installé, et expliqué.
    func testOwnersAndKinds() {
        XCTAssertEqual(StartupReader.owner(label: "com.bjango.istatmenus.agent", program: nil, apps: apps)?.name, "iStat Menus")
        XCTAssertEqual(StartupReader.owner(label: "com.docker.socket", program: nil, apps: apps)?.name, "Docker", "même éditeur")
        XCTAssertEqual(StartupReader.owner(label: "x", program: "/Applications/Foo.app/Contents/MacOS/foo", apps: apps)?.name, "Foo")
        XCTAssertNil(StartupReader.owner(label: "com.example.cleanup", program: "/Users/me/.local/bin/cleanup.sh", apps: apps))
        XCTAssertEqual(StartupReader.kind(label: "com.google.keystone.agent", program: nil, owner: apps[2], scope: .user, home: "/Users/me"), .updater)
        XCTAssertEqual(StartupReader.kind(label: "com.example.cleanup", program: "/Users/me/x.sh", owner: nil, scope: .user, home: "/Users/me"), .script)
        XCTAssertEqual(StartupReader.kind(label: "com.docker.vmnetd", program: nil, owner: apps[1], scope: .system, home: "/Users/me"), .service)
        let helper = StartupItem(label: "com.bjango.istatmenus.agent", scope: .appHelper, plistPath: nil, program: nil, ownerName: "iStat Menus",
                                 ownerPath: nil, kind: .helper, pid: 12, isEnabled: true)
        XCTAssertFalse(helper.canToggle, "les aides d'apps se gèrent dans Réglages")
        XCTAssertTrue(helper.explanation.fr.hasPrefix("Aide de iStat Menus"))
    }

    /// Sur ce Mac : rien d'Apple, et les agents de l'utilisateur se coupent.
    func testRealStartupItems() {
        let items = StartupReader.read()
        XCTAssertFalse(items.contains { $0.label.hasPrefix("com.apple.") })
        XCTAssertTrue(items.filter { $0.scope == .user }.allSatisfy(\.canToggle))
    }
}

final class AppFootprintTests: FrenchTestCase {
    func testFindsTheAppsFilesAndProtectsPrivateFolders() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("vigie-app-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: home) }
        let app = home.appendingPathComponent("Applications/TestApp.app")
        try FileManager.default.createDirectory(at: app.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        let plist: NSDictionary = ["CFBundleIdentifier": "com.example.testapp", "CFBundleName": "TestApp", "CFBundleExecutable": "TestApp"]
        plist.write(to: app.appendingPathComponent("Contents/Info.plist"), atomically: true)
        let library = home.appendingPathComponent("Library")
        for folder in ["Application Support/TestApp", "Caches/com.example.testapp", "Containers/com.example.testapp",
                       "Group Containers/ABC123.com.example.testapp", "Application Support/AutreApp"] {
            try FileManager.default.createDirectory(at: library.appendingPathComponent(folder), withIntermediateDirectories: true)
        }
        try FileManager.default.createDirectory(at: library.appendingPathComponent("LaunchAgents"), withIntermediateDirectories: true)
        try Data(count: 1_000_000).write(to: library.appendingPathComponent("Application Support/TestApp/données"))
        try Data("x".utf8).write(to: library.appendingPathComponent("Preferences/com.example.testapp.plist").createParents())
        try Data("x".utf8).write(to: library.appendingPathComponent("LaunchAgents/com.example.testapp.helper.plist"))

        let entries = AppFootprint.related(to: app.path, home: home.path, fullDiskAccess: false)
        let found = entries.map { $0.path.replacingOccurrences(of: library.path + "/", with: "") }
        XCTAssertEqual(Set(found), [
            "Application Support/TestApp", "Caches/com.example.testapp", "Preferences/com.example.testapp.plist",
            "LaunchAgents/com.example.testapp.helper.plist", "Containers/com.example.testapp", "Group Containers/ABC123.com.example.testapp",
        ])
        XCTAssertEqual(entries.first?.path.hasSuffix("Application Support/TestApp"), true, "le plus gros d'abord")
        XCTAssertTrue(entries.filter { $0.path.contains("Containers") }.allSatisfy(\.isProtected))
        XCTAssertFalse(found.contains("Application Support/AutreApp"))
    }

    /// Un dossier n'est compté qu'une fois : « Claude » va à Claude.app, pas à l'assistant « Claude Code URL Handler »,
    /// et deux copies d'une même app (même identifiant) ne se partagent pas ses dossiers.
    func testEachFolderBelongsToOneApp() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("vigie-apps-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: home) }
        func makeApp(_ name: String, id: String, executable: String? = nil) throws {
            let app = home.appendingPathComponent("Applications/\(name).app")
            try FileManager.default.createDirectory(at: app.appendingPathComponent("Contents"), withIntermediateDirectories: true)
            let plist: NSDictionary = ["CFBundleIdentifier": id, "CFBundleName": name, "CFBundleExecutable": executable ?? name]
            plist.write(to: app.appendingPathComponent("Contents/Info.plist"), atomically: true)
        }
        try makeApp("Claude", id: "com.example.claude")
        // Son exécutable « claude » désigne aussi « Application Support/Claude » : le disque ignore les majuscules.
        try makeApp("Claude Code URL Handler", id: "com.example.claude-url", executable: "claude")
        try makeApp("Studio", id: "com.example.studio")
        try makeApp("Studio-beta", id: "com.example.studio")
        let library = home.appendingPathComponent("Library")
        for folder in ["Application Support/Claude", "Caches/com.example.studio"] {
            let url = library.appendingPathComponent(folder)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            try Data(count: 2_000_000).write(to: url.appendingPathComponent("contenu"))
        }

        let apps = StorageScanner.scanApplications(home: home.path, minimumSize: 0, folders: [home.path + "/Applications"])
        func children(_ name: String) -> [String] {
            apps.first { $0.title.fr == name }?.children.map { PathRules.lastComponent($0.path) } ?? []
        }
        XCTAssertEqual(children("Claude"), ["Claude"])
        XCTAssertEqual(children("Claude Code URL Handler"), [])
        XCTAssertEqual(children("Studio").count + children("Studio-beta").count, 1)
        let total = apps.reduce(UInt64(0)) { $0 + $1.children.reduce(0) { $0 + $1.size } }
        XCTAssertLessThan(total, 5_000_000, "chaque dossier compté une seule fois")
    }
}

private extension URL {
    func createParents() throws -> URL {
        try FileManager.default.createDirectory(at: deletingLastPathComponent(), withIntermediateDirectories: true)
        return self
    }
}
