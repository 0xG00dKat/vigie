import AppKit
import SwiftUI
import VigieCore

/// « Vitesse et batterie » : pourquoi le Mac est lent, chauffe ou vide sa batterie, en mots simples.
/// La même vue sert au panneau (compacte) et à la page de la fenêtre.
struct PerformanceView: View {
    @Environment(AppModel.self) private var model
    let compact: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 12 : 18) {
            // Dans le panneau, l'état est déjà en haut (grand chiffre, phrase, action) : pas de carte en double.
            if !compact { StatusCard(compact: compact, source: .speed) }
            BusySection(compact: compact)
            MemorySection(compact: compact)
            StartupSection(compact: compact)
            if let battery = model.performance?.battery {
                BatterySection(battery: battery, compact: compact)
            }
            ThermalSection(compact: compact)
            AlertsCard(compact: compact)
        }
    }
}

/// Titre de bloc et une phrase.
struct SpeedSectionTitle: View {
    let title: String
    let subtitle: String?
    let compact: Bool
    /// Explication liée (« En savoir plus » à côté du titre).
    var lesson: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title).font(.system(size: compact ? 13 : 15, weight: .semibold))
                if let lesson { LearnMoreLink(lesson: lesson) }
            }
            if let subtitle {
                Text(subtitle).font(.system(size: compact ? 11 : 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Une app : icône, nom, ce qu'elle fait au Mac, et le bouton Quitter quand c'est permis.
struct SpeedAppRow: View {
    /// Dans une case de la fenêtre, la carte perd son cadre : les lignes s'alignent sur le titre.
    @Environment(\.flatCards) private var flat
    @Environment(AppModel.self) private var model
    let group: ProcessGroup
    let detail: String
    let tint: Color

    var body: some View {
        HStack(spacing: 10) {
            if let path = group.bundlePath {
                Image(nsImage: IconCache.icon(for: path)).resizable().interpolation(.high).frame(width: 24, height: 24)
            } else {
                VigieTile(symbol: group.category.outlineSymbol, tint: VigieTheme.accent, size: 24)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(group.title).font(.system(size: 12.5, weight: .medium)).lineLimit(1)
                Text(detail).font(.system(size: 11)).foregroundStyle(tint).lineLimit(1)
            }
            Spacer(minLength: 6)
            if group.close.isAllowed && !group.isProtected {
                GroupCloseControl(group: group)
            }
        }
        .padding(.horizontal, flat ? 0 : 12)
        .padding(.vertical, 7)
    }
}

struct BusySection: View {
    /// Dans une case de la fenêtre, la carte perd son cadre : les lignes s'alignent sur le titre.
    @Environment(\.flatCards) private var flat
    @Environment(AppModel.self) private var model
    let compact: Bool

    var body: some View {
        let groups = Array(model.busyGroups.prefix(5))
        VStack(alignment: .leading, spacing: 8) {
            SpeedSectionTitle(title: tr("Ce qui fait travailler ton Mac", "What's working your Mac"),
                              subtitle: tr("Les apps qui ont le plus utilisé le processeur ces dernières minutes.",
                                           "The apps that used the processor most in the last few minutes."), compact: compact)
            VigieCard(padding: 0) {
                ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                    if index > 0 { Divider().padding(.leading, flat ? 34 : 46) }
                    let cpu = model.averageCPU(group)
                    SpeedAppRow(group: group, detail: Self.describe(cpu, developer: model.isDeveloper), tint: cpu >= 50 ? .orange : .secondary)
                }
                if groups.isEmpty {
                    Text(tr("Rien ne travaille pour l'instant.", "Nothing is working right now.")).font(.system(size: 12)).foregroundStyle(.secondary).padding(12)
                }
            }
        }
    }

    static func describe(_ cpu: Double, developer: Bool) -> String {
        let level = cpu >= 50 ? tr("travaille beaucoup", "working hard") : cpu >= 10 ? tr("travaille un peu", "working a little") : tr("presque rien", "almost idle")
        return developer ? "\(level) · \(Int(cpu.rounded())) % CPU" : level
    }
}

struct MemorySection: View {
    /// Dans une case de la fenêtre, la carte perd son cadre : les lignes s'alignent sur le titre.
    @Environment(\.flatCards) private var flat
    @Environment(AppModel.self) private var model
    let compact: Bool

    var body: some View {
        let memory = model.performance?.memory
        let color: Color = memory?.pressure == .critical ? .red : memory?.pressure == .warning ? .orange : .green
        VStack(alignment: .leading, spacing: 8) {
            SpeedSectionTitle(title: tr("La mémoire", "Memory"), subtitle: Self.sentence(memory), compact: compact,
                              lesson: memory?.swapUsed ?? 0 > 1_000_000_000 ? "swap" : "memoire")
            if let snapshot = model.snapshot {
                VStack(alignment: .leading, spacing: 4) {
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.primary.opacity(0.08))
                            Capsule().fill(color).frame(width: geometry.size.width * min(1, Double(snapshot.memoryUsed) / Double(max(snapshot.memoryTotal, 1))))
                        }
                    }
                    .frame(height: 8)
                    Text(tr("\(Format.bytes(snapshot.memoryUsed)) utilisés sur \(Format.bytes(snapshot.memoryTotal))",
                            "\(Format.bytes(snapshot.memoryUsed)) used of \(Format.bytes(snapshot.memoryTotal))"))
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            VigieCard(padding: 0) {
                ForEach(Array(model.memoryGroups.prefix(5).enumerated()), id: \.element.id) { index, group in
                    if index > 0 { Divider().padding(.leading, flat ? 34 : 46) }
                    SpeedAppRow(group: group, detail: Format.bytes(group.memory), tint: group.memory > 2 * 1_073_741_824 ? .orange : .secondary)
                }
            }
        }
    }

    static func sentence(_ memory: MemoryStatus?) -> String {
        guard let memory else { return "" }
        let swap = Format.bytes(memory.swapUsed, decimal: true)
        switch memory.pressure {
        case .normal:
            // Le « swap » reste après un moment chargé : ce n'est pas un problème tant que la pression est normale.
            return memory.swapUsed > 1_000_000_000
                ? tr("Assez de mémoire en ce moment. Ton Mac a rangé \(swap) sur le disque plus tôt, quand il en manquait : rien à faire.",
                     "Enough memory right now. Your Mac stored \(swap) on the disk earlier, when it was short: nothing to do.")
                : tr("Assez de mémoire : ton Mac n'a pas besoin de ranger des choses sur le disque.", "Enough memory: your Mac doesn't need to store things on the disk.")
        case .warning:
            return tr("Un peu juste : ton Mac range \(swap) sur le disque, ce qui le ralentit. Quitter une app ou fermer des onglets aide.",
                      "A bit tight: your Mac is storing \(swap) on the disk, which slows it down. Quitting an app or closing tabs helps.")
        case .critical:
            return tr("Il en manque : ton Mac range \(swap) sur le disque et devient lent. Quitte une ou deux apps parmi les plus gourmandes.",
                      "Not enough: your Mac is storing \(swap) on the disk and getting slow. Quit one or two of the hungriest apps.")
        }
    }
}

struct BatterySection: View {
    /// Dans une case de la fenêtre, la carte perd son cadre : les lignes s'alignent sur le titre.
    @Environment(\.flatCards) private var flat
    @Environment(AppModel.self) private var model
    let battery: BatteryStatus
    let compact: Bool

    var body: some View {
        let blockers = (model.performance?.blockers ?? []).filter { model.isDeveloper || !$0.isSystem }
        VStack(alignment: .leading, spacing: 8) {
            SpeedSectionTitle(title: tr("La batterie", "Battery"), subtitle: chargeLine, compact: compact, lesson: "batterie")
            VigieCard(padding: compact ? 12 : 16) {
                HStack(spacing: 12) {
                    VigieTile(symbol: battery.charging ? "battery.100percent.bolt" : "battery.75percent",
                              tint: (battery.health ?? 100) < 80 ? .orange : .green, size: compact ? 30 : 36)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(healthTitle).font(.system(size: 12.5, weight: .semibold))
                        Text(healthDetail).font(.system(size: 11.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            let energy = Array(model.energyGroups.prefix(5))
            if !energy.isEmpty {
                Text(tr("Ce qui consomme le plus", "What uses the most")).font(.system(size: 12, weight: .semibold)).padding(.top, 2)
                VigieCard(padding: 0) {
                    ForEach(Array(energy.enumerated()), id: \.element.id) { index, group in
                        if index > 0 { Divider().padding(.leading, flat ? 34 : 46) }
                        let watts = model.energyRates[group.id] ?? 0
                        SpeedAppRow(group: group, detail: Self.describe(watts: watts, developer: model.isDeveloper), tint: watts >= 5 ? .orange : .secondary)
                    }
                }
            }
            if !blockers.isEmpty {
                Text(tr("Ce qui empêche la veille", "What keeps your Mac awake")).font(.system(size: 12, weight: .semibold)).padding(.top, 2)
                VigieCard(padding: 0) {
                    ForEach(Array(blockers.enumerated()), id: \.element.id) { index, blocker in
                        if index > 0 { Divider().padding(.leading, flat ? 0 : 12) }
                        VStack(alignment: .leading, spacing: 1) {
                            Text(Self.blockerSentence(blocker)).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
                            if model.isDeveloper {
                                Text("\(blocker.kind) · « \(blocker.reason) » · pid \(blocker.pid)").font(.system(size: 10.5, design: .monospaced)).foregroundStyle(.tertiary)
                            }
                        }
                        .opacity(blocker.isSystem ? 0.6 : 1)
                        .padding(.horizontal, flat ? 0 : 12)
                        .padding(.vertical, 7)
                    }
                }
            }
        }
    }

    private var chargeLine: String {
        if battery.charging { return tr("\(battery.percent) %, en charge.", "\(battery.percent)%, charging.") }
        if battery.onPower { return tr("\(battery.percent) %, branché.", "\(battery.percent)%, plugged in.") }
        if let minutes = battery.minutesRemaining {
            return tr("\(battery.percent) %, encore environ \(minutes / 60) h \(String(format: "%02d", minutes % 60)).",
                      "\(battery.percent)%, about \(minutes / 60) h \(String(format: "%02d", minutes % 60)) left.")
        }
        return tr("\(battery.percent) %, sur batterie.", "\(battery.percent)%, on battery.")
    }

    private var healthTitle: String {
        guard let health = battery.health else { return tr("Santé de la batterie inconnue", "Battery health unknown") }
        if health >= 80 { return tr("Ta batterie est en bonne santé", "Your battery is healthy") }
        return tr("Ta batterie s'use", "Your battery is wearing out")
    }

    private var healthDetail: String {
        let cycles = battery.cycles.map { tr("\($0) cycles de charge", "\($0) charge cycles") }
        guard let health = battery.health else { return cycles ?? "" }
        var text = tr("Elle garde \(health) % de sa capacité d'origine", "It keeps \(health)% of its original capacity")
        if let cycles { text += " · " + cycles }
        if health < 80 { text += tr(". Un remplacement chez Apple redonnerait de l'autonomie.", ". A replacement at Apple would restore battery life.") }
        return text
    }

    static func describe(watts: Double, developer: Bool) -> String {
        let level = watts >= 5 ? tr("consomme beaucoup", "uses a lot") : watts >= 1 ? tr("consomme un peu", "uses a little") : tr("consomme très peu", "uses very little")
        return developer ? "\(level) · " + String(format: "%.1f W", watts) : level
    }

    static func blockerSentence(_ blocker: SleepBlocker) -> String {
        let name = blocker.name == "zoom.us" ? "Zoom" : blocker.name
        let duration = Format.uptime(since: Date().addingTimeInterval(-Double(blocker.seconds)))
        if blocker.name == "coreaudiod" {
            return tr("Un son est en cours de lecture : ton Mac reste éveillé \(duration).", "Sound is playing: your Mac stays awake \(duration.replacingOccurrences(of: "depuis", with: "for")).")
        }
        return blocker.keepsDisplayOn
            ? tr("\(name) garde l'écran allumé \(duration).", "\(name) keeps the screen on.")
            : tr("\(name) empêche ton Mac de se mettre en veille \(duration).", "\(name) keeps your Mac from sleeping.")
    }
}

struct ThermalSection: View {
    @Environment(AppModel.self) private var model
    let compact: Bool

    var body: some View {
        let thermal = model.performance?.thermal ?? .normal
        let (title, text, color): (String, String, Color) = {
            switch thermal {
            case .normal: return (tr("Température normale", "Normal temperature"), tr("Rien à signaler.", "Nothing to report."), .green)
            case .warm: return (tr("Un peu chaud", "A bit warm"), tr("Normal quand il travaille beaucoup ; rien à faire.", "Normal when it works hard; nothing to do."), .green)
            case .hot: return (tr("Chaud", "Hot"), tr("macOS ralentit le processeur pour le refroidir. Quitter l'app qui travaille le plus aide.", "macOS is slowing the processor to cool it. Quitting the busiest app helps."), .orange)
            case .critical: return (tr("Très chaud", "Very hot"), tr("macOS ralentit fortement le Mac. Quitte les apps gourmandes et laisse-le respirer (pas sur un coussin).", "macOS is slowing the Mac a lot. Quit hungry apps and let it breathe (not on a cushion)."), .red)
            }
        }()
        VigieCard(padding: compact ? 12 : 16) {
            HStack(spacing: 12) {
                VigieTile(symbol: "thermometer.medium", tint: color, size: compact ? 30 : 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 12.5, weight: .semibold))
                    Text(text).font(.system(size: 11.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

/// « Ce qui démarre avec ton Mac » : tes agents se coupent ici (interrupteur, réversible) ;
/// les aides d'apps et les services se gèrent dans Réglages Système, où macOS demande ton accord.
struct StartupSection: View {
    /// Dans une case de la fenêtre, la carte perd son cadre : les lignes s'alignent sur le titre.
    @Environment(\.flatCards) private var flat
    @Environment(AppModel.self) private var model
    let compact: Bool

    var body: some View {
        let order: [StartupItem.Scope] = [.user, .appHelper, .allUsers, .system]
        let items = model.startupItems.sorted { (order.firstIndex(of: $0.scope) ?? 9, $0.displayName) < (order.firstIndex(of: $1.scope) ?? 9, $1.displayName) }
        VStack(alignment: .leading, spacing: 8) {
            SpeedSectionTitle(title: tr("Ce qui démarre avec ton Mac", "What starts with your Mac"),
                              subtitle: tr("Ces programmes se lancent tout seuls quand tu ouvres ta session. En couper un libère de la mémoire et accélère le démarrage.",
                                           "These programs start on their own when you log in. Turning one off frees memory and speeds up startup."), compact: compact,
                              lesson: "demarrage")
            VigieCard(padding: 0) {
                // Une ligne par app : ses éléments (mises à jour, aide, service…) se déplient au clic.
                let groups = Self.grouped(items)
                ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                    if index > 0 { Divider().padding(.leading, flat ? 34 : 46) }
                    if group.items.count == 1, let item = group.items.first {
                        StartupRow(item: item)
                    } else {
                        StartupGroupRow(group: group)
                    }
                }
                if items.isEmpty {
                    Text(tr("Rien ne démarre tout seul, à part macOS.", "Nothing starts on its own, apart from macOS."))
                        .font(.system(size: 12)).foregroundStyle(.secondary).padding(12)
                }
            }
            if items.contains(where: { !$0.canToggle }) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(tr("Les aides d'apps et les services se gèrent dans Réglages Système › Général › Ouverture : macOS y demande ton accord.",
                            "App helpers and services are managed in System Settings › General › Login Items: macOS asks for your approval there."))
                        .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Button(tr("Ouvrir", "Open")) { model.openLoginItemsSettings() }
                        .buttonStyle(.borderless).font(.system(size: 11, weight: .medium))
                }
            }
            if let error = model.startupError {
                Text(error).font(.system(size: 11)).foregroundStyle(.red)
            }
        }
        .onAppear { model.refreshStartupItems() }
    }

    struct Group: Identifiable {
        var id: String
        var name: String
        var ownerPath: String?
        var items: [StartupItem]
    }

    /// Les éléments d'une même app ensemble (par son chemin, sinon son nom) ; l'ordre d'arrivée est gardé.
    static func grouped(_ items: [StartupItem]) -> [Group] {
        var groups: [Group] = []
        for item in items {
            let key = item.ownerPath ?? item.ownerName ?? item.label
            if let index = groups.firstIndex(where: { $0.id == key }) {
                groups[index].items.append(item)
            } else {
                groups.append(Group(id: key, name: item.ownerName ?? item.displayName, ownerPath: item.ownerPath, items: [item]))
            }
        }
        return groups
    }
}

/// Une app qui lance plusieurs choses au démarrage : une ligne, et ses éléments au clic.
struct StartupGroupRow: View {
    /// Dans une case de la fenêtre, la carte perd son cadre : les lignes s'alignent sur le titre.
    @Environment(\.flatCards) private var flat
    @Environment(AppModel.self) private var model
    let group: StartupSection.Group
    @State private var expanded = false
    @State private var hovering = false

    var body: some View {
        let running = group.items.filter(\.isRunning).count
        let off = group.items.filter { !$0.isEnabled }.count
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(VigieMotion.standard) { expanded.toggle() }
            } label: {
                HStack(spacing: 10) {
                    if let path = group.ownerPath, FileManager.default.fileExists(atPath: path) {
                        Image(nsImage: IconCache.icon(for: path)).resizable().interpolation(.high).frame(width: 24, height: 24)
                    } else {
                        VigieTile(symbol: "puzzlepiece.extension", size: 24)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(group.name).font(.system(size: 12.5, weight: .medium)).lineLimit(1)
                            Chip(text: tr("\(group.items.count) éléments", "\(group.items.count) items"), tint: .secondary)
                        }
                        Text(summary(running: running, off: off)).font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 6)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                }
                .padding(.horizontal, flat ? 0 : 12)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(hovering ? Color.primary.opacity(0.04) : .clear)
            .onHover { hovering = $0 }
            if expanded {
                VStack(spacing: 0) {
                    ForEach(group.items) { item in
                        Divider().padding(.leading, flat ? 34 : 46)
                        StartupRow(item: item).padding(.leading, 22)
                    }
                }
                .background(Color.primary.opacity(0.025))
            }
        }
    }

    private func summary(running: Int, off: Int) -> String {
        var parts: [String] = []
        if running > 0 { parts.append(tr("\(running) en marche", "\(running) running")) }
        if off > 0 { parts.append(tr("\(off) coupé\(off > 1 ? "s" : "")", "\(off) off")) }
        let ready = group.items.count - running - off
        if ready > 0 { parts.append(tr("\(ready) prêt\(ready > 1 ? "s" : "")", "\(ready) ready")) }
        return parts.joined(separator: " · ")
    }
}

struct StartupRow: View {
    /// Dans une case de la fenêtre, la carte perd son cadre : les lignes s'alignent sur le titre.
    @Environment(\.flatCards) private var flat
    @Environment(AppModel.self) private var model
    let item: StartupItem

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if let path = item.ownerPath, FileManager.default.fileExists(atPath: path) {
                Image(nsImage: IconCache.icon(for: path)).resizable().interpolation(.high).frame(width: 24, height: 24)
            } else {
                VigieTile(symbol: symbol, tint: VigieTheme.accent, size: 24)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.displayName).font(.system(size: 12.5, weight: .medium)).lineLimit(1)
                    Chip(text: state.text, tint: state.color)
                }
                Text(item.explanation.text).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if model.isDeveloper {
                    Text(item.label + (item.program.map { " · " + storagePath($0) } ?? ""))
                        .font(.system(size: 10, design: .monospaced)).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.middle)
                }
            }
            Spacer(minLength: 6)
            if item.canToggle {
                Toggle("", isOn: Binding(get: { item.isEnabled }, set: { model.setStartupItem(item, enabled: $0) }))
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
                    .help(item.isEnabled ? tr("Couper : l'arrêter et ne plus le lancer à l'ouverture de session. Réversible.", "Turn off: stop it and no longer start it at login. Reversible.")
                                         : tr("Le relancer, et à chaque ouverture de session.", "Start it again, and at every login."))
            }
        }
        .padding(.horizontal, flat ? 0 : 12)
        .padding(.vertical, 8)
    }

    private var symbol: String {
        switch item.kind {
        case .updater: return "arrow.down.circle"
        case .helper: return "puzzlepiece.extension"
        case .script: return "terminal"
        case .service: return "gearshape"
        }
    }

    private var state: (text: String, color: Color) {
        if !item.isEnabled { return (tr("coupé", "off"), .secondary) }
        if item.isRunning { return (tr("en marche", "running"), .green) }
        return (tr("prêt", "ready"), .secondary)
    }
}

