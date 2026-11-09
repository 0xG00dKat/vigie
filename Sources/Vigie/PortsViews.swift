import AppKit
import SwiftUI
import VigieCore

/// « Le port 3000 est déjà pris » : chaque port en écoute, qui l'occupe (projet, app, conteneur), s'il est visible
/// sur le réseau, et le bouton pour arrêter ce qui le tient (même confirmation que la ligne du processus).
struct PortsPage: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let ports = model.visiblePorts
        let sections = PortSection.split(ports)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PageHeader(title: tr("Ports", "Ports"),
                           subtitle: tr("Qui occupe chaque port de ton Mac. « Le port 3000 est déjà pris » ? Tape 3000 dans la recherche en haut.",
                                        "Who holds each port on your Mac. “Port 3000 is already in use”? Type 3000 in the search at the top."),
                           lesson: "ports") { EmptyView() }
                    .padding(.horizontal, -VigieTheme.pagePadding)
                    .padding(.bottom, -16)

                RelaunchBanner()

                if !model.isSearching, !model.portEntries.isEmpty {
                    HStack(alignment: .top, spacing: 16) {
                        PortCountTile(sections: PortSection.split(model.portEntries))
                        PortExposureTile(entries: model.portEntries)
                        PortOldestTile(entries: model.portEntries)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }

                ForEach(sections) { section in
                    BentoCell {
                        VStack(alignment: .leading, spacing: 0) {
                            HStack(spacing: 8) {
                                Text(section.title).font(.system(size: 14, weight: .semibold))
                                Text(String(section.entries.count))
                                    .font(.system(size: 12, weight: .medium)).monospacedDigit()
                                    .foregroundStyle(.secondary)
                                Spacer()
                            }
                            .padding(.bottom, 6)
                            ForEach(Array(section.entries.enumerated()), id: \.element.id) { index, entry in
                                if index > 0 { Divider().padding(.leading, 74) }
                                PortRow(entry: entry).padding(.horizontal, -12)
                            }
                        }
                    }
                }

                if ports.isEmpty {
                    EmptyPage(text: model.isSearching
                              ? tr("Aucun port ne correspond à « \(model.query) » : il est libre (ou tenu par un service de macOS que Vigie ne peut pas lire).",
                                   "No port matches “\(model.query)”: it's free (or held by a macOS service Vigie can't read).")
                              : tr("Aucun port en écoute pour l'instant.", "No listening port right now."))
                }
                Text(tr("Les ports tenus par des services de macOS lancés en administrateur (root) ne sont pas lisibles sans droits administrateur.",
                        "Ports held by macOS services running as administrator (root) can't be read without admin rights."))
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, VigieTheme.pagePadding)
            .padding(.bottom, WindowGrid.pageBottom)
        }
    }
}

/// Les ports rangés par origine : tes projets, Docker, le reste (apps et macOS).
struct PortSection: Identifiable {
    enum Kind: String { case dev, docker, other }
    let kind: Kind
    let entries: [PortEntry]
    var id: String { kind.rawValue }

    var title: String {
        switch kind {
        case .dev: return tr("Tes projets et outils de dev", "Your projects and dev tools")
        case .docker: return tr("Conteneurs Docker", "Docker containers")
        case .other: return tr("Apps et macOS", "Apps and macOS")
        }
    }

    static func kind(_ entry: PortEntry) -> Kind {
        if entry.containerID != nil || entry.container != nil { return .docker }
        return entry.category == .dev ? .dev : .other
    }

    static func split(_ entries: [PortEntry]) -> [PortSection] {
        [Kind.dev, .docker, .other].compactMap { kind in
            let matching = entries.filter { Self.kind($0) == kind }
            return matching.isEmpty ? nil : PortSection(kind: kind, entries: matching)
        }
    }
}

/// Combien de ports sont ouverts, et à qui.
private struct PortCountTile: View {
    let sections: [PortSection]

