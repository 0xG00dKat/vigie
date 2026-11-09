import Darwin
import Foundation
import IOKit
import IOKit.ps

// MARK: - Mesures

/// Pression mémoire, comme la jauge du Moniteur d'activité : verte, orange, rouge.
public enum MemoryPressure: Int, Sendable {
    case normal = 1, warning = 2, critical = 4
}

public struct MemoryStatus: Sendable, Equatable {
    public var pressure: MemoryPressure
    /// Mémoire rangée sur le disque faute de place (« swap »).
    public var swapUsed: UInt64

    public init(pressure: MemoryPressure, swapUsed: UInt64) {
        self.pressure = pressure
        self.swapUsed = swapUsed
    }
}

public struct BatteryStatus: Sendable, Equatable {
    public var percent: Int
    public var charging: Bool
    public var onPower: Bool
    public var minutesRemaining: Int?
    /// Capacité restante par rapport à une batterie neuve, en %.
    public var health: Int?
    public var cycles: Int?

    public init(percent: Int, charging: Bool, onPower: Bool, minutesRemaining: Int?, health: Int?, cycles: Int?) {
        self.percent = percent
        self.charging = charging
        self.onPower = onPower
        self.minutesRemaining = minutesRemaining
        self.health = health
        self.cycles = cycles
    }
}

public enum ThermalLevel: Sendable, Equatable {
    case normal, warm, hot, critical
}

/// Une app qui empêche le Mac de se mettre en veille (lu dans `pmset -g assertions`).
public struct SleepBlocker: Sendable, Equatable, Identifiable {
    public var id: String { "\(pid)-\(kind)-\(reason)" }
    public var pid: Int32
    public var name: String
    public var seconds: Int
    public var kind: String
    public var reason: String
    /// Service de macOS (lecture audio, Bluetooth, écran allumé…) : normal, masqué en mode Simple.
    public var isSystem: Bool
    /// Empêche aussi l'écran de s'éteindre.
    public var keepsDisplayOn: Bool
}

public struct PerformanceStatus: Sendable, Equatable {
    public var memory: MemoryStatus
    public var battery: BatteryStatus?
    public var thermal: ThermalLevel
    public var blockers: [SleepBlocker]

    public init(memory: MemoryStatus, battery: BatteryStatus?, thermal: ThermalLevel, blockers: [SleepBlocker]) {
        self.memory = memory
        self.battery = battery
        self.thermal = thermal
        self.blockers = blockers
    }
}

/// Lectures sans droits administrateur : `sysctl`, IOKit, `pmset`, `proc_pid_rusage`.
public enum PerformanceReader {
    public static func read(includeBlockers: Bool = true) -> PerformanceStatus {
        PerformanceStatus(memory: memory(), battery: battery(), thermal: thermal(), blockers: includeBlockers ? sleepBlockers() : [])
    }

