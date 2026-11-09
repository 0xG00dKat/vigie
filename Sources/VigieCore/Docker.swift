import Foundation

/// Un conteneur Docker en cours d'exécution.
public struct DockerContainer: Sendable, Identifiable, Equatable {
    public var id: String
    public var name: String
    public var image: String
    /// Projet Docker Compose (étiquette `com.docker.compose.project`).
    public var project: String?
    public var service: String?
    public var ports: [Int]
    public var startedAt: Date?
    public var cpuPercent: Double?
    public var memory: UInt64?

    public init(id: String, name: String, image: String, project: String? = nil, service: String? = nil,
                ports: [Int] = [], startedAt: Date? = nil, cpuPercent: Double? = nil, memory: UInt64? = nil) {
        self.id = id
        self.name = name
        self.image = image
        self.project = project
        self.service = service
        self.ports = ports
        self.startedAt = startedAt
        self.cpuPercent = cpuPercent
        self.memory = memory
    }
}

/// Place occupée dans Docker, telle que la donne `docker system df`.
public struct DockerDiskUsage: Sendable, Equatable {
    public struct Item: Sendable, Equatable {
        public var size: UInt64
        public var reclaimable: UInt64
        public var count: Int
        public var active: Int

        public init(size: UInt64 = 0, reclaimable: UInt64 = 0, count: Int = 0, active: Int = 0) {
            self.size = size
            self.reclaimable = reclaimable
            self.count = count
            self.active = active
        }
    }

    public var images = Item()
    public var containers = Item()
    public var volumes = Item()
    public var buildCache = Item()

    public init(images: Item = Item(), containers: Item = Item(), volumes: Item = Item(), buildCache: Item = Item()) {
        self.images = images
        self.containers = containers
        self.volumes = volumes
        self.buildCache = buildCache
    }

    public var total: UInt64 { images.size + containers.size + volumes.size + buildCache.size }
}

/// Fichier de disque virtuel de la machine Docker, sur le disque du Mac.
/// Il occupe de la place même quand Docker est arrêté.
public struct DockerVirtualDisk: Sendable, Equatable {
    public var engine: String
    public var path: String
    /// Place réellement occupée sur le Mac (le fichier est « creux » : sa taille apparente est plus grande).
    public var allocated: UInt64
    public var maximum: UInt64

    public init(engine: String, path: String, allocated: UInt64, maximum: UInt64) {
        self.engine = engine
        self.path = path
        self.allocated = allocated
        self.maximum = maximum
    }
}

public struct DockerStatus: Sendable, Equatable {
    public enum State: Sendable, Equatable {
        case notInstalled
        case notRunning
        case running
    }

    public var state: State
    public var containers: [DockerContainer]
    public var stoppedContainers: Int
    public var disk: DockerDiskUsage?
    public var virtualDisk: DockerVirtualDisk?
    public var date: Date

    public init(state: State, containers: [DockerContainer] = [], stoppedContainers: Int = 0,
                disk: DockerDiskUsage? = nil, virtualDisk: DockerVirtualDisk? = nil, date: Date = Date()) {
        self.state = state
        self.containers = containers
        self.stoppedContainers = stoppedContainers
        self.disk = disk
        self.virtualDisk = virtualDisk
        self.date = date
    }

    public var memory: UInt64 { containers.reduce(0) { $0 + ($1.memory ?? 0) } }

    /// Conteneurs regroupés par projet Compose ; les conteneurs isolés forment chacun leur groupe.
    public var groups: [DockerGroup] {
        var byProject: [String: [DockerContainer]] = [:]
        var singles: [DockerGroup] = []
        for container in containers {
            if let project = container.project {
                byProject[project, default: []].append(container)
            } else {
                singles.append(DockerGroup(id: "docker:" + container.id, project: nil, containers: [container]))
            }
        }
        let projects = byProject.map { DockerGroup(id: "docker:project:" + $0.key, project: $0.key, containers: $0.value.sorted { $0.name < $1.name }) }
        return (projects + singles).sorted {
            if $0.memory != $1.memory { return $0.memory > $1.memory }
            return $0.title < $1.title
        }
    }
}