    var body: some View {
        let total = sections.reduce(0) { $0 + $1.entries.count }
        let parts = sections.map { section -> String in
            let count = section.entries.count
            switch section.kind {
            case .dev: return tr("\(count) de tes projets", "\(count) from your projects")
            case .docker: return tr("\(count) de Docker", "\(count) from Docker")
            case .other: return tr("\(count) d'apps et de macOS", "\(count) from apps and macOS")
            }
        }
        TopTile(symbol: "point.3.connected.trianglepath.dotted", tint: .green,
                title: tr("\(total) port\(total > 1 ? "s" : "") en écoute", "\(total) listening port\(total > 1 ? "s" : "")"),
                text: parts.joined(separator: " · ")) { EmptyView() }
    }
}

/// Ce que les autres appareils du Wi-Fi peuvent joindre. Orange seulement pour tes serveurs de dev :
/// AirPlay et les apps qui partagent volontairement restent une information.
private struct PortExposureTile: View {
    let entries: [PortEntry]

    var body: some View {
        let exposed = entries.filter(\.isExposed)
        let dev = exposed.filter { $0.category == .dev && PortSection.kind($0) != .docker }
        let names = Array(Set(dev.map { $0.groupTitle ?? $0.processName })).sorted()
        if !dev.isEmpty {
            TopTile(symbol: "wifi", tint: .orange,
                    title: tr("\(names.joined(separator: ", ")) visible sur le Wi-Fi", "\(names.joined(separator: ", ")) visible on the Wi-Fi"),
                    text: PortMap.exposedAdvice.text) { EmptyView() }
        } else {
            TopTile(symbol: "lock", tint: .green,
                    title: tr("Tes projets restent sur ce Mac", "Your projects stay on this Mac"),
                    text: exposed.isEmpty
                        ? tr("Aucun port n'est joignable depuis le réseau.", "No port can be reached from the network.")
                        : tr("\(exposed.count) port\(exposed.count > 1 ? "s" : "") visible\(exposed.count > 1 ? "s" : "") sur le réseau, tous tenus par des apps ou par macOS (AirPlay…).",
                             "\(exposed.count) port\(exposed.count > 1 ? "s" : "") visible on the network, all held by apps or macOS (AirPlay…).")) { EmptyView() }
        }
    }
}

/// Le serveur ouvert depuis le plus longtemps : souvent celui qu'on a oublié.
private struct PortOldestTile: View {
    let entries: [PortEntry]

    var body: some View {
        let candidates = entries.filter { $0.startTime != nil && PortSection.kind($0) != .other }
        if let oldest = candidates.min(by: { $0.startTime! < $1.startTime! }), let start = oldest.startTime {
            let days = Date().timeIntervalSince(start) / 86_400
            TopTile(symbol: "clock", tint: days >= 7 ? .orange : .green,
                    title: tr("\(oldest.container ?? oldest.groupTitle ?? oldest.processName) tourne \(Format.uptime(since: start))",
                              "\(oldest.container ?? oldest.groupTitle ?? oldest.processName) running \(Format.uptime(since: start))"),
                    text: days >= 7
                        ? tr("Le plus ancien serveur ouvert (port \(oldest.port)). Si tu ne t'en sers plus, arrête-le dans la liste.",
                             "The oldest open server (port \(oldest.port)). If you no longer use it, stop it in the list.")
                        : tr("Le plus ancien serveur ouvert (port \(oldest.port)) : rien d'oublié depuis des jours.",
                             "The oldest open server (port \(oldest.port)): nothing left running for days.")) { EmptyView() }
        }
    }
}

/// Encadré orange : des serveurs de dev sont joignables depuis le Wi-Fi.
struct ExposedWarning: View {
    let entries: [PortEntry]

    var body: some View {
        let names = Array(Set(entries.map { $0.groupTitle ?? $0.processName })).sorted()
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 4) {
                Text(tr("Visible sur le Wi-Fi : \(names.joined(separator: ", "))", "Visible on the Wi-Fi: \(names.joined(separator: ", "))"))
                    .font(.system(size: 13, weight: .semibold))
                Text(PortMap.exposedAdvice.text)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.orange.opacity(0.09)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.orange.opacity(0.3), lineWidth: 0.5))
    }
}

