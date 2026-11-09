import Darwin
import Foundation

/// Qui occupe quel port : « le port 3000 est déjà pris » trouve sa réponse, avec le moyen de l'arrêter.
///
/// Tous les processus de l'utilisateur sont lus (ceux de root ne le sont pas sans droits administrateur).
/// Un port publié par un conteneur Docker est rattaché au conteneur plutôt qu'au moteur de Docker.
public struct PortEntry: Sendable, Identifiable, Equatable {
    public var id: String { "\(port)-\(pid)" }
    public var port: Int
    /// Adresses d'écoute (127.0.0.1, 0.0.0.0, ::…).
    public var addresses: [String]
    public var pid: Int32
    public var processName: String
    /// Groupe de Vigie qui contient ce processus (pour l'arrêter avec le même bouton que sa ligne).
    public var groupID: String?
    public var groupTitle: String?
    /// Dossier du projet (dev) ou emplacement de l'app.
    public var location: String?
    public var category: ProcessCategory?
    public var startTime: Date?
    /// Conteneur Docker qui publie ce port (« api-1 (shop) »).
    public var container: String?
    /// Son identifiant, pour l'arrêter seul (et pas tout Docker).
    public var containerID: String?

    public init(port: Int, addresses: [String], pid: Int32, processName: String, groupID: String? = nil, groupTitle: String? = nil,
                location: String? = nil, category: ProcessCategory? = nil, startTime: Date? = nil, container: String? = nil,
                containerID: String? = nil) {
        self.port = port
        self.addresses = addresses
        self.pid = pid
        self.processName = processName
        self.groupID = groupID
        self.groupTitle = groupTitle
        self.location = location
        self.category = category
        self.startTime = startTime
        self.container = container
        self.containerID = containerID
    }

    /// Joignable par les autres appareils du même réseau (Wi-Fi d'un café, d'un bureau…).
    public var isExposed: Bool {
        addresses.contains { !ListeningSocket(port: port, address: $0).isLoopback }
    }

    /// Pourquoi ce port est connu (AirPlay sur 5000 et 7000…), quand Vigie le sait.
    public var knownUse: L? { PortMap.knownUse(port: port, processName: processName) }
}

public enum PortMap {
    /// Lit les ports de tous les processus de l'utilisateur et les rattache à leur groupe.
    public static func scan(groups: [ProcessGroup], containers: [DockerContainer] = []) -> [PortEntry] {
        let uid = getuid()
        return build(groups: groups, containers: containers) { process in
            process.uid == uid ? ProcessSampler.listeningSockets(process.pid) : []
        }
    }

    public static func build(groups: [ProcessGroup], containers: [DockerContainer] = [],
                             sockets: (RawProcess) -> [ListeningSocket]) -> [PortEntry] {
        var entries: [PortEntry] = []
        var seen = Set<Int32>()
        for group in groups {
            for process in group.processes where seen.insert(process.pid).inserted {
                let found = sockets(process)
                guard !found.isEmpty else { continue }
                for port in Array(Set(found.map(\.port))).sorted() {
                    let published = containers.first { $0.ports.contains(port) }
                    let container = published.map { container in
                        container.project.map { "\(container.name) (\($0))" } ?? container.name
                    }
                    entries.append(PortEntry(port: port, addresses: found.filter { $0.port == port }.map(\.address).sorted(),
                                             pid: process.pid, processName: process.name, groupID: group.id, groupTitle: group.title,
                                             location: group.location, category: group.category, startTime: process.startTime,
                                             container: container, containerID: published?.id))
                }
            }
        }
        return entries.sorted { ($0.port, $0.pid) < ($1.port, $1.pid) }
    }

    /// Ports que macOS ou des outils connus prennent souvent, et qui surprennent.
    public static func knownUse(port: Int, processName: String) -> L? {
        let name = processName.lowercased()
        if (port == 5000 || port == 7000) && name.contains("controlcenter") {
            return L("Récepteur AirPlay de macOS. Pour libérer le port : Réglages Système › Général › AirDrop et Handoff › Récepteur AirPlay.",
                     "macOS AirPlay Receiver. To free the port: System Settings › General › AirDrop & Handoff › AirPlay Receiver.")
        }
        if name.contains("rapportd") || name.contains("sharingd") {
            return L("Service de macOS pour Handoff et le partage entre tes appareils Apple.",
                     "macOS service for Handoff and sharing between your Apple devices.")
        }
        return nil
    }

    /// Conseil pour un serveur de dev visible sur le réseau.
    public static let exposedAdvice = L(
        "Il écoute sur toutes les adresses : les autres appareils du même Wi-Fi peuvent s'y connecter. Si ce n'est pas voulu, lance-le avec l'hôte 127.0.0.1 (par exemple --host 127.0.0.1).",
        "It listens on every address: other devices on the same Wi-Fi can connect to it. If that's not intended, start it with host 127.0.0.1 (for example --host 127.0.0.1).")
}