public struct DockerGroup: Sendable, Identifiable, Equatable {
    public var id: String
    public var project: String?
    public var containers: [DockerContainer]

    public var title: String { project ?? containers.first?.name ?? "?" }
    public var memory: UInt64 { containers.reduce(0) { $0 + ($1.memory ?? 0) } }
    public var cpuPercent: Double { containers.reduce(0) { $0 + ($1.cpuPercent ?? 0) } }
    public var ports: [Int] { Array(Set(containers.flatMap(\.ports))).sorted() }
    public var startedAt: Date? { containers.compactMap(\.startedAt).min() }
}

/// Lit l'état de Docker avec la commande `docker` installée.
public enum DockerReader {
    public static func findCLI(home: String = NSHomeDirectory()) -> URL? {
        let candidates = [
            "/usr/local/bin/docker",
            "/opt/homebrew/bin/docker",
            home + "/.docker/bin/docker",
            "/Applications/Docker.app/Contents/Resources/bin/docker",
            home + "/.orbstack/bin/docker",
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }.map { URL(fileURLWithPath: $0) }
    }

    /// Lecture complète (quelques secondes au plus) : à appeler hors du fil principal.
    public static func read(home: String = NSHomeDirectory()) -> DockerStatus {
        let virtualDisk = findVirtualDisk(home: home)
        guard let cli = findCLI(home: home) else {
            return DockerStatus(state: virtualDisk == nil ? .notInstalled : .notRunning, virtualDisk: virtualDisk)
        }
        let list = run(cli, ["ps", "--no-trunc", "--format", "{{json .}}"], timeout: 6)
        guard list.status == 0 else {
            return DockerStatus(state: .notRunning, virtualDisk: virtualDisk)
        }
        var containers = parseContainers(list.output)

        if !containers.isEmpty {
            let stats = parseStats(run(cli, ["stats", "--no-stream", "--format", "{{json .}}"], timeout: 10).output)
            let started = parseStartTimes(run(cli, ["inspect", "--format", "{{.Name}} {{.State.StartedAt}}"] + containers.map(\.id), timeout: 6).output)
            for index in containers.indices {
                let name = containers[index].name
                containers[index].cpuPercent = stats[name]?.cpu
                containers[index].memory = stats[name]?.memory
                containers[index].startedAt = started[name]
            }
        }

        let disk = parseDiskUsage(run(cli, ["system", "df", "--format", "{{json .}}"], timeout: 10).output)
        let stopped = disk.map { max(0, $0.containers.count - $0.containers.active) } ?? 0
        return DockerStatus(state: .running, containers: containers, stoppedContainers: stopped, disk: disk, virtualDisk: virtualDisk)
    }

    /// `docker stop` (arrêt propre, puis forcé par Docker après 10 s).
    public static func stop(_ ids: [String], home: String = NSHomeDirectory()) -> Bool {
        guard let cli = findCLI(home: home), !ids.isEmpty else { return false }
        return run(cli, ["stop"] + ids, timeout: 40).status == 0
    }

    // MARK: - Disque virtuel

