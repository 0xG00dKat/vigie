import AppKit
import SwiftUI
import VigieCore

// Le panneau de la barre des menus en verre : un fond translucide, des cartes à peine plus claires et très arrondies,
// des chiffres en grand, des mini-graphiques, l'ambre pour ce qui vient de se passer. Pas de vert d'eau.

/// Couleurs et formes du panneau en verre.
enum Glass {
    /// Ambre : les dernières heures, ce qui est à nettoyer.
    static let amber = Color(red: 1.0, green: 0.71, blue: 0.24)
    /// Vert doux : « en direct ».
    static let live = Color(red: 0.47, green: 0.76, blue: 0.56)
    static let radius: CGFloat = 16

    static func card(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.065) : Color.white.opacity(0.62)
    }
    static func cardRaised(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.11) : Color.white.opacity(0.9)
    }
    static func stroke(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.07) : Color.black.opacity(0.06)
    }
    static func track(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.08)
    }
}

/// Le fond en verre du panneau.
struct GlassBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

extension View {
    /// Une carte du panneau en verre.
    func glassCard(raised: Bool = false) -> some View {
        modifier(GlassCardModifier(raised: raised))
    }
}

private struct GlassCardModifier: ViewModifier {
    let raised: Bool
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        content
            .background(RoundedRectangle(cornerRadius: Glass.radius, style: .continuous)
                .fill(raised ? Glass.cardRaised(scheme) : Glass.card(scheme)))
            .overlay(RoundedRectangle(cornerRadius: Glass.radius, style: .continuous)
                .strokeBorder(Glass.stroke(scheme), lineWidth: 0.5))
    }
}

// MARK: - Le panneau

/// Le panneau : l'en-tête, trois tuiles, l'état du Mac en anneaux, la mémoire sur 24 heures, « À faire »,
/// « En direct » (tes serveurs, ou ce qui pèse le plus), et la recherche en bas.
struct GlassPanel: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var scheme
    /// Faux à la fermeture : à chaque ouverture, les cartes apparaissent l'une après l'autre.
    @State private var shown = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            GlassHeader().reveal(0, shown)
            // Une nouvelle version, ou le résultat d'une recherche lancée à la main.
            if let update = model.visibleUpdate { GlassUpdateCard(state: update).reveal(1, shown) }
            if model.isSearching {
                GlassSearchResults()
            } else if model.snapshot == nil {
                ProgressView(tr("Lecture des processus…", "Reading processes…"))
                    .controlSize(.small)
                    .frame(maxWidth: .infinity)
                    .padding(24)
            } else {
                GlassTiles().reveal(1, shown)
                MacRingsCard().reveal(2, shown)
                MemoryDayCard().reveal(3, shown)
                GlassTodoCard().reveal(4, shown)
                LiveCard().reveal(5, shown)
            }
            GlassSearchField().reveal(6, shown)
        }
        .padding(10)
        .frame(width: 450)
        .fixedSize(horizontal: false, vertical: true)
        .background {
            ZStack {
                GlassBackground()
                // Un peu plus sombre que le verre de macOS, comme un HUD.
                if scheme == .dark { Color.black.opacity(0.22) }
            }
            .ignoresSafeArea()
        }
        .animation(VigieMotion.standard, value: model.isSearching)
        .background(WindowVisibilityObserver { visible in
            if visible {
                withAnimation { shown = true }
            } else {
                shown = false
            }
        })
        // Les captures (Mac fictif) montrent le panneau déjà ouvert.
        .onAppear { if model.isDemo { shown = true } }
    }
}

extension View {
    /// Apparition d'une carte à l'ouverture du panneau : un fondu et une petite montée, en décalé, en ressort doux.
    func reveal(_ index: Int, _ shown: Bool) -> some View {
        modifier(RevealModifier(index: index, shown: shown))
    }
}

private struct RevealModifier: ViewModifier {
    let index: Int
    let shown: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 10)
            .scaleEffect(shown || reduceMotion ? 1 : 0.985, anchor: .top)
            .animation(shown
                       ? (reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.42, dampingFraction: 0.86).delay(Double(index) * 0.035))
                       : nil,
                       value: shown)
    }
}