/// Prévenir quand le Mac ralentit : désactivé par défaut, car Vigie regarde alors une fois par minute même fermée.
struct AlertsCard: View {
    @Environment(AppModel.self) private var model
    let compact: Bool

    var body: some View {
        @Bindable var model = model
        VigieCard(padding: compact ? 12 : 16) {
            VStack(alignment: .leading, spacing: 6) {
                Toggle(isOn: $model.speedAlertsEnabled) {
                    Text(tr("Me prévenir si le Mac ralentit", "Warn me when the Mac slows down")).font(.system(size: 12.5, weight: .semibold))
                }
                .toggleStyle(.switch)
                .controlSize(.small)
                Text(tr("Une notification quand une app fait travailler ton Mac depuis 5 min (avec un bouton pour la quitter), quand la mémoire manque vraiment, quand il chauffe, ou quand une app l'empêche de dormir depuis 30 min sur batterie. Pas plus d'une fois par heure pour la même chose. Vigie regarde alors une fois par minute, même fermée.",
                        "A notification when an app has been working your Mac for 5 min (with a button to quit it), when memory really runs out, when it gets hot, or when an app keeps it awake for 30 min on battery. At most once an hour for the same thing. Vigie then checks once a minute, even when closed."))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if model.speedAlertsEnabled, model.notificationsAllowed == false {
                    HStack(spacing: 6) {
                        Text(tr("macOS bloque les notifications de Vigie.", "macOS blocks Vigie's notifications."))
                            .font(.system(size: 11, weight: .medium)).foregroundStyle(.orange)
                        Button(tr("Les autoriser", "Allow them")) { model.openNotificationSettings() }
                            .buttonStyle(.borderless).font(.system(size: 11, weight: .medium))
                    }
                }
            }
        }
    }
}

