import AppKit
import SwiftUI
import VigieCore

// Panneau de la barre des menus façon tableau de bord : un grand chiffre en haut, des onglets en pastilles,
// puis des cartes empilées sur un fond uni (comme un HUD). Mêmes couleurs que le reste de Vigie.

/// Le panneau de la barre des menus : un coup d'œil et quelques actions, pas toute l'app.
/// L'état en grand, « À faire » (trois actions au plus), ce qui pèse le plus, tes serveurs (mode Développeur),
/// la recherche, et « Ouvrir Vigie » pour tout le reste.
struct DashboardPanel: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PanelHero()
            VStack(alignment: .leading, spacing: 14) {
                if model.isSearching {
                    PanelSearchResults()
                } else if model.snapshot == nil {
                    ProgressView(tr("Lecture des processus…", "Reading processes…"))
                        .controlSize(.small)
                        .frame(maxWidth: .infinity)
                        .padding(20)
                } else {
                    QuickActionsSection()
                    HeaviestSection()
                    if model.isDeveloper { ServersSection() }
                    DailyTipCard()
                }
                // En bas : retrouver vite une app ou un port, ou passer à la fenêtre pour tout le reste.
                HStack(spacing: 8) {
                    PanelSearchField()
                    Button(tr("Ouvrir Vigie", "Open Vigie")) { DockPresence.openFromPanel(dismiss) }
                        .buttonStyle(HUDPillButtonStyle(prominent: true))
                        .keyboardShortcut("o")
                        .help(tr("Tout le détail dans la fenêtre (⌘O)", "All the details in the window (⌘O)"))
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
        .frame(width: 400)
        .fixedSize(horizontal: false, vertical: true)
        .background(DS.canvas)
        .animation(VigieMotion.standard, value: model.isSearching)
    }
}

/// En haut : « Ton Mac », le chiffre qui compte le plus en ce moment, l'état en une phrase et les trois mesures.
struct PanelHero: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(tr("Mon Mac", "My Mac"))
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(DS.secondaryText)
                Spacer(minLength: 6)
                PanelRoundButton(symbol: "arrow.clockwise", help: tr("Actualiser", "Refresh")) {
                    model.refreshAndReorder()
                }
                SettingsMenu(round: true, inPanel: true)
            }
            bigNumber
            // Les trois mesures ; le point dit l'état (le détail est dans « À faire »).
            HStack(spacing: 6) {
                if let health = model.health {
                    Circle().fill(color(health.level)).frame(width: 7, height: 7)
                }
                Text(measures)
                    .font(.system(size: 12))
                    .foregroundStyle(DS.secondaryText)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 12)
    }

    private func color(_ level: MacHealth.Level) -> Color {
        level == .critical ? DS.urgent : level == .attention ? DS.review : DS.safe
    }

    /// Le disque s'il est le souci du moment, sinon la mémoire.
    @ViewBuilder
    private var bigNumber: some View {
        if let disk = model.disk, (disk.isLow || disk.isTight), model.diskHealth?.level != .good {
            BigFigure(value: Format.bytes(disk.available, decimal: true),
                      suffix: tr("libres sur \(Format.bytes(disk.total, decimal: true))", "free of \(Format.bytes(disk.total, decimal: true))"))
        } else if let snapshot = model.snapshot {
            BigFigure(value: Format.bytes(snapshot.memoryUsed),
                      suffix: tr("de mémoire sur \(Format.bytes(snapshot.memoryTotal))", "of memory, \(Format.bytes(snapshot.memoryTotal)) total"))
        }
    }

    /// « · disque 182 Go libres · processeur 11 % »
    private var measures: String {
        var parts: [String] = []
        if let pressure = model.performance?.memory.pressure {
            parts.append(pressure == .normal ? tr("mémoire suffisante", "enough memory") : pressure == .warning ? tr("mémoire un peu juste", "memory a bit tight") : tr("mémoire insuffisante", "not enough memory"))
        }
        if let disk = model.disk {
            parts.append(tr("disque \(Format.bytes(disk.available, decimal: true)) libres", "disk \(Format.bytes(disk.available, decimal: true)) free"))
        }
        if let snapshot = model.snapshot {
            let cores = Double(max(ProcessInfo.processInfo.activeProcessorCount, 1))
            let cpu = snapshot.groups.reduce(0.0) { $0 + $1.cpuPercent } / cores
            parts.append(tr("processeur \(Int(min(100, cpu).rounded())) %", "CPU \(Int(min(100, cpu).rounded()))%"))
        }
        return parts.joined(separator: " · ")
    }
}