    public static func findVirtualDisk(home: String = NSHomeDirectory()) -> DockerVirtualDisk? {
        let candidates: [(engine: String, path: String)] = [
            ("Docker Desktop", home + "/Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw"),
            ("OrbStack", home + "/Library/Group Containers/HUAQ24HBR6.dev.orbstack/data/data.img"),
            ("OrbStack", home + "/.orbstack/data/data.img"),
            ("Colima", home + "/.colima/_lima/colima/diffdisk"),
        ]
        for candidate in candidates {
            let url = URL(fileURLWithPath: candidate.path)
            guard let values = try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileSizeKey]),
                  let allocated = values.totalFileAllocatedSize else { continue }
            return DockerVirtualDisk(
                engine: candidate.engine,
                path: candidate.path,
                allocated: UInt64(allocated),
                maximum: UInt64(values.fileSize ?? allocated)
            )
        }
        return nil
    }

    // MARK: - Commande

    static func run(_ cli: URL, _ arguments: [String], timeout: TimeInterval) -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = cli
        process.arguments = arguments
        var environment = ProcessInfo.processInfo.environment
        let home = NSHomeDirectory()
        environment["PATH"] = "/usr/local/bin:/opt/homebrew/bin:\(home)/.docker/bin:/Applications/Docker.app/Contents/Resources/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        process.environment = environment
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return (-1, "")
        }
        let watchdog = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: watchdog)
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        watchdog.cancel()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    // MARK: - Lecture des sorties (testées à part)

    private static func jsonLines(_ text: String) -> [[String: Any]] {
        text.split(whereSeparator: \.isNewline).compactMap { line in
            guard let data = line.data(using: .utf8) else { return nil }
            return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        }
    }

    static func parseContainers(_ text: String) -> [DockerContainer] {
        jsonLines(text).compactMap { object in
            guard let id = object["ID"] as? String else { return nil }
            let labels = parseLabels(object["Labels"] as? String ?? "")
            let name = (object["Names"] as? String ?? id).split(separator: ",").first.map(String.init) ?? id
            return DockerContainer(
                id: id,
                name: name,
                image: object["Image"] as? String ?? "",
                project: labels["com.docker.compose.project"],
                service: labels["com.docker.compose.service"],
                ports: parsePorts(object["Ports"] as? String ?? "")
            )
        }
    }

    static func parseLabels(_ text: String) -> [String: String] {
        var labels: [String: String] = [:]
        for pair in text.split(separator: ",") {
            guard let equals = pair.firstIndex(of: "=") else { continue }
            labels[String(pair[..<equals])] = String(pair[pair.index(after: equals)...])
        }
        return labels
    }

    /// Ports publiés sur le Mac : `0.0.0.0:5432->5432/tcp, [::]:5432->5432/tcp` → [5432].
    static func parsePorts(_ text: String) -> [Int] {
        var ports = Set<Int>()
        for part in text.components(separatedBy: ",") {
            guard let arrow = part.range(of: "->") else { continue }
            let host = part[..<arrow.lowerBound]
            guard let colon = host.lastIndex(of: ":") else { continue }
            let value = host[host.index(after: colon)...]
            // Plage publiée (`9000-9001->9000-9001/tcp`) : on garde les deux bornes.
            for bound in value.split(separator: "-") {
                if let port = Int(bound) { ports.insert(port) }
            }
        }
        return ports.sorted()
    }

    static func parseStats(_ text: String) -> [String: (cpu: Double, memory: UInt64)] {
        var result: [String: (cpu: Double, memory: UInt64)] = [:]
        for object in jsonLines(text) {
            guard let name = object["Name"] as? String else { continue }
            let cpu = Double((object["CPUPerc"] as? String ?? "").replacingOccurrences(of: "%", with: "")) ?? 0
            let used = (object["MemUsage"] as? String ?? "").components(separatedBy: "/").first ?? ""
            result[name] = (cpu, parseSize(used) ?? 0)
        }
        return result
    }

    static func parseStartTimes(_ text: String) -> [String: Date] {
        var result: [String: Date] = [:]
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        for line in text.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: " ", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let name = parts[0].hasPrefix("/") ? String(parts[0].dropFirst()) : String(parts[0])
            var stamp = String(parts[1]).trimmingCharacters(in: .whitespaces)
            // Docker donne des nanosecondes ; le format ISO 8601 de Foundation n'en lit que trois chiffres.
            if let dot = stamp.firstIndex(of: "."), let zone = stamp[dot...].firstIndex(where: { $0 == "Z" || $0 == "+" || $0 == "-" }) {
                let fraction = stamp[stamp.index(after: dot)..<zone].prefix(3)
                stamp = String(stamp[..<dot]) + "." + fraction + String(stamp[zone...])
            }
            if let date = formatter.date(from: stamp) ?? plain.date(from: stamp) {
                result[name] = date
            }
        }
        return result
    }

    static func parseDiskUsage(_ text: String) -> DockerDiskUsage? {
        let objects = jsonLines(text)
        guard !objects.isEmpty else { return nil }
        var usage = DockerDiskUsage()
        for object in objects {
            let reclaimableText = (object["Reclaimable"] as? String ?? "").components(separatedBy: " ").first ?? ""
            let item = DockerDiskUsage.Item(
                size: parseSize(object["Size"] as? String ?? "") ?? 0,
                reclaimable: parseSize(reclaimableText) ?? 0,
                count: Int(object["TotalCount"] as? String ?? "") ?? 0,
                active: Int(object["Active"] as? String ?? "") ?? 0
            )
            switch (object["Type"] as? String ?? "").lowercased() {
            case "images": usage.images = item
            case "containers": usage.containers = item
            case "local volumes": usage.volumes = item
            case "build cache": usage.buildCache = item
            default: break
            }
        }
        return usage
    }

    /// Tailles affichées par Docker : décimales (`2.7GB`, `512kB`) ou binaires (`38.5MiB`).
    public static func parseSize(_ text: String) -> UInt64? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard let unitStart = trimmed.firstIndex(where: { $0.isLetter }) else {
            return Double(trimmed).map { UInt64($0) }
        }
        guard let number = Double(trimmed[..<unitStart].trimmingCharacters(in: .whitespaces)) else { return nil }
        let units: [String: Double] = [
            "b": 1,
            "kb": 1e3, "mb": 1e6, "gb": 1e9, "tb": 1e12,
            "kib": 1024, "mib": 1_048_576, "gib": 1_073_741_824, "tib": 1_099_511_627_776,
        ]
        guard let factor = units[trimmed[unitStart...].lowercased()] else { return nil }
        return UInt64((number * factor).rounded())
    }
}