/// Page de la fenêtre.
struct SpeedPage: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                PageHeader(title: tr("Vitesse et batterie", "Speed and battery"),
                           subtitle: tr("Pourquoi ton Mac est lent, chauffe ou vide sa batterie, et quoi faire.",
                                        "Why your Mac is slow, hot or draining its battery, and what to do.")) { EmptyView() }
                // La grille prend toute la largeur de la fenêtre.
                SpeedBento()
                    .padding(.horizontal, VigieTheme.pagePadding)
                    .padding(.bottom, WindowGrid.pageBottom)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// La page de la fenêtre en grille : l'état du Mac en haut, puis des cases côte à côte, ce qui démarre en bas.
/// (Le panneau, trop étroit, garde une colonne : `PerformanceView`.)
struct SpeedBento: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if model.demoSection == "demarrage" {
            BentoCell { StartupSection(compact: false) }
        } else {
            content
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 16) {
            // En haut, trois cartes de même taille : l'état du Mac, la température, l'alerte de ralentissement.
            HStack(alignment: .top, spacing: 16) {
                SpeedStateTile()
                ThermalTile()
                AlertsTile()
            }
            .fixedSize(horizontal: false, vertical: true)
            Grid(horizontalSpacing: 16, verticalSpacing: 16) {
                GridRow(alignment: .top) {
                    BentoCell { BusySection(compact: false) }
                    BentoCell { MemorySection(compact: false) }
                }
                GridRow(alignment: .top) {
                    if let battery = model.performance?.battery {
                        BentoCell { BatterySection(battery: battery, compact: false) }
                        BentoCell { StartupSection(compact: false) }
                    } else {
                        BentoCell { StartupSection(compact: false) }
                            .gridCellColumns(2)
                    }
                }
            }
        }
    }
}

