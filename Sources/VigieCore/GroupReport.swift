import Foundation

/// Texte à coller pour signaler un serveur ou un outil bloqué : PID, ports, dossier du projet, durée,
/// commande d'arrêt. Jamais les arguments (ils peuvent contenir des jetons) ; chemins abrégés avec « ~ ».
public enum GroupReport {
    /// Processus à citer en premier : celui qui écoute sur un port, sinon le plus gros (déjà en tête du groupe).
    public static func mainProcess(of group: ProcessGroup) -> RawProcess? {
        group.processes.first { !$0.listeningPorts.isEmpty } ?? group.processes.first
    }

    public static func text(for group: ProcessGroup, in language: Language = Localization.current, now: Date = Date()) -> String {
        let french = language == .fr
        var lines: [String] = []
        if let location = group.location {
            lines.append(group.category == .dev
                         ? "\(group.title) — \(french ? "projet" : "project") \(location)"
                         : "\(group.title) — \(location)")
        } else {
            lines.append(group.title)
        }

        let main = mainProcess(of: group)
        var identity: [String] = []
        if let main { identity.append("PID \(main.pid)") }
        if !group.ports.isEmpty {
            let ports = group.ports.map(String.init).joined(separator: ", ")
            identity.append(group.ports.count == 1 ? "port \(ports)" : "ports \(ports)")
        }
        if !identity.isEmpty { lines.append(identity.joined(separator: " · ")) }

        let others = group.processes.filter { $0.pid != main?.pid }
        if !others.isEmpty {
            let shown = others.prefix(8).map { "\($0.pid) (\($0.name))" }.joined(separator: ", ")
            let more = others.count > 8 ? (french ? ", +\(others.count - 8) autres" : ", +\(others.count - 8) more") : ""
            lines.append((french ? "Autres processus : " : "Other processes: ") + shown + more)
        }

        var started: [String] = []
        if let start = group.startTime {
            started.append((french ? "Lancé " : "Started ") + Format.elapsed(since: start, in: language, now: now))
        }
        if let launcher = group.launchedBy {
            started.append((french ? "depuis " : "from ") + launcher)
        }
        if !started.isEmpty {
            var line = started.joined(separator: " ")
            if started.count == 1 && group.startTime == nil { line = (french ? "Lancé " : "Started ") + line }
            lines.append(line)
        }
        if group.isOrphan {
            lines.append(french ? "Son processus parent a disparu (reste d'une session fermée ?)." : "Its parent process is gone (left over from a closed session?).")
        }

        if let main, !group.isProtected, group.category == .dev || group.category == .background {
            lines.append((french ? "Pour l'arrêter : " : "To stop it: ") + "kill \(main.pid)")
        }
        return lines.joined(separator: "\n")
    }
}
