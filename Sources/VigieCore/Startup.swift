import Foundation

/// Ce qui démarre tout seul avec le Mac : agents de lancement et aides d'apps, reliés à leur app et expliqués.
/// Seuls tes agents (`~/Library/LaunchAgents`) se coupent depuis Vigie, sans mot de passe et de façon réversible ;
/// le reste se gère dans Réglages Système › Général › Ouverture. Jamais ce qui vient d'Apple.
public struct StartupItem: Sendable, Equatable, Identifiable {
    public enum Scope: Sendable, Equatable {
        /// Tes agents : `~/Library/LaunchAgents`. Se coupent depuis Vigie.
        case user
        /// Pour tous les utilisateurs : `/Library/LaunchAgents`.
        case allUsers
        /// Services du Mac : `/Library/LaunchDaemons` (mot de passe administrateur).
        case system
        /// Aide déclarée par une app (« Éléments en arrière-plan » de macOS).
        case appHelper
    }

    public enum Kind: Sendable, Equatable {
        case updater, helper, script, service
    }

    public var id: String { label }
    public var label: String
    public var scope: Scope
    public var plistPath: String?
    public var program: String?
    public var ownerName: String?
    public var ownerPath: String?
    public var kind: Kind
    public var pid: Int32?
    public var isEnabled: Bool

    public var isRunning: Bool { pid != nil }
    public var canToggle: Bool { scope == .user && plistPath != nil }

    /// Ce que c'est, en une phrase.
    public var explanation: L {
        let owner = ownerName ?? ""
        switch kind {
        case .updater:
            return owner.isEmpty ? L("Cherche des mises à jour en arrière-plan.", "Checks for updates in the background.")
                                 : L("Cherche les mises à jour de \(owner) en arrière-plan.", "Checks for \(owner) updates in the background.")
        case .helper:
            return L("Aide de \(owner) : elle s'en sert en arrière-plan (icône de la barre des menus, synchronisation…).",
                     "\(owner)'s helper: it uses it in the background (menu bar icon, sync…).")
        case .script:
            return L("Un programme lancé à l'ouverture de ta session, sans app : créé par toi ou par un outil installé.",
                     "A program started when you log in, without an app: created by you or by an installed tool.")
        case .service:
            return owner.isEmpty ? L("Service qui tourne pour tout le Mac.", "A service running for the whole Mac.")
                                 : L("Service de \(owner) pour tout le Mac.", "\(owner)'s service for the whole Mac.")
        }
    }

    /// Nom à afficher : l'app, ou la fin de l'étiquette.
    public var displayName: String {
        if let ownerName {
            switch kind {
            case .updater: return L("Mises à jour de \(ownerName)", "\(ownerName) updates").text
            default: return ownerName
            }
        }
        return label.split(separator: ".").suffix(2).joined(separator: ".")
    }
}

/// Une app installée (identifiant, nom, chemin).
public struct InstalledApp: Sendable, Equatable {
    public var id: String
    public var name: String
    public var path: String

    public init(id: String, name: String, path: String) {
        self.id = id
        self.name = name
        self.path = path
    }
}

public enum StartupReader {
    public static func read(home: String = NSHomeDirectory(), apps: [InstalledApp] = InstalledApps.all()) -> [StartupItem] {
        let uid = getuid()
        let running = parseList(run("/bin/launchctl", ["list"]))
        let overrides = parseDisabled(run("/bin/launchctl", ["print-disabled", "gui/\(uid)"]))
        var items: [StartupItem] = []
        var seen = Set<String>()
        let folders: [(String, StartupItem.Scope)] = [(home + "/Library/LaunchAgents", .user), ("/Library/LaunchAgents", .allUsers),
                                                      ("/Library/LaunchDaemons", .system)]
        for (folder, scope) in folders {
            for name in ((try? FileManager.default.contentsOfDirectory(atPath: folder)) ?? []).sorted() where name.hasSuffix(".plist") {
                let path = folder + "/" + name
                guard let plist = NSDictionary(contentsOfFile: path) as? [String: Any], let label = plist["Label"] as? String,
                      !label.hasPrefix("com.apple."), seen.insert(label).inserted else { continue }
                let program = (plist["Program"] as? String) ?? (plist["ProgramArguments"] as? [String])?.first
                let owner = owner(label: label, program: program, apps: apps)
                let disabled = overrides[label] == false || (plist["Disabled"] as? Bool ?? false) && overrides[label] != true
                items.append(StartupItem(label: label, scope: scope, plistPath: path, program: program, ownerName: owner?.name,
                                         ownerPath: owner?.path, kind: kind(label: label, program: program, owner: owner, scope: scope, home: home),
                                         pid: running[label] ?? nil, isEnabled: !disabled))
            }
        }
        // Aides déclarées par des apps : elles apparaissent dans les réglages de lancement de ta session.
        // (Pas Vigie elle-même : ses réglages de lancement se gèrent dans son menu ⚙︎.)
        for (label, enabled) in overrides.sorted(by: { $0.key < $1.key })
        where !label.hasPrefix("com.apple.") && !label.hasPrefix("io.github.0xg00dkat.vigie") && !seen.contains(label) {
            guard let owner = owner(label: label, program: nil, apps: apps) else { continue }
            seen.insert(label)
            items.append(StartupItem(label: label, scope: .appHelper, plistPath: nil, program: nil, ownerName: owner.name, ownerPath: owner.path,
                                     kind: kind(label: label, program: nil, owner: owner, scope: .appHelper, home: home),
                                     pid: running[label] ?? nil, isEnabled: enabled))
        }
        return items
    }