// MARK: - Les trois cartes du haut

/// Carte de la rangée du haut : icône et titre, une phrase, et en bas une action ou un réglage.
struct TopTile<Footer: View>: View {
    @Environment(AppModel.self) private var model
    let symbol: String
    let tint: Color
    let title: String
    let text: String
    var lesson: String? = nil
    @ViewBuilder var footer: Footer

    /// Le mini-graphique de la tuile, d'après ce qu'elle montre (mémoire, disque, processeur).
    private var trend: [Double] { TileTrend(symbol: symbol)?.values(model) ?? [] }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // En haut : le pictogramme et le point d'état, comme l'étiquette d'une tuile de chiffres.
            HStack(spacing: 7) {
                Image(systemName: symbol)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(DS.secondaryText)
                    .frame(width: 16)
                Circle().fill(tint).frame(width: 7, height: 7)
                Spacer(minLength: 0)
                if let lesson { LearnMoreLink(lesson: lesson) }
            }
            // Le chiffre en grand, son unité en petit (« 182 Go libres »), sinon la phrase en titre.
            if let figure = TileFigure(title) {
                HStack(alignment: .lastTextBaseline, spacing: 5) {
                    Text(figure.number).font(.system(size: 28, weight: .semibold).monospacedDigit())
                        .fixedSize().layoutPriority(2)
                    // L'unité passe avant le graphique : elle rétrécit un peu plutôt que d'être coupée.
                    Text(figure.rest).font(.system(size: 13.5, weight: .medium)).foregroundStyle(DS.secondaryText)
                        .lineLimit(1).minimumScaleFactor(0.75).layoutPriority(1)
                    Spacer(minLength: 6)
                    if trend.count >= 3 { TrendBars(values: trend) }
                }
            } else {
                HStack(alignment: .bottom, spacing: 8) {
                    Text(title).font(.system(size: 16, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    if trend.count >= 3 { TrendBars(values: trend) }
                }
            }
            Text(text).font(.system(size: 12)).foregroundStyle(DS.secondaryText).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            footer
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .panelSurface()
    }
}

/// « Ton Mac est rapide » / « Ton Mac manque de mémoire » : le point vert, orange ou rouge dit l'état.
struct SpeedStateTile: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let health = model.speedHealth {
            TopTile(symbol: "gauge.with.needle", tint: StatusCard.color(health.level), title: health.title, text: health.message) {
                if case .quit(let id, let name)? = health.action, model.closeState(id) == .confirming {
                    HStack(spacing: 8) {
                        Button(tr("Quitter \(name) ?", "Quit \(name)?")) { model.performHealthAction(fromPanel: false, health: health) }
                            .buttonStyle(DangerButtonStyle())
                        Button(tr("Annuler", "Cancel")) { model.cancelConfirmation(id) }.buttonStyle(.borderless)
                    }
                } else if let title = Self.shortTitle(health) {
                    Button(title) { model.performHealthAction(fromPanel: false, health: health) }
                        .buttonStyle(.borderedProminent)
                        .tint(VigieTheme.accent)
                }
            }
        }
    }
}