// MARK: - En-tête

private struct GlassHeader: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 8) {
            LogoMark(color: DS.primaryText)
                .frame(width: 17)
            Text("Vigie").font(.system(size: 14, weight: .semibold))
            Text(model.isDeveloper ? tr("Dev", "Dev") : "")
                .font(.system(size: 14))
                .foregroundStyle(DS.secondaryText)
            Spacer(minLength: 8)
            GlassIconButton(symbol: "arrow.clockwise", help: tr("Actualiser", "Refresh")) { model.refreshAndReorder() }
            GlassIconButton(symbol: scheme == .dark ? "sun.max" : "moon", help: tr("Clair ou sombre", "Light or dark")) {
                ThemeSwitcher.switchTo(scheme == .dark ? .light : .dark, from: nil)
            }
            SettingsMenu(round: true, inPanel: true, plain: true)
            GlassIconButton(symbol: "macwindow", help: tr("Ouvrir Vigie (⌘O)", "Open Vigie (⌘O)")) {
                DockPresence.openFromPanel(dismiss)
            }
            .keyboardShortcut("o")
        }
        .padding(.horizontal, 6)
        .padding(.top, 2)
        .padding(.bottom, 2)
    }
}

/// Une icône de l'en-tête : sans fond, un léger fond au survol.
struct GlassIconButton: View {
    let symbol: String
    let help: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(hovering ? DS.primaryText : DS.secondaryText)
                .frame(width: 26, height: 26)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.primary.opacity(hovering ? 0.08 : 0)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
    }
}

// MARK: - Les trois tuiles

private struct GlassTiles: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let apps = model.visibleGroups(in: .apps)
        let appsMemory = apps.reduce(UInt64(0)) { $0 + $1.memory }
        let second = model.isDeveloper ? model.visibleGroups(in: .dev).filter { !$0.ports.isEmpty } : model.visibleGroups(in: .background)
        let safe = model.safeCleanItems.reduce(UInt64(0)) { $0 + $1.size }
        let safeText = Format.bytes(safe, decimal: true).split(separator: " ")
        HStack(spacing: 6) {
            GlassTile(label: tr("Apps", "Apps"), status: tr("En direct", "Live"), value: "\(apps.count)", unit: nil) {
                Text(Format.bytes(appsMemory)).font(.system(size: 11.5)).foregroundStyle(DS.secondaryText).monospacedDigit()
            } action: { open(.running) }
            GlassTile(label: model.isDeveloper ? tr("Serveurs", "Servers") : tr("Arrière-plan", "Background"),
                      status: nil, value: "\(second.count)", unit: nil) {
                MiniBars(values: second.prefix(14).map { Double($0.memory) })
            } action: { open(model.isDeveloper ? .ports : .running) }
            GlassTile(label: tr("À nettoyer", "Clean up"), status: nil,
                      value: String(safeText.first ?? "0"), unit: safeText.count > 1 ? String(safeText[1]) : nil) {
                Capsule().fill(Glass.amber)
                    .frame(width: max(14, 56 * min(1, Double(safe) / 50_000_000_000)), height: 4)
            } action: { open(.storage(.cache)) }
        }
    }

    private func open(_ page: WindowPage) {
        model.windowPageRequest = page
        DockPresence.openFromPanel(dismiss)
    }
}

/// Une tuile : l'étiquette en haut (et un statut à droite), un grand chiffre, et un petit dessin à droite.
private struct GlassTile<Trailing: View>: View {
    let label: String
    let status: String?
    let value: String
    let unit: String?
    var raised = false
    @ViewBuilder var trailing: Trailing
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(label).font(.system(size: 11.5, weight: .medium)).foregroundStyle(DS.secondaryText).lineLimit(1)
                    Spacer(minLength: 4)
                    if let status {
                        Text(status).font(.system(size: 10.5, weight: .medium)).foregroundStyle(Glass.live)
                    }
                }
                HStack(alignment: .lastTextBaseline, spacing: 3) {
                    Text(value).font(.system(size: 21, weight: .semibold).monospacedDigit()).contentTransition(.numericText())
                    if let unit {
                        Text(unit).font(.system(size: 11.5, weight: .medium)).foregroundStyle(DS.secondaryText)
                    }
                    Spacer(minLength: 4)
                    trailing
                }
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard(raised: raised || hovering)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(VigieMotion.quick, value: hovering)
    }
}