    /// Sortie de `launchctl list` : « PID  Statut  Étiquette », PID « - » pour ce qui ne tourne pas.
    public static func parseList(_ text: String) -> [String: Int32?] {
        var result: [String: Int32?] = [:]
        for line in text.split(separator: "\n").dropFirst() {
            let parts = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard parts.count >= 3 else { continue }
            result[String(parts[2])] = Int32(parts[0])
        }
        return result
    }

    /// Sortie de `launchctl print-disabled` : `"étiquette" => enabled|disabled`.
    public static func parseDisabled(_ text: String) -> [String: Bool] {
        var result: [String: Bool] = [:]
        for line in text.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("\""), let close = trimmed.dropFirst().firstIndex(of: "\"") else { continue }
            let label = String(trimmed[trimmed.index(after: trimmed.startIndex)..<close])
            if trimmed.hasSuffix("enabled") { result[label] = true } else if trimmed.hasSuffix("disabled") { result[label] = false }
        }
        return result
    }

    /// L'app qui a installé l'agent : celle qui contient le programme, sinon celle dont l'identifiant commence
    /// l'étiquette (« com.bjango.istatmenus.agent » → iStat Menus), sinon un même éditeur (« com.docker.socket » → Docker).
    public static func owner(label: String, program: String?, apps: [InstalledApp]) -> InstalledApp? {
        if let program, let range = program.range(of: ".app/") {
            let bundle = String(program[..<range.lowerBound]) + ".app"
            if let app = apps.first(where: { $0.path == bundle }) { return app }
            let name = (bundle as NSString).lastPathComponent.replacingOccurrences(of: ".app", with: "")
            return InstalledApp(id: "", name: name, path: bundle)
        }
        let lower = label.lowercased()
        if let app = apps.filter({ !$0.id.isEmpty && lower.hasPrefix($0.id.lowercased()) }).max(by: { $0.id.count < $1.id.count }) {
            return app
        }
        let vendor = lower.split(separator: ".").prefix(2).joined(separator: ".")
        let sameVendor = apps.filter { $0.id.lowercased().split(separator: ".").prefix(2).joined(separator: ".") == vendor }
        return sameVendor.count == 1 ? sameVendor.first : nil
    }

    public static func kind(label: String, program: String?, owner: InstalledApp?, scope: StartupItem.Scope, home: String) -> StartupItem.Kind {
        let text = (label + " " + (program ?? "")).lowercased()
        if ["update", "shipit", "keystone", "sparkle"].contains(where: { text.contains($0) }) { return .updater }
        if owner == nil { return scope == .system ? .service : .script }
        return scope == .system ? .service : .helper
    }

    static func run(_ tool: String, _ arguments: [String]) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return "" }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }
}

/// Un service de lancement réglé pour être relancé dès qu'il s'arrête (`KeepAlive`) : le fermer ne sert à rien,
/// macOS le relance quelques secondes plus tard. On le lit à chaque actualisation : `launchctl list` et les quelques
/// fichiers des dossiers LaunchAgents, sans chercher l'app propriétaire (trop lent).
public struct KeepAliveJob: Sendable, Equatable, Identifiable {
    public var id: String { label }
    public var label: String
    public var plistPath: String
    public var pid: Int32
    /// Tes agents : Vigie peut les arrêter. Ceux de /Library : Réglages Système › Général › Ouverture.
    public var isUser: Bool
    /// Délai avant relance (`ThrottleInterval`, 10 s par défaut chez macOS).
    public var throttle: Int

    public init(label: String, plistPath: String, pid: Int32, isUser: Bool, throttle: Int = 10) {
        self.label = label
        self.plistPath = plistPath
        self.pid = pid
        self.isUser = isUser
        self.throttle = throttle
    }