extension SpeedStateTile {
    /// Titre court du bouton, pour un tiers de largeur.
    static func shortTitle(_ health: MacHealth) -> String? {
        switch health.action {
        case .showMemory?: return tr("Voir la mémoire", "See memory")
        case .quit(_, let name)?: return tr("Quitter \(name)", "Quit \(name)")
        default: return health.actionTitle()
        }
    }
}

struct ThermalTile: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let thermal = model.performance?.thermal ?? .normal
        let (title, text, color): (String, String, Color) = {
            switch thermal {
            case .normal: return (tr("Température normale", "Normal temperature"), tr("Ton Mac ne chauffe pas : rien à signaler.", "Your Mac isn't hot: nothing to report."), .green)
            case .warm: return (tr("Un peu chaud", "A bit warm"), tr("Normal quand il travaille beaucoup ; rien à faire.", "Normal when it works hard; nothing to do."), .green)
            case .hot: return (tr("Chaud", "Hot"), tr("macOS ralentit le processeur pour le refroidir. Quitter l'app qui travaille le plus aide.", "macOS is slowing the processor to cool it. Quitting the busiest app helps."), .orange)
            case .critical: return (tr("Très chaud", "Very hot"), tr("macOS ralentit fortement le Mac. Quitte les apps gourmandes et laisse-le respirer.", "macOS is slowing the Mac a lot. Quit hungry apps and let it breathe."), .red)
            }
        }()
        TopTile(symbol: "thermometer.medium", tint: color, title: title, text: text) { EmptyView() }
    }
}