// MARK: - Volumes orphelins

/// Un volume Docker qu'aucun conteneur (même arrêté) n'utilise plus.
/// Vigie ne supprime jamais de volume : il peut contenir la base de données d'un projet. Elle le montre, dit d'où
/// il vient, et donne la commande à copier.
public struct DockerVolume: Sendable, Equatable, Identifiable {
    public var id: String { name }
    public var name: String
    public var size: UInt64
    /// Projet Docker Compose qui l'a créé.
    public var project: String?
    /// Volume anonyme (créé sans nom par un conteneur) : presque toujours un reste sans valeur.
    public var isAnonymous: Bool

    public init(name: String, size: UInt64, project: String? = nil, isAnonymous: Bool = false) {
        self.name = name
        self.size = size
        self.project = project
        self.isAnonymous = isAnonymous
    }

    public var removeCommand: String { "docker volume rm \(name)" }
}

extension DockerReader {
    /// Volumes sans conteneur (`docker system df -v`), du plus gros au plus petit. Vide si Docker ne tourne pas.
    public static func orphanVolumes(home: String = NSHomeDirectory()) -> [DockerVolume] {
        guard let cli = findCLI(home: home) else { return [] }
        let result = run(cli, ["system", "df", "-v", "--format", "{{json .}}"], timeout: 15)
        guard result.status == 0 else { return [] }
        return parseOrphanVolumes(result.output)
    }

    public static func parseOrphanVolumes(_ text: String) -> [DockerVolume] {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let volumes = json["Volumes"] as? [[String: Any]] else { return [] }
        return volumes.compactMap { volume -> DockerVolume? in
            guard let name = volume["Name"] as? String else { return nil }
            let links = Int("\(volume["Links"] ?? "0")") ?? 0
            guard links == 0 else { return nil }
            var labels: [String: String] = [:]
            for pair in ((volume["Labels"] as? String) ?? "").split(separator: ",") {
                let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                labels[String(parts[0])] = parts.count > 1 ? String(parts[1]) : ""
            }
            return DockerVolume(name: name, size: parseSize((volume["Size"] as? String) ?? "") ?? 0,
                                project: labels["com.docker.compose.project"],
                                isAnonymous: labels["com.docker.volume.anonymous"] != nil)
        }
        .sorted { $0.size > $1.size }
    }
}