    /// Nom lisible : « com.example.ledger » → « ledger ».
    public var shortName: String { label.split(separator: ".").last.map(String.init) ?? label }

    /// `KeepAlive` vaut `true`, ou un dictionnaire de conditions (relance selon l'état) : dans les deux cas, il revient.
    public static func keepsAlive(_ value: Any?) -> Bool {
        if let flag = value as? Bool { return flag }
        if let conditions = value as? [String: Any] { return !conditions.isEmpty }
        return false
    }

    public static func read(home: String = NSHomeDirectory()) -> [KeepAliveJob] {
        let running = StartupReader.parseList(StartupReader.run("/bin/launchctl", ["list"]))
        return parse(running: running, folders: [(home + "/Library/LaunchAgents", true), ("/Library/LaunchAgents", false)])
    }

    static func parse(running: [String: Int32?], folders: [(String, Bool)]) -> [KeepAliveJob] {
        var jobs: [KeepAliveJob] = []
        for (folder, isUser) in folders {
            for name in ((try? FileManager.default.contentsOfDirectory(atPath: folder)) ?? []) where name.hasSuffix(".plist") {
                let path = folder + "/" + name
                guard let plist = NSDictionary(contentsOfFile: path) as? [String: Any], let label = plist["Label"] as? String,
                      keepsAlive(plist["KeepAlive"]), let pid = running[label] ?? nil else { continue }
                jobs.append(KeepAliveJob(label: label, plistPath: path, pid: pid, isUser: isUser,
                                         throttle: plist["ThrottleInterval"] as? Int ?? 10))
            }
        }
        return jobs
    }
}

/// Couper ou relancer un de tes agents : arrêté tout de suite, et ne revient plus à l'ouverture de session.
/// Réversible : réactiver le relance.
public enum StartupControl {
    public static func setEnabled(_ item: StartupItem, _ enabled: Bool) -> String? {
        guard item.canToggle, let plist = item.plistPath else { return "Not a user agent" }
        let domain = "gui/\(getuid())"
        if enabled {
            _ = StartupReader.run("/bin/launchctl", ["enable", "\(domain)/\(item.label)"])
            _ = StartupReader.run("/bin/launchctl", ["bootstrap", domain, plist])
        } else {
            _ = StartupReader.run("/bin/launchctl", ["bootout", domain, plist])
            _ = StartupReader.run("/bin/launchctl", ["disable", "\(domain)/\(item.label)"])
        }
        let state = StartupReader.parseDisabled(StartupReader.run("/bin/launchctl", ["print-disabled", domain]))[item.label]
        return state == enabled ? nil : "launchctl"
    }

    /// Arrête un service qui se relance tout seul. `forGood` : il ne revient pas non plus à l'ouverture de session
    /// (comme l'interrupteur de « Ce qui démarre avec ton Mac », réversible). Sinon il revient au prochain démarrage.
    public static func stop(_ job: KeepAliveJob, forGood: Bool) -> String? {
        guard job.isUser else { return "Not a user agent" }
        let domain = "gui/\(getuid())"
        _ = StartupReader.run("/bin/launchctl", ["bootout", domain, job.plistPath])
        if forGood { _ = StartupReader.run("/bin/launchctl", ["disable", "\(domain)/\(job.label)"]) }
        let stillRunning = (StartupReader.parseList(StartupReader.run("/bin/launchctl", ["list"]))[job.label] ?? nil) != nil
        return stillRunning ? "launchctl" : nil
    }
}

/// Les apps installées : celles que Spotlight connaît, plus /Applications et ~/Applications.
public enum InstalledApps {
    public static func all(home: String = NSHomeDirectory()) -> [InstalledApp] {
        var paths = Set<String>()
        StartupReader.run("/usr/bin/mdfind", ["kMDItemContentType == 'com.apple.application-bundle'"])
            .split(separator: "\n").forEach { paths.insert(String($0)) }
        for folder in ["/Applications", "/Applications/Utilities", "/System/Applications", home + "/Applications"] {
            for name in (try? FileManager.default.contentsOfDirectory(atPath: folder)) ?? [] where name.hasSuffix(".app") {
                paths.insert(folder + "/" + name)
            }
        }
        return paths.compactMap { path in
            guard let info = NSDictionary(contentsOfFile: path + "/Contents/Info.plist") as? [String: Any],
                  let id = info["CFBundleIdentifier"] as? String else { return nil }
            return InstalledApp(id: id, name: PathRules.bundleDisplayName(path), path: path)
        }
    }
}