/// Petites barres côte à côte ; la dernière en ambre.
struct MiniBars: View {
    let values: [Double]

    var body: some View {
        let top = max(values.max() ?? 1, 1)
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                Capsule()
                    .fill(index == values.count - 1 ? Glass.amber : DS.secondaryText.opacity(0.55))
                    .frame(width: 2.5, height: max(3, 16 * value / top))
            }
        }
        .frame(height: 16, alignment: .bottom)
    }
}

// MARK: - Mon Mac en anneaux

private struct MacRingsCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(tr("Mon Mac", "My Mac")).font(.system(size: 12.5, weight: .semibold))
            HStack(alignment: .center, spacing: 0) {
                if let snapshot = model.snapshot {
                    let pressure = model.performance?.memory.pressure
                    RingStat(symbol: "memorychip", fraction: Double(snapshot.memoryUsed) / Double(max(snapshot.memoryTotal, 1)),
                             tint: pressure == .critical ? DS.urgent : pressure == .warning ? DS.review : DS.primaryText,
                             label: tr("Mémoire", "Memory"), value: Format.bytes(snapshot.memoryUsed),
                             detail: tr("sur \(Format.bytes(snapshot.memoryTotal))", "of \(Format.bytes(snapshot.memoryTotal))"))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if let disk = model.disk {
                    RingStat(symbol: "internaldrive", fraction: 1 - Double(disk.available) / Double(max(disk.total, 1)),
                             tint: disk.isLow ? DS.urgent : disk.isTight ? DS.review : DS.primaryText,
                             label: tr("Disque", "Disk"), value: Format.bytes(disk.available, decimal: true),
                             detail: tr("libres", "free"))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if let battery = model.performance?.battery {
                    RingStat(symbol: battery.charging ? "bolt.fill" : "battery.75percent", fraction: Double(battery.percent) / 100,
                             tint: battery.percent <= 15 && !battery.onPower ? DS.urgent : DS.primaryText,
                             label: tr("Batterie", "Battery"), value: "\(battery.percent) %",
                             detail: battery.charging ? tr("en charge", "charging")
                                 : battery.minutesRemaining.map { tr("\($0 / 60) h \(String(format: "%02d", $0 % 60))", "\($0 / 60) h \(String(format: "%02d", $0 % 60))") }
                                 ?? (battery.onPower ? tr("sur secteur", "on power") : ""))
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else if let snapshot = model.snapshot {
                    let cores = Double(max(ProcessInfo.processInfo.activeProcessorCount, 1))
                    let cpu = min(100, snapshot.groups.reduce(0.0) { $0 + $1.cpuPercent } / cores)
                    RingStat(symbol: "gauge.with.needle", fraction: cpu / 100, tint: DS.primaryText,
                             label: tr("Processeur", "CPU"), value: "\(Int(cpu.rounded())) %", detail: tr("utilisé", "used"))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(12)
        .glassCard()
    }
}

/// Un anneau (avec son icône au centre), et à côté : ce que c'est, le chiffre, une précision.
private struct RingStat: View {
    let symbol: String
    let fraction: Double
    let tint: Color
    let label: String
    let value: String
    let detail: String
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 7) {
            ZStack {
                Circle().stroke(Glass.track(scheme), lineWidth: 3.5)
                Circle()
                    .trim(from: 0, to: max(0.02, min(1, fraction)))
                    .stroke(tint, style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Image(systemName: symbol)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(DS.secondaryText)
            }
            .frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 0) {
                Text(label).font(.system(size: 10.5)).foregroundStyle(DS.secondaryText)
                Text(value).font(.system(size: 14.5, weight: .semibold).monospacedDigit()).lineLimit(1).minimumScaleFactor(0.8)
                Text(detail).font(.system(size: 10.5)).foregroundStyle(DS.secondaryText).lineLimit(1)
            }
        }
    }
}

// MARK: - La mémoire sur 24 heures

private struct MemoryDayCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let slots = Self.hourly(model.history)
        if slots.contains(where: { $0 != nil }) {
            let peak = slots.compactMap { $0 }.max() ?? 0
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(tr("Mémoire · 24 dernières heures", "Memory · last 24 hours")).font(.system(size: 12.5, weight: .semibold))
                    Spacer()
                    Text(tr("au plus \(Format.bytes(peak))", "peak \(Format.bytes(peak))"))
                        .font(.system(size: 11.5, weight: .medium)).foregroundStyle(DS.secondaryText)
                }
                DayBars(slots: slots)
                HStack {
                    Text(Self.startLabel).font(.system(size: 10.5)).foregroundStyle(DS.secondaryText)
                    Spacer()
                    Text(tr("Maintenant", "Now")).font(.system(size: 10.5)).foregroundStyle(DS.secondaryText)
                }
            }
            .padding(12)
            .glassCard()
        }
    }

    /// La mémoire utilisée heure par heure sur les 24 dernières heures (nil : pas de mesure cette heure-là).
    static func hourly(_ points: [HistoryPoint], now: Date = Date()) -> [UInt64?] {
        let hour = Calendar.current.dateInterval(of: .hour, for: now)?.start ?? now
        return (0..<24).reversed().map { back in
            let start = hour.addingTimeInterval(-Double(back) * 3600)
            let end = start.addingTimeInterval(3600)
            return points.last { $0.date >= start && $0.date < end && $0.memoryUsed != nil }?.memoryUsed
        }
    }

    static var startLabel: String {
        let start = Date().addingTimeInterval(-23 * 3600)
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:00"
        return tr("Hier \(formatter.string(from: start))", "Yesterday \(formatter.string(from: start))")
    }
}