struct AlertsTile: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        TopTile(symbol: "bell", tint: model.speedAlertsEnabled ? .green : Color.secondary.opacity(0.5),
                title: tr("Me prévenir si le Mac ralentit", "Warn me when the Mac slows down"),
                text: tr("Une notification si une app fait travailler ton Mac depuis 5 min, si la mémoire manque, s'il chauffe ou si une app l'empêche de dormir. Au plus une fois par heure.",
                         "A notification if an app has worked your Mac for 5 min, memory runs out, it gets hot or an app keeps it awake. At most once an hour.")) {
            VStack(alignment: .leading, spacing: 6) {
                Toggle(tr("Activer les alertes", "Turn on alerts"), isOn: $model.speedAlertsEnabled)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                if model.speedAlertsEnabled, model.notificationsAllowed == false {
                    Button(tr("macOS les bloque : les autoriser", "macOS blocks them: allow")) { model.openNotificationSettings() }
                        .buttonStyle(.borderless)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.orange)
                }
            }
        }
    }
}


/// « 182 Go libres » → « 182 » en grand et « Go libres » en petit ; une phrase sans chiffre en tête reste un titre.
struct TileFigure {
    let number: String
    let rest: String

    init?(_ title: String) {
        let scalars = Array(title)
        var index = 0
        if index < scalars.count, "+-−".contains(scalars[index]) { index += 1 }
        let start = index
        while index < scalars.count, scalars[index].isNumber || ",. \u{202F}\u{00A0}".contains(scalars[index]) && index + 1 < scalars.count && scalars[index + 1].isNumber {
            index += 1
        }
        guard index > start else { return nil }
        number = String(scalars[0..<index])
        rest = String(scalars[index...]).trimmingCharacters(in: .whitespaces)
    }
}