/// « 21 Go » en grand, et ce que c'est en petit à côté.
struct BigFigure: View {
    let value: String
    let suffix: String

    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: 7) {
            Text(value)
                .font(.system(size: 38, weight: .bold).monospacedDigit())
                .foregroundStyle(DS.primaryText)
                .contentTransition(.numericText())
                .lineLimit(1)
            Text(suffix)
                .font(.system(size: 12.5))
                .foregroundStyle(DS.secondaryText)
                .lineLimit(1)
        }
        .animation(VigieMotion.standard, value: value)
    }
}

/// Onglets en pastilles dans un bac : l'onglet choisi glisse de l'un à l'autre.
struct PillTabs<Value: Hashable>: View {
    @Binding var selection: Value
    let tabs: [(Value, String)]
    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 2) {
            ForEach(tabs, id: \.0) { tab in
                let selected = tab.0 == selection
                Button {
                    withAnimation(VigieMotion.glide) { selection = tab.0 }
                } label: {
                    Text(tab.1)
                        .font(.system(size: 12.5, weight: selected ? .semibold : .medium))
                        .foregroundStyle(selected ? DS.primaryText : DS.secondaryText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background {
                            if selected {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(DS.wellSelected)
                                    .shadow(color: .black.opacity(0.12), radius: 1.5, y: 0.5)
                                    .matchedGeometryEffect(id: "onglet", in: namespace)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(DS.well))
    }
}

/// Bouton rond discret (fenêtre, actualiser, réglages).
struct PanelRoundButton: View {
    let symbol: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(DS.secondaryText)
                .frame(width: 26, height: 26)
                .background(Circle().fill(DS.well))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

/// Pastille : l'action principale en plein (noir en clair, blanc en sombre), la secondaire en creux.
struct HUDPillButtonStyle: ButtonStyle {
    var prominent = false
    /// Largeur commune des boutons d'une même colonne (« Voir », « Nettoyer »…).
    var minWidth: CGFloat? = nil

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12.5, weight: .semibold))
            .frame(minWidth: minWidth)
            .foregroundStyle(prominent ? DS.canvas : DS.primaryText)
            .padding(.horizontal, 13)
            .padding(.vertical, 7)
            .background(Capsule().fill(prominent ? DS.primaryText : DS.well))
            .opacity(configuration.isPressed ? 0.75 : 1)
            .animation(VigieMotion.quick, value: configuration.isPressed)
    }
}

/// Champ de recherche du panneau, dans un creux arrondi.
struct PanelSearchField: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass").foregroundStyle(DS.secondaryText)
            TextField(tr("Rechercher…", "Search…"), text: $model.query)
                .help(model.isDeveloper ? tr("Une app, un projet ou un port (« 3000 »)", "An app, a project or a port (“3000”)") : tr("Une app", "An app"))
                .textFieldStyle(.plain)
            if model.isSearching {
                Button { model.query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(DS.secondaryText) }
                    .buttonStyle(.plain)
            }
        }
        .font(.system(size: 12.5))
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .panelSurface(radius: 10)
    }
}

extension View {
    /// Carte du panneau : à peine plus claire que le fond, liseré fin, grands arrondis.
    func panelSurface(radius: CGFloat = 18) -> some View {
        self
            .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(DS.surface)
                .shadow(color: .black.opacity(0.10), radius: 8, y: 3))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(DS.stroke, lineWidth: 0.5))
    }
}

// MARK: - À faire

/// Une action proposée : ce qui se passe, et un bouton qui y répond.
struct QuickAction: Identifiable {
    enum Kind {
        case health(MacHealth)
        case safeClean(UInt64)
        case stop(ProcessGroup)
        case service(KeepAliveJob)
    }
    let id: String
    let tint: Color
    let title: String
    let detail: String
    let kind: Kind
}