    public static func memory() -> MemoryStatus {
        var level: Int32 = 1
        var size = MemoryLayout<Int32>.size
        sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0)
        var swap = xsw_usage()
        var swapSize = MemoryLayout<xsw_usage>.size
        sysctlbyname("vm.swapusage", &swap, &swapSize, nil, 0)
        return MemoryStatus(pressure: MemoryPressure(rawValue: Int(level)) ?? .normal, swapUsed: UInt64(swap.xsu_used))
    }

    public static func thermal() -> ThermalLevel {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: return .normal
        case .fair: return .warm
        case .serious: return .hot
        case .critical: return .critical
        @unknown default: return .normal
        }
    }

    /// Charge et état depuis IOKit ; santé et cycles depuis la batterie elle-même. Nil sur un Mac de bureau.
    public static func battery() -> BatteryStatus? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType else { continue }
            let current = description[kIOPSCurrentCapacityKey] as? Int ?? 0
            let maximum = max(description[kIOPSMaxCapacityKey] as? Int ?? 100, 1)
            let charging = description[kIOPSIsChargingKey] as? Bool ?? false
            let onPower = description[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue
            let minutes = description[kIOPSTimeToEmptyKey] as? Int
            let (health, cycles) = batteryHealth()
            return BatteryStatus(percent: current * 100 / maximum, charging: charging, onPower: onPower,
                                 minutesRemaining: (minutes ?? -1) > 0 && !onPower ? minutes : nil, health: health, cycles: cycles)
        }
        return nil
    }

    static func batteryHealth() -> (Int?, Int?) {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return (nil, nil) }
        defer { IOObjectRelease(service) }
        func value(_ key: String) -> Int? {
            IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Int
        }
        let cycles = value("CycleCount")
        let design = value("DesignCapacity") ?? 0
        let raw = value("AppleRawMaxCapacity") ?? value("NominalChargeCapacity") ?? 0
        if design > 200, raw > 0 { return (min(100, raw * 100 / design), cycles) }
        if let percent = value("MaxCapacity"), percent <= 100 { return (percent, cycles) }
        return (nil, cycles)
    }

    public static func sleepBlockers() -> [SleepBlocker] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = ["-g", "assertions"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return [] }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return parseAssertions(String(decoding: data, as: UTF8.self))
    }

    /// Ce qui empêche vraiment la veille. « UserIsActive » (tu utilises le Mac) n'en fait pas partie.
    static let sleepKinds: Set<String> = ["NoIdleSleepAssertion", "PreventUserIdleSystemSleep", "PreventSystemSleep",
                                          "NoDisplaySleepAssertion", "PreventUserIdleDisplaySleep"]
    static let displayKinds: Set<String> = ["NoDisplaySleepAssertion", "PreventUserIdleDisplaySleep"]
    static let systemNames: Set<String> = ["powerd", "bluetoothd", "rcd", "coreaudiod", "sharingd", "WindowServer", "backupd",
                                           "mds", "mds_stores", "softwareupdated", "useractivityd", "locationd", "airportd", "apsd", "kernel_task"]

    /// Lignes comme `pid 29397(Claude): [0x…] 00:00:17 NoIdleSleepAssertion named: "Electron"`.
    public static func parseAssertions(_ text: String) -> [SleepBlocker] {
        var blockers: [SleepBlocker] = []
        for line in text.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("pid "), let open = trimmed.firstIndex(of: "("), let close = trimmed.firstIndex(of: ")"),
                  open < close, let pid = Int32(trimmed[trimmed.index(trimmed.startIndex, offsetBy: 4)..<open]) else { continue }
            let name = String(trimmed[trimmed.index(after: open)..<close])
            guard let bracket = trimmed.range(of: "] ") else { continue }
            let rest = trimmed[bracket.upperBound...].split(separator: " ", maxSplits: 2).map(String.init)
            guard rest.count >= 2, sleepKinds.contains(rest[1]) else { continue }
            let parts = rest[0].split(separator: ":").compactMap { Int($0) }
            let seconds = parts.count == 3 ? parts[0] * 3600 + parts[1] * 60 + parts[2] : 0
            var reason = ""
            if let named = trimmed.range(of: "named: \"") {
                reason = String(trimmed[named.upperBound...].prefix { $0 != "\"" })
            }
            blockers.append(SleepBlocker(pid: pid, name: name, seconds: seconds, kind: rest[1], reason: reason,
                                         isSystem: systemNames.contains(name) || name.hasPrefix("com.apple"),
                                         keepsDisplayOn: displayKinds.contains(rest[1])))
        }
        return blockers
    }

    /// Énergie consommée par un processus depuis son lancement (nanojoules), comme la colonne « Énergie »
    /// du Moniteur d'activité. Lisible pour tes apps, pas pour les services de macOS.
    public static func energy(_ pid: Int32) -> UInt64? {
        var info = rusage_info_v6()
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V6, $0) }
        }
        return result == 0 ? info.ri_energy_nj : nil
    }
}

// MARK: - État « vitesse »