/// Ce que dessine le mini-graphique d'une tuile, selon son icône.
enum TileTrend {
    case memory, cpu, disk

    init?(symbol: String) {
        switch symbol {
        case "memorychip": self = .memory
        case "gauge.with.needle": self = .cpu
        case "internaldrive": self = .disk
        default: return nil
        }
    }

    /// Les dernières valeurs, de la plus ancienne à la plus récente (au plus 8).
    @MainActor
    func values(_ model: AppModel) -> [Double] {
        switch self {
        case .memory:
            let live = model.liveSamples.map { Double($0.memory) }
            if live.count >= 3 { return Array(live.suffix(8)) }
            return Array(model.history.compactMap { $0.memoryUsed.map(Double.init) }.suffix(8))
        case .cpu:
            return Array(model.liveSamples.map(\.cpu).suffix(8))
        case .disk:
            // Une valeur par jour : la dernière mesure de chaque jour.
            let calendar = Calendar.current
            var byDay: [Date: Double] = [:]
            for point in model.history where point.storage == nil {
                byDay[calendar.startOfDay(for: point.date)] = Double(point.diskUsed)
            }
            return Array(byDay.sorted { $0.key < $1.key }.map(\.value).suffix(8))
        }
    }
}

/// Le mini-graphique d'une tuile de chiffres : des barres grises, la plus récente en bleu ;
/// la hauteur montre l'écart entre le plus bas et le plus haut, pour que la variation se voie.
struct TrendBars: View {
    let values: [Double]

    var body: some View {
        let low = values.min() ?? 0
        let high = values.max() ?? 1
        let span = max(high - low, high * 0.02, 1)
        HStack(alignment: .bottom, spacing: 2.5) {
            ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(index == values.count - 1 ? DS.accent : DS.secondaryText.opacity(0.45))
                    .frame(width: 4, height: 5 + 17 * (value - low) / span)
            }
        }
        .frame(height: 22, alignment: .bottom)
        .accessibilityHidden(true)
    }
}
