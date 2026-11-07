import AppKit
import SwiftUI
import VigieCore

// MARK: - Disque

struct DiskGauge: View {
    let disk: DiskStatus

    var body: some View {
        let used = 1 - disk.freeRatio
        let color: Color = disk.isLow ? .red : disk.isTight ? .orange : .green
        HStack(spacing: 6) {
            Text(tr("Disque \(Format.bytes(disk.available, decimal: true)) libres", "Disk \(Format.bytes(disk.available, decimal: true)) free"))
                .font(.system(size: 11))
                .monospacedDigit()
                .foregroundStyle(disk.isLow ? Color.red : Color.secondary)
            Capsule()
                .fill(Color.primary.opacity(0.12))
                .frame(width: 44, height: 5)
                .overlay(alignment: .leading) {
                    Capsule().fill(color).frame(width: 44 * min(1, used), height: 5)
                }
        }
        .help(tr(
            "Espace libre sur le disque du Mac : \(Format.bytes(disk.available, decimal: true)) sur \(Format.bytes(disk.total, decimal: true)) (\(disk.freePercent) %). Vigie prévient sous 15 %.",
            "Free space on the Mac's disk: \(Format.bytes(disk.available, decimal: true)) of \(Format.bytes(disk.total, decimal: true)) (\(disk.freePercent)%). Vigie warns you below 15%."
        ))
    }
}

/// Bandeau en haut de la liste quand il reste moins de 15 % d'espace.
struct LowDiskBanner: View {
    @Environment(AppModel.self) private var model
    let disk: DiskStatus

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "externaldrive.fill.badge.exclamationmark")
                .foregroundStyle(.red)
                .font(.system(size: 15))
            VStack(alignment: .leading, spacing: 2) {
                Text(tr("Disque presque plein", "Disk almost full"))
                    .font(.system(size: 12, weight: .semibold))
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.red.opacity(0.10)))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.red.opacity(0.35)))
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var message: String {
        let free = Format.bytes(disk.available, decimal: true)
        var text = tr("Il reste \(disk.freePercent) % d'espace libre (\(free)).", "Only \(disk.freePercent)% free space left (\(free)).")
        if let docker = model.docker?.virtualDisk {
            let size = Format.bytes(docker.allocated, decimal: true)
            text += " " + tr("Docker en occupe \(size) : voir la section Docker.", "Docker uses \(size): see the Docker section.")
        }
        return text
    }
}

// MARK: - Docker

enum DockerIcon {
    static let appPath = "/Applications/Docker.app"
}

struct DockerSectionView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let docker = model.docker, docker.state != .notInstalled {
            let groups = model.visibleDockerGroups
            if !model.isSearching || !groups.isEmpty {
                Section {
                    if model.isDockerOpen {
                        switch docker.state {
                        case .running:
                            ForEach(groups) { group in
                                DockerGroupRow(group: group)
                                Divider().padding(.leading, 50)
                            }
                            if groups.isEmpty {
                                Text(tr("Aucun conteneur en cours.", "No running containers."))
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                            }
                        case .notRunning:
                            DockerStoppedRow(docker: docker)
                        case .notInstalled:
                            EmptyView()
                        }
                        if let error = model.dockerError {
                            Text(error)
                                .font(.system(size: 11))
                                .foregroundStyle(.red)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 4)
                        }
                        if !model.isSearching {
                            DockerDiskBlock(docker: docker)
                        }
                    }
                } header: {
                    DockerSectionHeader(docker: docker, groups: groups)
                }
            }
        }
    }
}

struct DockerSectionHeader: View {
    @Environment(AppModel.self) private var model
    let docker: DockerStatus
    let groups: [DockerGroup]