struct QuickActionsSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let actions = Array(QuickActionsSection.actions(model).prefix(3))
        VStack(alignment: .leading, spacing: 6) {
            PanelSectionTitle(text: tr("À faire", "To do"))
            if actions.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(DS.safe)
                    Text(tr("Rien à faire, ton Mac va bien.", "Nothing to do, your Mac is fine."))
                        .font(.system(size: 12.5))
                    Spacer()
                }
                .padding(12)
                .panelSurface()
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(actions.enumerated()), id: \.element.id) { index, action in
                        if index > 0 { Divider().padding(.leading, 28) }
                        QuickActionRow(action: action)
                    }
                }
                .panelSurface()
            }
        }
    }

    /// Les actions du moment, de la plus urgente à la moins urgente, sans doublon.
    static func actions(_ model: AppModel) -> [QuickAction] {
        var result: [QuickAction] = []
        func tint(_ level: MacHealth.Level) -> Color { level == .critical ? DS.urgent : level == .attention ? DS.review : DS.safe }
        // Un service qui relance ce qu'on vient de fermer : la fermeture n'a servi à rien, c'est le plus utile à dire.
        if let notice = model.relaunchNotice, let job = notice.job, job.isUser {
            result.append(QuickAction(id: "service", tint: DS.review,
                                      title: tr("\(notice.title) revient tout seul", "\(notice.title) keeps coming back"),
                                      detail: tr("Relancé par macOS après chaque arrêt.", "Restarted by macOS after each stop."),
                                      kind: .service(job)))
        }
        // Vitesse : une app qui s'emballe, ou la mémoire qui manque.
        if let speed = model.speedHealth, speed.level != .good, speed.action != nil {
            result.append(QuickAction(id: "speed", tint: tint(speed.level), title: speed.title, detail: speed.message, kind: .health(speed)))
        }
        // Disque : vider ce qui est sûr (ou analyser).
        let safe = model.safeCleanItems.reduce(UInt64(0)) { $0 + $1.size }
        if let disk = model.diskHealth, disk.level != .good, disk.action != nil {
            result.append(QuickAction(id: "disk", tint: tint(disk.level), title: disk.title, detail: disk.message, kind: .health(disk)))
        } else if safe >= 1_000_000_000 || model.safeClean != nil {
            result.append(QuickAction(id: "clean", tint: DS.safe,
                                      title: tr("\(Format.bytes(safe, decimal: true)) se vident sans risque", "\(Format.bytes(safe, decimal: true)) can be safely cleared"),
                                      detail: tr("Des caches qui se recréent tout seuls.", "Caches that rebuild themselves."),
                                      kind: .safeClean(safe)))
        }
        // Développeur : un serveur visible sur le Wi-Fi.
        if model.isDeveloper {
            for group in model.visibleGroups(in: .dev) where !group.exposedPorts.isEmpty && group.close.isAllowed {
                result.append(QuickAction(id: "expose:" + group.id, tint: DS.review,
                                          title: tr("\(group.title) est visible sur le Wi-Fi", "\(group.title) is visible on the Wi-Fi"),
                                          detail: tr("Port \(group.exposedPorts.map(String.init).joined(separator: ", ")) : les appareils du même réseau peuvent s'y connecter.",
                                                     "Port \(group.exposedPorts.map(String.init).joined(separator: ", ")): devices on the same network can connect."),
                                          kind: .stop(group)))
            }
        }
        return result
    }
}