/// 24 barres : grises, les trois dernières heures en ambre ; une heure sans mesure reste un petit trait.
private struct DayBars: View {
    let slots: [UInt64?]
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let top = Double(max(slots.compactMap { $0 }.max() ?? 1, 1))
        GeometryReader { geometry in
            let gap: CGFloat = 3
            let width = (geometry.size.width - gap * CGFloat(slots.count - 1)) / CGFloat(slots.count)
            HStack(alignment: .bottom, spacing: gap) {
                ForEach(Array(slots.enumerated()), id: \.offset) { index, slot in
                    RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                        .fill(slot == nil ? Glass.track(scheme)
                              : index >= slots.count - 3 ? Glass.amber : DS.secondaryText.opacity(scheme == .dark ? 0.55 : 0.4))
                        .frame(width: width, height: slot.map { max(6, geometry.size.height * Double($0) / top) } ?? 4)
                }
            }
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .frame(height: 44)
    }
}

// MARK: - À faire

private struct GlassTodoCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let all = QuickActionsSection.actions(model)
        // Les deux plus urgentes ; le reste attend dans la fenêtre.
        let actions = Array(all.prefix(2))
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(tr("À faire", "To do")).font(.system(size: 12.5, weight: .semibold))
                if !all.isEmpty {
                    Text("\(all.count)").font(.system(size: 12.5)).foregroundStyle(DS.secondaryText)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            if actions.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(DS.safe)
                    Text(tr("Rien à faire, ton Mac va bien.", "Nothing to do, your Mac is fine.")).font(.system(size: 12.5))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            } else {
                ForEach(Array(actions.enumerated()), id: \.element.id) { index, action in
                    if index > 0 { Divider().padding(.leading, 30).padding(.trailing, 12).opacity(0.5) }
                    QuickActionRow(action: action)
                        .padding(.horizontal, 2)
                }
            }
        }
        .padding(.bottom, 2)
        .glassCard()
    }
}

// MARK: - En direct