    var body: some View {
        @Bindable var model = model
        let open = model.isDockerOpen
        HStack(spacing: 6) {
            Button {
                model.dockerCollapsed.toggle()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8.5, weight: .bold))
                        .rotationEffect(.degrees(open ? 90 : 0))
                        .frame(width: 10)
                    Text("DOCKER")
                        .font(.system(size: 10.5, weight: .semibold))
                    if docker.state == .running {
                        Text("\(docker.containers.count)")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                        if docker.memory > 0 {
                            Text("· \(Format.bytes(docker.memory))")
                                .font(.system(size: 10.5))
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text(tr("· arrêté", "· stopped"))
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(tr(
                "Conteneurs Docker en cours et place prise par Docker sur le disque.",
                "Running Docker containers and the disk space Docker uses."
            ))

            Spacer()

            if docker.state == .running && docker.containers.count > 1 {
                DockerStopAllButton(ids: docker.containers.map(\.id))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
    }
}

struct DockerStopAllButton: View {
    @Environment(AppModel.self) private var model
    let ids: [String]

    var body: some View {
        let key = "docker:section"
        let verb = tr("Tout arrêter", "Stop all")
        switch model.closeState(key) {
        case .confirming?:
            HStack(spacing: 4) {
                Button(tr("\(verb) (\(ids.count)) ?", "\(verb) (\(ids.count))?")) {
                    model.stopDocker(key, ids: ids)
                }
                .buttonStyle(DangerButtonStyle())
                Button(tr("Annuler", "Cancel")) { model.cancelConfirmation(key) }
                    .buttonStyle(.borderless)
            }
            .controlSize(.mini)
        case .closing?, .stuck?:
            ProgressView().controlSize(.mini)
        case nil:
            Button(verb) { model.requestConfirmation(key) }
                .buttonStyle(.borderless)
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
        }
    }
}

struct DockerAppIcon: View {
    var body: some View {
        if FileManager.default.fileExists(atPath: DockerIcon.appPath) {
            Image(nsImage: IconCache.icon(for: DockerIcon.appPath))
                .resizable()
                .interpolation(.high)
                .frame(width: 28, height: 28)
        } else {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.blue.gradient)
                .frame(width: 26, height: 26)
                .overlay {
                    Image(systemName: "shippingbox.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .padding(1)
        }
    }
}

struct DockerGroupRow: View {
    @Environment(AppModel.self) private var model
    let group: DockerGroup
    @State private var hovering = false

    var body: some View {
        let expanded = model.expandedGroups.contains(group.id)
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 10) {
                DockerAppIcon()
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Text(group.title)
                            .font(.system(size: 12.5, weight: .semibold))
                            .lineLimit(1)
                        ForEach(group.ports.prefix(3), id: \.self) { PortBadge(port: $0) }
                    }
                    Text(explanation)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(expanded ? nil : 2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(metaLine)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                HStack(spacing: 8) {
                    if group.memory > 0 {
                        Text(Format.bytes(group.memory))
                            .font(.system(size: 11.5, weight: .medium))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    CloseControl(key: group.id, verb: tr("Arrêter", "Stop")) {
                        model.stopDocker(group.id, ids: group.containers.map(\.id))
                    }
                }
                .padding(.top, 1)
            }
            if expanded {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(group.containers) { container in
                        HStack(spacing: 6) {
                            Text(container.service ?? container.name)
                                .font(.system(size: 11, weight: .medium))
                                .lineLimit(1)
                            Text(container.image)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer(minLength: 4)
                            ForEach(container.ports.prefix(2), id: \.self) { PortBadge(port: $0) }
                            if let memory = container.memory {
                                Text(Format.bytes(memory))
                                    .font(.system(size: 10.5))
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                            if group.containers.count > 1 {
                                CloseControl(key: "docker:c:" + container.id, verb: tr("Arrêter", "Stop")) {
                                    model.stopDocker("docker:c:" + container.id, ids: [container.id])
                                }
                                .scaleEffect(0.85)
                            }
                        }
                        .frame(minHeight: 18)
                        .help(container.name)
                    }
                }
                .padding(6)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.04)))
                .padding(.leading, 38)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .background(hovering ? Color.primary.opacity(0.045) : Color.clear)
        .onHover { hovering = $0 }
        .onTapGesture { model.toggleExpanded(group.id) }
    }

    private var explanation: String {
        if group.project != nil {
            let services = group.containers.map { $0.service ?? $0.name }.joined(separator: ", ")
            let count = group.containers.count
            return tr(
                "Projet Docker Compose : \(count) conteneur\(count > 1 ? "s" : "") (\(services)).",
                "Docker Compose project: \(count) container\(count > 1 ? "s" : "") (\(services))."
            )
        }
        let image = group.containers.first?.image ?? "?"
        return tr("Conteneur Docker de l'image \(image).", "Docker container from the \(image) image.")
    }

    private var metaLine: String {
        var parts: [String] = []
        if let cpu = Format.cpu(group.cpuPercent) { parts.append(cpu) }
        if let start = group.startedAt { parts.append(Format.uptime(since: start)) }
        return parts.joined(separator: " · ")
    }
}

struct DockerStoppedRow: View {
    let docker: DockerStatus

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            DockerAppIcon()
            VStack(alignment: .leading, spacing: 2) {
                Text(tr("Docker est arrêté", "Docker is not running"))
                    .font(.system(size: 12.5, weight: .semibold))
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var detail: String {
        guard let disk = docker.virtualDisk else {
            return tr("Aucun conteneur ne tourne.", "No containers are running.")
        }
        let size = Format.bytes(disk.allocated, decimal: true)
        return tr(
            "Aucun conteneur ne tourne. Son disque virtuel (\(disk.engine)) occupe quand même \(size) sur ton Mac.",
            "No containers are running. Its virtual disk (\(disk.engine)) still uses \(size) on your Mac."
        )
    }
}

/// Place prise par Docker, et les commandes de nettoyage à copier. Vigie ne supprime rien elle-même.
struct DockerDiskBlock: View {
    let docker: DockerStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(tr("Espace disque de Docker", "Docker disk space"))
                .font(.system(size: 11, weight: .semibold))
            if let virtual = docker.virtualDisk {
                DiskLine(
                    label: tr("Disque virtuel sur le Mac", "Virtual disk on the Mac"),
                    value: Format.bytes(virtual.allocated, decimal: true),
                    note: tr("maximum \(Format.bytes(virtual.maximum, decimal: true))", "up to \(Format.bytes(virtual.maximum, decimal: true))")
                )
                .help(virtual.path)
            }
            if let usage = docker.disk {
                DiskLine(
                    label: tr("Images", "Images"),
                    value: Format.bytes(usage.images.size, decimal: true),
                    note: reclaimable(usage.images.reclaimable)
                )
                DiskLine(
                    label: tr("Conteneurs arrêtés", "Stopped containers"),
                    value: "\(docker.stoppedContainers)",
                    note: reclaimable(usage.containers.reclaimable)
                )
                DiskLine(
                    label: tr("Volumes", "Volumes"),
                    value: Format.bytes(usage.volumes.size, decimal: true),
                    note: tr("tes données : Vigie n'y touche jamais", "your data: Vigie never touches them")
                )
                DiskLine(
                    label: tr("Cache de construction", "Build cache"),
                    value: Format.bytes(usage.buildCache.size, decimal: true),
                    note: reclaimable(usage.buildCache.reclaimable)
                )
                let suggestions = cleanups(usage)
                if !suggestions.isEmpty {
                    Text(tr("À nettoyer", "Worth cleaning"))
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.top, 4)
                    ForEach(suggestions, id: \.command) { suggestion in
                        CommandRow(label: suggestion.label, command: suggestion.command)
                    }
                    Text(tr(
                        "Vigie ne supprime rien elle-même : copie une commande et lance-la dans un terminal.",
                        "Vigie never deletes anything itself: copy a command and run it in a terminal."
                    ))
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                }
            } else if docker.state == .notRunning {
                Text(tr("Démarre Docker pour voir le détail (images, volumes, cache).", "Start Docker to see the details (images, volumes, cache)."))
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.04)))
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func reclaimable(_ bytes: UInt64) -> String? {
        guard bytes > 0 else { return nil }
        let size = Format.bytes(bytes, decimal: true)
        return tr("\(size) récupérables", "\(size) reclaimable")
    }