struct QuickActionRow: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let action: QuickAction

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Circle().fill(action.tint).frame(width: 8, height: 8).padding(.top, 5)
                VStack(alignment: .leading, spacing: 2) {
                    Text(action.title).font(.system(size: 12.5, weight: .medium)).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    // Une ligne : le panneau reste court ; le détail est dans la fenêtre.
                    Text(action.detail).font(.system(size: 11.5)).foregroundStyle(DS.secondaryText).lineLimit(1)
                        .help(action.detail)
                }
                Spacer(minLength: 8)
                button
            }
            // Le récapitulatif du nettoyage s'ouvre ici, sous l'action.
            if case .safeClean = action.kind, model.safeClean != nil {
                SafeCleanArea(showsButton: false).padding(.leading, 18)
            } else if case .health(let health) = action.kind, case .freeSpace? = health.action, model.safeClean != nil {
                SafeCleanArea(showsButton: false).padding(.leading, 18)
            } else if case .health(let health) = action.kind, case .scan? = health.action, let progress = model.storageProgress {
                ProgressView(value: progress).tint(VigieTheme.accent).padding(.leading, 18)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    /// Les boutons d'action ont tous cette largeur au moins : la colonne reste régulière.
    static let buttonWidth: CGFloat = 70

    @ViewBuilder
    private var button: some View {
        switch action.kind {
        case .health(let health):
            switch health.action {
            case .quit(let id, let name)?:
                ConfirmPill(key: id, title: tr("Quitter", "Quit"), confirm: tr("Quitter \(name) ?", "Quit \(name)?"), minWidth: Self.buttonWidth) {
                    model.performHealthAction(fromPanel: false, health: health)
                }
            case .showMemory?:
                Button(tr("Voir", "See")) {
                    model.windowPageRequest = .speed
                    DockPresence.openFromPanel(dismiss)
                }
                .buttonStyle(HUDPillButtonStyle(prominent: true, minWidth: Self.buttonWidth))
            case .freeSpace?:
                if model.safeClean == nil {
                    Button(tr("Nettoyer", "Clean")) { model.reviewSafeClean() }.buttonStyle(HUDPillButtonStyle(prominent: true, minWidth: Self.buttonWidth))
                }
            case .scan?:
                if model.storageProgress == nil {
                    Button(tr("Analyser", "Analyze")) { model.scanStorage() }.buttonStyle(HUDPillButtonStyle(prominent: true, minWidth: Self.buttonWidth))
                }
            case nil:
                EmptyView()
            }
        case .safeClean:
            if model.safeClean == nil {
                Button(tr("Nettoyer", "Clean")) { model.reviewSafeClean() }.buttonStyle(HUDPillButtonStyle(prominent: true, minWidth: Self.buttonWidth))
            }
        case .stop(let group):
            ConfirmPill(key: group.id, title: tr("Arrêter", "Stop"), confirm: tr("Arrêter ?", "Stop?"), minWidth: Self.buttonWidth) {
                model.confirmClose(group.id, methods: [group.close])
            }
        case .service(let job):
            if model.closeState("launchd:" + job.label) != nil {
                ProgressView().controlSize(.small)
            } else {
                Button(tr("Arrêter le service", "Stop the service")) { model.stopKeepAlive(job, forGood: false) }
                    .buttonStyle(HUDPillButtonStyle(prominent: true))
            }
        }
    }
}

/// Pastille en deux temps : un clic demande confirmation (4 s), le second agit.
struct ConfirmPill: View {
    @Environment(AppModel.self) private var model
    let key: String
    let title: String
    let confirm: String
    var minWidth: CGFloat? = nil
    let action: () -> Void

    var body: some View {
        switch model.closeState(key) {
        case .confirming?:
            Button(confirm, action: action)
                .buttonStyle(DangerButtonStyle())
        case .closing?:
            ProgressView().controlSize(.small)
        case .stuck?:
            Button(tr("Forcer", "Force")) { model.force(key) }.buttonStyle(DangerButtonStyle())
        case nil:
            Button(title) { model.requestConfirmation(key) }
                .buttonStyle(HUDPillButtonStyle(prominent: true, minWidth: minWidth))
        }
    }
}

// MARK: - Ce qui pèse le plus, serveurs, recherche

struct PanelSectionTitle: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10.5, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(DS.secondaryText)
            .padding(.leading, 4)
    }
}

/// Une ligne courte : icône, nom (et ports en mode Développeur), mémoire, ×.
struct CompactGroupRow: View {
    @Environment(AppModel.self) private var model
    let group: ProcessGroup
    var showsPorts = false