/// Une app qui fait beaucoup travailler le processeur depuis un moment.
public struct BusyApp: Sendable, Equatable {
    public var id: String
    public var name: String
    /// Moyenne du processeur sur la période (100 = un cœur entier).
    public var averageCPU: Double
    public var minutes: Int

    public init(id: String, name: String, averageCPU: Double, minutes: Int) {
        self.id = id
        self.name = name
        self.averageCPU = averageCPU
        self.minutes = minutes
    }
}

extension MacHealth {
    /// Au-delà de ce processeur moyen, pendant au moins deux minutes, une app « fait travailler ton Mac ».
    public static let busyThreshold: Double = 70

    /// Vert « Ton Mac est rapide », orange quand une app s'emballe ou que la mémoire manque, rouge quand il chauffe trop.
    public static func speed(memory: MemoryStatus, thermal: ThermalLevel, busiest: BusyApp?, language: Language = Localization.current) -> MacHealth {
        let fr = language == .fr
        if thermal == .critical || thermal == .hot {
            var message = fr ? "macOS ralentit le processeur pour le refroidir." : "macOS is slowing the processor down to cool it."
            if let busiest {
                message += fr ? " \(busiest.name) le fait beaucoup travailler." : " \(busiest.name) is working it hard."
            }
            return MacHealth(level: thermal == .critical ? .critical : .attention, title: fr ? "Ton Mac chauffe" : "Your Mac is hot",
                             message: message, action: busiest.map { .quit(id: $0.id, name: $0.name) })
        }
        if memory.pressure != .normal {
            let swap = Format.bytes(memory.swapUsed, decimal: true, in: language)
            let message = memory.swapUsed > 500_000_000
                ? (fr ? "Il range \(swap) sur le disque faute de place, d'où la lenteur. Quitter une app ou fermer des onglets aide."
                      : "It's storing \(swap) on the disk for lack of room, hence the slowness. Quitting an app or closing tabs helps.")
                : (fr ? "Quitter une app ou fermer des onglets aide." : "Quitting an app or closing tabs helps.")
            return MacHealth(level: memory.pressure == .critical ? .critical : .attention,
                             title: fr ? "Ton Mac manque de mémoire" : "Your Mac is low on memory", message: message, action: .showMemory)
        }
        if let busiest, busiest.averageCPU >= busyThreshold, busiest.minutes >= 2 {
            let message = fr ? "\(busiest.name) utilise beaucoup le processeur depuis \(busiest.minutes) min : ton Mac chauffe et la batterie descend plus vite."
                             : "\(busiest.name) has been using a lot of processor for \(busiest.minutes) min: your Mac heats up and the battery drains faster."
            return MacHealth(level: .attention, title: fr ? "Une app fait travailler ton Mac" : "An app is working your Mac hard",
                             message: message, action: .quit(id: busiest.id, name: busiest.name))
        }
        return MacHealth(level: .good, title: fr ? "Ton Mac est rapide" : "Your Mac is running well",
                         message: fr ? "Assez de mémoire, rien ne s'emballe." : "Enough memory, nothing running away.", action: nil)
    }

    /// Le plus urgent des deux (disque ou vitesse) : un débutant n'a qu'une chose à regarder.
    public static func worst(_ first: MacHealth?, _ second: MacHealth?) -> MacHealth? {
        guard let first else { return second }
        guard let second else { return first }
        func rank(_ health: MacHealth) -> Int {
            switch health.level {
            case .good: return 0
            case .attention: return 1
            case .critical: return 2
            }
        }
        if rank(second) > rank(first) { return second }
        if rank(second) == rank(first), first.level == .good, first.action == nil, second.action != nil { return second }
        return first
    }
}

// MARK: - Alertes en arrière-plan

/// Une notification à envoyer, avec de quoi quitter l'app en cause depuis la notification.
public struct SpeedAlert: Sendable, Equatable {
    public var key: String
    public var title: String
    public var body: String
    public var quitGroupID: String?
    public var quitName: String?
}