struct PortRow: View {
    @Environment(AppModel.self) private var model
    let entry: PortEntry
    @State private var hovering = false

    var body: some View {
        let group = entry.groupID.flatMap { model.group(withID: $0) }
        HStack(alignment: .top, spacing: 12) {
            Button {
                if let url = URL(string: "http://localhost:\(entry.port)") { NSWorkspace.shared.open(url) }
            } label: {
                Text(String(entry.port))
                    .font(.system(size: 15, weight: .semibold, design: .monospaced))
                    .frame(width: 62, alignment: .leading)
                    .foregroundStyle(VigieTheme.accent)
            }
            .buttonStyle(.plain)
            .help(tr("Ouvrir http://localhost:\(entry.port)", "Open http://localhost:\(entry.port)"))
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    Text(entry.container ?? entry.groupTitle ?? entry.processName)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    // Seule l'exception se signale : « ce Mac seulement » est le cas normal, inutile de le répéter partout.
                    if entry.isExposed { ExposureBadge(exposed: true) }
                }
                Text(details)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if entry.containerID == nil, let job = model.relauncher(forPID: entry.pid) { RelaunchLine(job: job) }
                if let known = entry.knownUse {
                    Text(known.text)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            if let id = entry.containerID {
                // Un port publié par un conteneur : on arrête le conteneur, pas Docker.
                CloseControl(key: "docker:c:" + id, verb: tr("Arrêter", "Stop")) {
                    model.stopDocker("docker:c:" + id, ids: [id])
                }
                .help(tr("Arrêter ce conteneur libère le port \(entry.port)", "Stopping this container frees port \(entry.port)"))
            } else if let job = model.relauncher(forPID: entry.pid) {
                KeepAliveMenu(job: job, group: group)
            } else if let group, group.close.isAllowed, !group.isProtected {
                CloseControl(key: group.id, verb: group.category == .dev ? tr("Arrêter", "Stop") : tr("Quitter", "Quit")) {
                    model.confirmClose(group.id, methods: [group.close])
                }
                .help(tr("Arrêter \(group.title) libère le port \(entry.port)", "Stopping \(group.title) frees port \(entry.port)"))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(hovering ? Color.primary.opacity(0.04) : .clear)
        .onHover { hovering = $0 }
        .contextMenu {
            Button(tr("Copier le PID (\(entry.pid))", "Copy PID (\(entry.pid))")) { copy(String(entry.pid)) }
            Button(tr("Copier « lsof -i :\(entry.port) »", "Copy “lsof -i :\(entry.port)”")) { copy("lsof -i :\(entry.port)") }
        }
    }

    private var details: String {
        var parts: [String] = []
        if entry.container != nil { parts.append(tr("conteneur Docker", "Docker container")) }
        parts.append(entry.processName)
        parts.append("PID \(entry.pid)")
        if let start = entry.startTime { parts.append(Format.uptime(since: start)) }
        if let location = entry.location, !location.hasPrefix("/System") { parts.append(location) }
        return parts.joined(separator: " · ")
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

/// « réseau » en orange (joignable depuis le Wi-Fi), « ce Mac » en gris.
struct ExposureBadge: View {
    let exposed: Bool

    var body: some View {
        Label(exposed ? tr("visible sur le réseau", "visible on the network") : tr("ce Mac seulement", "this Mac only"),
              systemImage: exposed ? "wifi" : "lock")
            .font(.system(size: 9.5, weight: .medium))
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(Capsule().fill((exposed ? Color.orange : Color.gray).opacity(0.15)))
            .foregroundStyle(exposed ? Color.orange : Color.secondary)
            .fixedSize()
            .help(exposed ? PortMap.exposedAdvice.text
                          : tr("Écoute sur 127.0.0.1 : seul ce Mac peut s'y connecter.", "Listens on 127.0.0.1: only this Mac can connect."))
    }
}