    var body: some View {
        HStack(spacing: 9) {
            GroupIcon(group: group).frame(width: 20, height: 20)
            Text(group.title).font(.system(size: 12.5, weight: .medium)).lineLimit(1)
            if showsPorts {
                ForEach(Array(group.ports.prefix(2)), id: \.self) { port in
                    PortBadge(port: port, exposed: group.exposedPorts.contains(port))
                }
            }
            Spacer(minLength: 6)
            Text(Format.bytes(group.memory))
                .font(.system(size: 11.5)).monospacedDigit()
                .foregroundStyle(DS.secondaryText)
            if group.close.isAllowed && !group.isProtected {
                GroupCloseControl(group: group)
            } else {
                Color.clear.frame(width: 17, height: 17)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}

struct HeaviestSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let groups = Array(model.memoryGroups.prefix(4))
        if !groups.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                PanelSectionTitle(text: tr("Ce qui pèse le plus", "Using the most"))
                VStack(spacing: 0) {
                    ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                        if index > 0 { Divider().padding(.leading, 41) }
                        CompactGroupRow(group: group)
                    }
                }
                .panelSurface()
            }
        }
    }
}

/// Tes serveurs de dev qui écoutent sur un port : souvent la raison d'ouvrir le panneau.
struct ServersSection: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let servers = model.visibleGroups(in: .dev).filter { !$0.ports.isEmpty }
        if !servers.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                PanelSectionTitle(text: tr("Serveurs", "Servers"))
                VStack(spacing: 0) {
                    ForEach(Array(servers.prefix(3).enumerated()), id: \.element.id) { index, group in
                        if index > 0 { Divider().padding(.leading, 41) }
                        CompactGroupRow(group: group, showsPorts: true)
                    }
                    if servers.count > 3 {
                        Divider()
                        Button(tr("\(servers.count - 3) autre\(servers.count > 4 ? "s" : "") dans Vigie…", "\(servers.count - 3) more in Vigie…")) {
                            model.windowPageRequest = .ports
                            DockPresence.openFromPanel(dismiss)
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 11.5))
                        .foregroundStyle(DS.secondaryText)
                        .padding(8)
                    }
                }
                .panelSurface()
            }
        }
    }
}

/// Pendant une recherche : ce qui correspond (apps, projets, ports), en lignes courtes.
struct PanelSearchResults: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let groups = ProcessCategory.allCases.flatMap { model.visibleGroups(in: $0) }.sorted { $0.memory > $1.memory }
        VStack(alignment: .leading, spacing: 6) {
            PanelSectionTitle(text: tr("\(groups.count) résultat\(groups.count > 1 ? "s" : "")", "\(groups.count) result\(groups.count > 1 ? "s" : "")"))
            if groups.isEmpty {
                Text(tr("Rien ne correspond à « \(model.query) ».", "Nothing matches “\(model.query)”."))
                    .font(.system(size: 12.5)).foregroundStyle(DS.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .panelSurface()
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(groups.prefix(8).enumerated()), id: \.element.id) { index, group in
                        if index > 0 { Divider().padding(.leading, 41) }
                        CompactGroupRow(group: group, showsPorts: model.isDeveloper)
                    }
                }
                .panelSurface()
            }
        }
    }
}

/// « Le savais-tu ? » : une explication par jour, en une ligne ; un clic l'ouvre dans la fenêtre.
struct DailyTipCard: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var hovering = false

    var body: some View {
        let lessons = Lessons.visible(developer: model.isDeveloper)
        let day = Calendar.current.ordinality(of: .day, in: .era, for: Date()) ?? 0
        if !lessons.isEmpty {
            let lesson = lessons[day % lessons.count]
            Button {
                model.windowPageRequest = .lesson(lesson.id)
                DockPresence.openFromPanel(dismiss)
            } label: {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "lightbulb.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(VigieTheme.accent)
                        .padding(.top, 1)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(tr("Le savais-tu ?", "Did you know?"))
                            .font(.system(size: 10.5, weight: .semibold)).foregroundStyle(DS.secondaryText)
                        Text(lesson.takeaway.text)
                            .font(.system(size: 12.5))
                            .foregroundStyle(DS.primaryText)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 6)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(DS.tertiaryText)
                        .padding(.top, 4)
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(VigieTheme.accent.opacity(hovering ? 0.14 : 0.08)))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .animation(VigieMotion.quick, value: hovering)
            .help(tr("Lire « \(lesson.title.text) »", "Read “\(lesson.title.text)”"))
        }
    }
}
