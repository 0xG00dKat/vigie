import AppKit
import SwiftUI
import VigieCore

struct MainPanel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            HeaderView()
            Divider()
            if model.snapshot == nil {
                ProgressView(tr("Lecture des processus…", "Reading processes…"))
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                GroupListView()
            }
            Divider()
            FooterView()
        }
        // Changer de langue reconstruit tout le panneau avec les nouveaux textes.
        .id(model.language)
        .frame(width: 460, height: 640)
        .background(WindowVisibilityObserver { model.setVisible($0) })
    }
}

// MARK: - En-tête

struct HeaderView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                Text("Vigie")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                SettingsMenu()
                Button {
                    model.refreshAndReorder()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help(tr("Actualiser et retrier", "Refresh and re-sort"))
            }

            HStack(spacing: 14) {
                if let snapshot = model.snapshot {
                    MemoryGauge(used: snapshot.memoryUsed, total: snapshot.memoryTotal)
                }
                if let disk = model.disk {
                    DiskGauge(disk: disk)
                }
                Spacer(minLength: 0)
            }

            if let snapshot = model.snapshot {
                Text(summary(snapshot))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField(tr("Rechercher une app, un projet, un port…", "Search an app, a project, a port…"), text: $model.query)
                    .textFieldStyle(.plain)
                if model.isSearching {
                    Button {
                        model.query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .font(.system(size: 12))
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 7).fill(Color.primary.opacity(0.07)))
        }
        .padding(12)
    }

    private func summary(_ snapshot: Snapshot) -> String {
        let apps = model.count(in: .apps)
        let dev = model.count(in: .dev)
        let background = model.count(in: .background)
        let systemProcesses = snapshot.groups(in: .system).reduce(0) { $0 + $1.processes.count }
        let total = Format.processes(snapshot.processCount)
        let others = Format.count(systemProcesses)
        return tr(
            "\(total) en tout, rangés en \(apps) apps, \(dev) groupes de dev et \(background) utilitaires. Les \(others) autres appartiennent à macOS.",
            "\(total) in total, sorted into \(apps) apps, \(dev) dev groups and \(background) utilities. The other \(others) belong to macOS."
        )
    }
}

struct MemoryGauge: View {
    let used: UInt64
    let total: UInt64

    var body: some View {
        let ratio = total > 0 ? min(1, Double(used) / Double(total)) : 0
        HStack(spacing: 6) {
            Text("RAM \(Format.bytes(used)) / \(Format.bytes(total))")
                .font(.system(size: 11))
                .monospacedDigit()
                .foregroundStyle(.secondary)
            Capsule()
                .fill(Color.primary.opacity(0.12))
                .frame(width: 44, height: 5)
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(ratio > 0.85 ? Color.red : ratio > 0.7 ? Color.orange : Color.green)
                        .frame(width: 44 * ratio, height: 5)
                }
        }
        .help(tr("Mémoire utilisée, comme dans le Moniteur d'activité", "Memory used, as in Activity Monitor"))
    }
}

// MARK: - Liste

struct GroupListView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                if let disk = model.disk, disk.isLow, !model.isSearching {
                    LowDiskBanner(disk: disk)
                }
                if let update = model.visibleUpdate, !model.isSearching {
                    UpdateBanner(state: update)
                }
                ForEach(ProcessCategory.allCases) { category in
                    let groups = model.visibleGroups(in: category)
                    if !groups.isEmpty {
                        Section {
                            if model.isSectionOpen(category) {
                                if category == .system {
                                    Text(category.help)
                                        .font(.system(size: 10.5))
                                        .foregroundStyle(.secondary)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                }
                                ForEach(groups) { group in
                                    GroupRow(group: group)
                                    Divider().padding(.leading, 50)
                                }
                            }
                        } header: {
                            SectionHeaderView(category: category, groups: groups)
                        }
                    }
                    if category == .dev {
                        DockerSectionView()
                    }
                }
                if model.isSearching && ProcessCategory.allCases.allSatisfy({ model.visibleGroups(in: $0).isEmpty }) {
                    Text(tr("Rien ne correspond à « \(model.query) ».", "Nothing matches “\(model.query)”."))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(30)
                }
            }
        }
    }
}

struct SectionHeaderView: View {
    @Environment(AppModel.self) private var model
    let category: ProcessCategory
    let groups: [ProcessGroup]