/// Quand prévenir (réglage désactivé par défaut) : une app qui s'emballe depuis 5 minutes, la mémoire au rouge,
/// le Mac qui chauffe, une app qui empêche la veille depuis 30 minutes sur batterie. Une même alerte ne revient
/// pas avant une heure.
public enum SpeedAlertPolicy {
    public static let cooldown: TimeInterval = 3600
    public static let busyMinutes = 5
    public static let blockerSeconds = 1800

    public struct Input: Sendable {
        public var busiest: BusyApp?
        public var memory: MemoryStatus
        public var memoryHog: String?
        public var thermal: ThermalLevel
        public var blockers: [SleepBlocker]
        public var onBattery: Bool

        public init(busiest: BusyApp?, memory: MemoryStatus, memoryHog: String?, thermal: ThermalLevel, blockers: [SleepBlocker], onBattery: Bool) {
            self.busiest = busiest
            self.memory = memory
            self.memoryHog = memoryHog
            self.thermal = thermal
            self.blockers = blockers
            self.onBattery = onBattery
        }
    }

    public static func alerts(for input: Input, lastSent: [String: Date], now: Date = Date(), language: Language = Localization.current) -> [SpeedAlert] {
        let fr = language == .fr
        var alerts: [SpeedAlert] = []
        func recent(_ key: String) -> Bool { lastSent[key].map { now.timeIntervalSince($0) < cooldown } ?? false }

        if input.thermal == .hot || input.thermal == .critical, !recent("thermal") {
            var body = fr ? "macOS ralentit le processeur pour le refroidir." : "macOS is slowing the processor to cool it."
            if let busy = input.busiest { body += fr ? " \(busy.name) le fait beaucoup travailler." : " \(busy.name) is working it hard." }
            alerts.append(SpeedAlert(key: "thermal", title: fr ? "Ton Mac chauffe" : "Your Mac is hot", body: body,
                                     quitGroupID: input.busiest?.id, quitName: input.busiest?.name))
        }
        if let busy = input.busiest, busy.averageCPU >= MacHealth.busyThreshold, busy.minutes >= busyMinutes,
           !recent("busy:" + busy.id), !alerts.contains(where: { $0.key == "thermal" }) {
            alerts.append(SpeedAlert(key: "busy:" + busy.id,
                                     title: fr ? "\(busy.name) fait travailler ton Mac" : "\(busy.name) is working your Mac hard",
                                     body: fr ? "Depuis \(busy.minutes) min, il utilise beaucoup le processeur : ton Mac chauffe et la batterie descend plus vite."
                                              : "For \(busy.minutes) min it has used a lot of processor: your Mac heats up and the battery drains faster.",
                                     quitGroupID: busy.id, quitName: busy.name))
        }
        if input.memory.pressure == .critical, !recent("memory") {
            var body = fr ? "Il range des choses sur le disque et devient lent." : "It's storing things on the disk and getting slow."
            if let hog = input.memoryHog { body += fr ? " \(hog) en prend le plus." : " \(hog) uses the most." }
            alerts.append(SpeedAlert(key: "memory", title: fr ? "Ton Mac manque de mémoire" : "Your Mac is low on memory", body: body))
        }
        if input.onBattery {
            for blocker in input.blockers where !blocker.isSystem && blocker.seconds >= blockerSeconds && !recent("blocker:" + blocker.name) {
                let name = blocker.name == "zoom.us" ? "Zoom" : blocker.name
                let minutes = blocker.seconds / 60
                alerts.append(SpeedAlert(key: "blocker:" + blocker.name,
                                         title: fr ? "\(name) empêche ton Mac de dormir" : "\(name) keeps your Mac awake",
                                         body: fr ? "Depuis \(minutes) min, sur batterie. Si tu ne t'en sers plus, quitte-le pour économiser la batterie."
                                                  : "For \(minutes) min, on battery. If you're not using it, quit it to save battery."))
            }
        }
        return alerts
    }
}