    private func cleanups(_ usage: DockerDiskUsage) -> [(label: String, command: String)] {
        var result: [(label: String, command: String)] = []
        let threshold: UInt64 = 500_000_000
        if usage.buildCache.reclaimable >= threshold {
            let size = Format.bytes(usage.buildCache.reclaimable, decimal: true)
            result.append((tr("Vider le cache de construction (\(size))", "Clear the build cache (\(size))"), "docker builder prune"))
        }
        if usage.images.reclaimable >= threshold {
            let size = Format.bytes(usage.images.reclaimable, decimal: true)
            result.append((tr(
                "Supprimer les images inutilisées (\(size), elles se retéléchargent au besoin)",
                "Remove unused images (\(size), they download again when needed)"
            ), "docker image prune -a"))
        }
        if usage.containers.reclaimable >= 100_000_000 {
            let size = Format.bytes(usage.containers.reclaimable, decimal: true)
            result.append((tr("Supprimer les conteneurs arrêtés (\(size))", "Remove stopped containers (\(size))"), "docker container prune"))
        }
        return result
    }
}

struct DiskLine: View {
    let label: String
    let value: String
    let note: String?

    var body: some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 11))
            if let note {
                Text(note)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            Text(value)
                .font(.system(size: 11, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }
}

struct CommandRow: View {
    @Environment(AppModel.self) private var model
    let label: String
    let command: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                Text(command)
                    .font(.system(size: 10.5, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.07)))
                Button(model.copiedCommand == command ? tr("Copié ✓", "Copied ✓") : tr("Copier", "Copy")) {
                    model.copyCommand(command)
                }
                .buttonStyle(.borderless)
                .font(.system(size: 10.5))
                Spacer(minLength: 0)
            }
        }
    }
}

// MARK: - Barre des menus

/// L'œil de Vigie ; quand le disque est presque plein, le pourcentage libre s'affiche à côté.
struct MenuBarLabel: View {
    let model: AppModel

    var body: some View {
        if let disk = model.disk, disk.isLow {
            HStack(spacing: 3) {
                Image(nsImage: MenuBarIcon.image)
                Text(tr("\(disk.freePercent) %", "\(disk.freePercent)%"))
            }
            .accessibilityLabel(tr("Vigie : disque presque plein", "Vigie: disk almost full"))
        } else {
            Image(nsImage: MenuBarIcon.image)
                .accessibilityLabel("Vigie")
        }
    }
}