    var body: some View {
        let open = model.isSectionOpen(category)
        let memory = groups.reduce(UInt64(0)) { $0 + $1.memory }
        HStack(spacing: 6) {
            Button {
                model.toggleSection(category)
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8.5, weight: .bold))
                        .rotationEffect(.degrees(open ? 90 : 0))
                        .frame(width: 10)
                    Text(category.title.uppercased())
                        .font(.system(size: 10.5, weight: .semibold))
                    Text("\(groups.count)")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                    if memory > 0 {
                        Text("· \(Format.bytes(memory))")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(category.help)

            Spacer()

            if category != .system {
                BulkCloseButton(category: category, groups: groups)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
    }
}

struct BulkCloseButton: View {
    @Environment(AppModel.self) private var model
    let category: ProcessCategory
    let groups: [ProcessGroup]

    var body: some View {
        let targets = groups.filter { $0.close.isAllowed && !$0.isProtected }
        let key = "section:\(category.rawValue)"
        let verb = category == .dev ? tr("Tout arrêter", "Stop all") : tr("Tout quitter", "Quit all")
        Group {
            switch model.closeState(key) {
            case .confirming?:
                HStack(spacing: 4) {
                    Button(tr("\(verb) (\(targets.count)) ?", "\(verb) (\(targets.count))?")) {
                        model.confirmClose(key, methods: targets.map(\.close))
                    }
                    .buttonStyle(DangerButtonStyle())
                    Button(tr("Annuler", "Cancel")) { model.cancelConfirmation(key) }
                        .buttonStyle(.borderless)
                }
                .controlSize(.mini)
            case .closing?:
                ProgressView().controlSize(.mini)
            case .stuck?:
                Button("Forcer") { model.force(key) }
                    .buttonStyle(DangerButtonStyle())
                    .controlSize(.mini)
                    .help(tr("Certains ne répondent pas. Forcer peut faire perdre un travail non enregistré.", "Some aren't responding. Force quitting can lose unsaved work."))
            case nil:
                if targets.count > 1 {
                    Button(verb) { model.requestConfirmation(key) }
                        .buttonStyle(.borderless)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - Ligne d'un groupe

struct GroupRow: View {
    @Environment(AppModel.self) private var model
    let group: ProcessGroup
    @State private var hovering = false

    var body: some View {
        let expanded = model.expandedGroups.contains(group.id)
        let explanation = model.explanationText(for: group)
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 10) {
                GroupIcon(group: group)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Text(group.title)
                            .font(.system(size: 12.5, weight: .semibold))
                            .lineLimit(1)
                        ForEach(group.ports.prefix(3), id: \.self) { port in
                            PortBadge(port: port)
                        }
                        if group.ports.count > 3 {
                            Text("+\(group.ports.count - 3)").font(.system(size: 9.5)).foregroundStyle(.secondary)
                        }
                        if group.isProtected && group.category != .system {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(.tertiary)
                                .help(group.close.notAllowedReason ?? tr("Protégé", "Protected"))
                        }
                    }
                    ExplanationLine(group: group, text: explanation.text, fromClaude: explanation.fromClaude, expanded: expanded)
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
                            .foregroundStyle(group.memory > 2 * 1_073_741_824 ? Color.orange : Color.secondary)
                            .help(tr("Mémoire utilisée par l'ensemble de ses processus", "Memory used by all of its processes"))
                    }
                    if group.close.isAllowed && !group.isProtected {
                        CloseControl(key: group.id, verb: group.category == .dev ? tr("Arrêter", "Stop") : tr("Quitter", "Quit")) {
                            model.confirmClose(group.id, methods: [group.close])
                        }
                    } else if group.category != .system {
                        Color.clear.frame(width: 17, height: 17)
                    }
                }
                .padding(.top, 1)
            }
            if expanded {
                ExpandedDetails(group: group)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .background(hovering ? Color.primary.opacity(0.045) : Color.clear)
        .onHover { hovering = $0 }
        .onTapGesture { model.toggleExpanded(group.id) }
    }

    private var metaLine: String {
        var parts = [Format.processes(group.processes.count)]
        if let cpu = Format.cpu(group.cpuPercent) { parts.append(cpu) }
        if let start = group.startTime, group.category != .system { parts.append(Format.uptime(since: start)) }
        if let launcher = group.launchedBy {
            parts.append(tr("lancé par \(launcher)", "launched by \(launcher)"))
        } else if group.isOrphan {
            parts.append(tr("sans app parente", "no parent app"))
        }
        return parts.joined(separator: " · ")
    }
}

extension CloseMethod {
    var notAllowedReason: String? {
        if case .notAllowed(let reason) = self { return reason }
        return nil
    }
}

struct ExplanationLine: View {
    @Environment(AppModel.self) private var model
    let group: ProcessGroup
    let text: String
    let fromClaude: Bool
    let expanded: Bool

    var body: some View {
        switch model.claude[group.id] {
        case .loading?:
            HStack(spacing: 5) {
                ProgressView().controlSize(.mini)
                Text(tr("Claude réfléchit…", "Claude is thinking…"))
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
        case .failed(let message)?:
            VStack(alignment: .leading, spacing: 2) {
                Text(text)
                Text(message).foregroundStyle(.red)
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
        default:
            (fromClaude ? Text(Image(systemName: "sparkles")) + Text(" ") + Text(text) : Text(text))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(expanded ? nil : 2)
                .fixedSize(horizontal: false, vertical: true)
                .help(fromClaude ? tr("Réponse de Claude (peut être imprécise)", "Claude's answer (may be inaccurate)") : "")
        }
    }
}

struct PortBadge: View {
    let port: Int

    var body: some View {
        Button {
            if let url = URL(string: "http://localhost:\(port)") {
                NSWorkspace.shared.open(url)
            }
        } label: {
            Text(":\(String(port))")
                .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                .foregroundStyle(Color.accentColor)
        }
        .buttonStyle(.plain)
        .help(tr("Ouvrir http://localhost:\(String(port)) dans le navigateur", "Open http://localhost:\(String(port)) in your browser"))
    }
}

struct CloseControl: View {
    @Environment(AppModel.self) private var model
    let key: String
    let verb: String
    let action: () -> Void

    var body: some View {
        switch model.closeState(key) {
        case .confirming?:
            HStack(spacing: 3) {
                Button(tr("\(verb) ?", "\(verb)?"), action: action)
                    .buttonStyle(DangerButtonStyle())
                Button {
                    model.cancelConfirmation(key)
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
                .help(tr("Annuler", "Cancel"))
            }
            .controlSize(.small)
        case .closing?:
            ProgressView().controlSize(.small).frame(width: 22)
        case .stuck?:
            VStack(alignment: .trailing, spacing: 2) {
                Button("Forcer") { model.force(key) }
                    .buttonStyle(DangerButtonStyle())
                    .controlSize(.small)
                Text(tr("Ne répond pas", "Not responding"))
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary)
            }
            .help(tr("Elle attend peut-être une réponse (enregistrer ?). Forcer peut faire perdre un travail non enregistré.", "It may be waiting for an answer (save?). Force quitting can lose unsaved work."))
        case nil:
            Button {
                model.requestConfirmation(key)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help(verb)
        }
    }
}

struct ExpandedDetails: View {
    @Environment(AppModel.self) private var model
    let group: ProcessGroup
    private let limit = 14

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let location = group.location {
                Label(location, systemImage: group.category == .dev ? "folder" : "shippingbox")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            VStack(alignment: .leading, spacing: 1) {
                ForEach(group.processes.prefix(limit)) { process in
                    ProcessLine(process: process, group: group)
                }
                if group.processes.count > limit {
                    Text(tr("+ \(group.processes.count - limit) autres processus", "+ \(group.processes.count - limit) more processes"))
                        .font(.system(size: 10.5))
                        .foregroundStyle(.tertiary)
                        .padding(.top, 2)
                }
            }
            .padding(6)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.04)))

            HStack(spacing: 10) {
                Button {
                    model.askClaude(group)
                } label: {
                    Label(tr("Demander à Claude", "Ask Claude"), systemImage: "sparkles")
                }
                .disabled(model.claude[group.id] == .loading)
                .help(tr("Envoie à Claude le nom et le chemin de l'exécutable (jamais ses arguments).", "Sends Claude the executable's name and path (never its arguments)."))
                Button {
                    model.reveal(group)
                } label: {
                    Label(tr("Afficher dans le Finder", "Show in Finder"), systemImage: "folder")
                }
            }
            .buttonStyle(.borderless)
            .font(.system(size: 11))
            .padding(.top, 2)
        }
        .padding(.leading, 38)
    }
}

struct ProcessLine: View {
    @Environment(AppModel.self) private var model
    let process: RawProcess
    let group: ProcessGroup

    var body: some View {
        let canClose = (group.category == .dev || group.category == .background && group.bundlePath == nil)
            && process.uid == getuid() && process.pid != getpid()
        HStack(spacing: 6) {
            Text(process.name)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
                .layoutPriority(1)
            if let command = Explainer.commandSummary(process) {
                Text(command)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 4)
            ForEach(process.listeningPorts.prefix(2), id: \.self) { PortBadge(port: $0) }
            if let memory = process.memory {
                Text(Format.bytes(memory))
                    .font(.system(size: 10.5))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            if canClose {
                CloseControl(key: "pid:\(process.pid)", verb: tr("Arrêter", "Stop")) {
                    model.closeProcess(process, in: group)
                }
                .scaleEffect(0.85)
            }
        }
        .frame(minHeight: 18)
        .help("PID \(process.pid)\n\(process.path)")
    }
}

// MARK: - Icônes

@MainActor
enum IconCache {
    private static var icons: [String: NSImage] = [:]

    static func icon(for path: String) -> NSImage {
        if let icon = icons[path] { return icon }
        let icon = NSWorkspace.shared.icon(forFile: path)
        icon.size = NSSize(width: 64, height: 64)
        icons[path] = icon
        return icon
    }
}

struct GroupIcon: View {
    let group: ProcessGroup

    var body: some View {
        if let path = group.bundlePath {
            Image(nsImage: IconCache.icon(for: path))
                .resizable()
                .interpolation(.high)
                .frame(width: 28, height: 28)
        } else {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(tint.gradient)
                .frame(width: 26, height: 26)
                .overlay {
                    Image(systemName: symbol)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .padding(1)
        }
    }

    private var symbol: String {
        switch group.category {
        case .dev:
            let names = Set(group.processes.map(\.name))
            if names.contains("claude") { return "sparkle" }
            if group.directory != nil { return "folder.fill" }
            return "terminal.fill"
        case .system: return "gearshape.fill"
        case .background: return "moon.fill"
        case .apps: return "app.fill"
        }
    }

    private var tint: Color {
        switch group.category {
        case .dev:
            let names = Set(group.processes.map(\.name))
            if names.contains("claude") { return .orange }
            return group.directory != nil ? .teal : .indigo
        case .system: return .gray
        case .background: return .purple
        case .apps: return .blue
        }
    }
}

// MARK: - Pied de page

struct FooterView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack {
            Button(tr("Moniteur d'activité", "Activity Monitor")) { model.openActivityMonitor() }
            Spacer()
            LoginItemToggle()
            Spacer()
            Button(tr("Quitter Vigie", "Quit Vigie")) { NSApp.terminate(nil) }
        }
        .buttonStyle(.borderless)
        .font(.system(size: 11))
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

// MARK: - Visibilité de la fenêtre

/// Prévient le modèle quand le panneau s'ouvre ou se ferme, pour n'actualiser que lorsqu'il est visible.
struct WindowVisibilityObserver: NSViewRepresentable {
    let onChange: (Bool) -> Void

    func makeNSView(context: Context) -> ObserverView {
        let view = ObserverView()
        view.onChange = onChange
        return view
    }

    func updateNSView(_ view: ObserverView, context: Context) {
        view.onChange = onChange
    }

    final class ObserverView: NSView {
        var onChange: ((Bool) -> Void)?
        private var tokens: [NSObjectProtocol] = []

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            tokens.forEach(NotificationCenter.default.removeObserver)
            tokens = []
            guard let window else {
                onChange?(false)
                return
            }
            let names = [
                NSWindow.didChangeOcclusionStateNotification,
                NSWindow.didBecomeKeyNotification,
                NSWindow.didResignKeyNotification,
            ]
            for name in names {
                tokens.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.report() }
                })
            }
            report()
        }

        private func report() {
            guard let window else { return }
            onChange?(window.isVisible && window.occlusionState.contains(.visible))
        }
    }
}

/// Bouton rouge de confirmation, rouge même quand la fenêtre n'a pas le focus.
struct DangerButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.red.opacity(configuration.isPressed ? 0.75 : 1))
            )
            .contentShape(Rectangle())
    }
}

struct LoginItemToggle: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let isOn = Binding(
            get: { model.loginItemState != .disabled },
            set: { model.setLaunchAtLogin($0) }
        )
        HStack(spacing: 4) {
            Toggle(tr("Ouvrir au démarrage", "Open at login"), isOn: isOn)
                .toggleStyle(.checkbox)
                .help(model.loginItemError ?? tr("Lance Vigie à l'ouverture de ta session (Réglages Système › Général › Ouverture).", "Starts Vigie when you log in (System Settings › General › Login Items)."))
            if model.loginItemState == .needsApproval {
                Button(tr("À autoriser", "Needs approval")) { LoginItem.openSettings() }
                    .foregroundStyle(.orange)
                    .help(tr("macOS attend ton accord dans Réglages Système › Général › Ouverture.", "macOS is waiting for your approval in System Settings › General › Login Items."))
            } else if model.loginItemError != nil {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .help(model.loginItemError ?? "")
            }
        }
        .onAppear { model.refreshLoginItemState() }
    }
}