/// Mode Développeur : tes serveurs en arbre (le projet, puis chaque port). Mode Simple : ce qui pèse le plus.
private struct LiveCard: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let servers = model.visibleGroups(in: .dev).filter { !$0.ports.isEmpty }
        let developer = model.isDeveloper && !servers.isEmpty
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(developer ? tr("En direct", "Live") : tr("Ce qui pèse le plus", "Using the most")).font(.system(size: 12.5, weight: .semibold))
                if developer { Text("\(servers.count)").font(.system(size: 12.5)).foregroundStyle(DS.secondaryText) }
                Spacer()
                Button(tr("Tout voir", "See all")) {
                    model.windowPageRequest = developer ? .ports : .running
                    DockPresence.openFromPanel(dismiss)
                }
                .buttonStyle(.plain)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(DS.secondaryText)
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            if developer {
                ForEach(servers.prefix(2)) { group in
                    ServerTree(group: group)
                }
            } else {
                ForEach(model.memoryGroups.prefix(3)) { group in
                    CompactGroupRow(group: group)
                        .padding(.horizontal, 2)
                }
            }
        }
        .padding(.bottom, 8)
        .glassCard()
    }
}

/// Un projet et ses ports, reliés par un trait.
private struct ServerTree: View {
    @Environment(AppModel.self) private var model
    let group: ProcessGroup
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Text(String(group.title.prefix(1)).uppercased())
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(scheme == .dark ? Color.black : .white)
                    .frame(width: 24, height: 24)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(DS.primaryText))
                Text(group.title).font(.system(size: 12.5, weight: .medium)).lineLimit(1)
                if let location = group.location {
                    Text(location).font(.system(size: 11.5)).foregroundStyle(DS.secondaryText).lineLimit(1).truncationMode(.middle)
                }
                Spacer(minLength: 6)
                Text(Format.bytes(group.memory)).font(.system(size: 11.5)).foregroundStyle(DS.secondaryText).monospacedDigit()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            ForEach(Array(group.ports.prefix(1).enumerated()), id: \.element) { index, port in
                HStack(spacing: 10) {
                    // Le trait de l'arbre.
                    TreeConnector(last: true)
                        .stroke(Glass.track(scheme), lineWidth: 1.5)
                        .frame(width: 18, height: 34)
                    Image(systemName: "network")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(DS.secondaryText)
                        .frame(width: 26, height: 26)
                        .glassCard(raised: true)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(verbatim: "localhost:" + String(port)).font(.system(size: 12.5, weight: .medium)).monospacedDigit()
                        Text(group.exposedPorts.contains(port) ? tr("visible sur le Wi-Fi", "visible on the Wi-Fi") : tr("sur ce Mac", "on this Mac"))
                            .font(.system(size: 11.5))
                            .foregroundStyle(group.exposedPorts.contains(port) ? DS.review : DS.secondaryText)
                    }
                    Spacer(minLength: 6)
                    if group.close.isAllowed && !group.isProtected, index == 0 {
                        GroupCloseControl(group: group)
                    }
                    Button {
                        if let url = URL(string: "http://localhost:\(port)") { NSWorkspace.shared.open(url) }
                    } label: {
                        // Même taille que la croix d'arrêt à côté.
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 8.5, weight: .bold))
                            .foregroundStyle(DS.primaryText)
                            .frame(width: 18, height: 18)
                            .background(Circle().fill(Glass.cardRaised(scheme)))
                    }
                    .buttonStyle(.plain)
                    .help(tr("Ouvrir dans le navigateur", "Open in the browser"))
                }
                .padding(.leading, 24)
                .padding(.trailing, 14)
            }
        }
    }
}

/// Le coude de l'arbre : un trait qui descend et tourne vers la ligne.
private struct TreeConnector: Shape {
    let last: Bool

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + 1, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + 1, y: last ? rect.midY - 6 : rect.maxY))
        if last {
            path.addQuadCurve(to: CGPoint(x: rect.minX + 7, y: rect.midY), control: CGPoint(x: rect.minX + 1, y: rect.midY))
        } else {
            path.move(to: CGPoint(x: rect.minX + 1, y: rect.midY))
        }
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return path
    }
}

// MARK: - Recherche

private struct GlassSearchResults: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let groups = ProcessCategory.allCases.flatMap { model.visibleGroups(in: $0) }.sorted { $0.memory > $1.memory }
        VStack(alignment: .leading, spacing: 4) {
            Text(tr("\(groups.count) résultat\(groups.count > 1 ? "s" : "")", "\(groups.count) result\(groups.count > 1 ? "s" : "")"))
                .font(.system(size: 12.5, weight: .semibold))
                .padding(.horizontal, 14)
                .padding(.top, 12)
            if groups.isEmpty {
                Text(tr("Rien ne correspond à « \(model.query) ».", "Nothing matches “\(model.query)”."))
                    .font(.system(size: 12.5)).foregroundStyle(DS.secondaryText)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
            } else {
                ForEach(groups.prefix(8)) { group in
                    CompactGroupRow(group: group, showsPorts: model.isDeveloper).padding(.horizontal, 2)
                }
            }
        }
        .padding(.bottom, 8)
        .glassCard()
    }
}

/// La recherche, en bas : une app, un projet ou un port ; ⌘K pour y aller.
private struct GlassSearchField: View {
    @Environment(AppModel.self) private var model
    @FocusState private var focused: Bool

    var body: some View {
        @Bindable var model = model
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass").font(.system(size: 12.5, weight: .medium)).foregroundStyle(DS.secondaryText)
            TextField(model.isDeveloper ? tr("Filtrer par nom ou port…", "Filter by name or port…") : tr("Rechercher une app…", "Search for an app…"),
                      text: $model.query)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
                .focused($focused)
            if model.isSearching {
                Button { model.query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(DS.secondaryText) }
                    .buttonStyle(.plain)
            } else {
                Text("⌘K")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(DS.secondaryText)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(DS.secondaryText.opacity(0.5), lineWidth: 0.8))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .glassCard()
        .background {
            // ⌘K : la recherche prend la main.
            Button("") { focused = true }.keyboardShortcut("k").opacity(0)
        }
    }
}

// MARK: - Mise à jour

/// Le bandeau de mise à jour du panneau : une carte de verre, l'icône en bleu, les boutons en pastilles.
private struct GlassUpdateCard: View {
    @Environment(AppModel.self) private var model
    let state: UpdateState

    var body: some View {
        switch state {
        case .available(let release): available(release)
        case .checking: line(icon: "arrow.triangle.2.circlepath", tint: DS.secondaryText, text: tr("Recherche d'une mise à jour…", "Checking for updates…"), closable: false)
        case .upToDate: line(icon: "checkmark.circle.fill", tint: DS.safe,
                             text: tr("Vigie est à jour (\(model.currentVersion?.description ?? "?")).", "Vigie is up to date (\(model.currentVersion?.description ?? "?")).") , closable: true)
        case .failed: line(icon: "exclamationmark.triangle.fill", tint: DS.review, text: tr("Impossible de vérifier les mises à jour.", "Couldn't check for updates."), closable: true)
        case .idle: EmptyView()
        }
    }

    private func available(_ release: ReleaseInfo) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(DS.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(tr("Vigie \(release.version) est disponible", "Vigie \(release.version) is available"))
                        .font(.system(size: 12.5, weight: .semibold))
                    Text(release.summary.isEmpty
                         ? tr("Tu as la \(model.currentVersion?.description ?? "?").", "You have \(model.currentVersion?.description ?? "?").")
                         : release.summary)
                        .font(.system(size: 11.5))
                        .foregroundStyle(DS.secondaryText)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 6)
                closeButton
            }
            HStack(spacing: 8) {
                Button(tr("Télécharger", "Download")) { model.open(release.downloadURL ?? release.pageURL) }
                    .buttonStyle(HUDPillButtonStyle(prominent: true))
                Button(tr("Nouveautés", "What's new")) { model.open(release.pageURL) }
                    .buttonStyle(HUDPillButtonStyle())
            }
            .padding(.leading, 28)
        }
        .padding(12)
        .glassCard(raised: true)
    }

    private func line(icon: String, tint: Color, text: String, closable: Bool) -> some View {
        HStack(spacing: 9) {
            Image(systemName: icon).foregroundStyle(tint)
            Text(text).font(.system(size: 12.5)).lineLimit(1)
            Spacer(minLength: 6)
            if closable { closeButton }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .glassCard()
    }

    private var closeButton: some View {
        Button { model.dismissUpdateMessage() } label: {
            Image(systemName: "xmark").font(.system(size: 10, weight: .semibold)).foregroundStyle(DS.secondaryText)
        }
        .buttonStyle(.plain)
        .help(tr("Fermer", "Close"))
    }
}
