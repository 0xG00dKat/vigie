import AppKit
import SwiftUI
import VigieCore

/// Nouveau design de Vigie (en essai, derrière la clé `nouveauDesign` ou l'option de rendu `--redesign`).
///
/// Un seul langage visuel, décliné selon le thème du Mac :
/// - en clair, des cartes blanches qui flottent sur un fond gris doux, des ombres légères, de grands arrondis ;
/// - en sombre, une console : fond presque noir bleuté, cartes à bord fin, chiffres en monospace.
/// Le risque se lit comme un niveau de journal : SÛR (vert), À VÉRIFIER (orange), À GARDER (gris), URGENT (rouge).
/// Peu de couleurs, chacune avec un seul sens (voir la règle plus bas).
enum DS {
    // MARK: Couleurs (claires / sombres)

    static func dynamic(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        })
    }

    static func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
        NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }

    /// Fond uni (panneau, fenêtre) : gris très doux en clair, presque noir neutre en sombre, sans effet translucide.
    static let canvas = dynamic(light: rgb(0xF2F2F3), dark: rgb(0x171717))
    /// Carte : un voile clair sur le verre de la fenêtre (translucide).
    static let surface = dynamic(light: rgb(0xFFFFFF, 0.62), dark: rgb(0xFFFFFF, 0.065))
    /// Creux (bac des onglets, bouton rond, piste d'une barre, bouton secondaire).
    static let well = dynamic(light: rgb(0x000000, 0.05), dark: rgb(0xFFFFFF, 0.07))
    /// Onglet choisi dans son bac.
    static let wellSelected = dynamic(light: rgb(0xFFFFFF, 0.95), dark: rgb(0xFFFFFF, 0.13))
    /// Bord fin des cartes et des pilules.
    static let stroke = dynamic(light: rgb(0x000000, 0.07), dark: rgb(0xFFFFFF, 0.08))
    static let separator = dynamic(light: rgb(0x000000, 0.06), dark: rgb(0xFFFFFF, 0.06))
    static let primaryText = dynamic(light: rgb(0x121314), dark: rgb(0xEDEEF0))
    static let secondaryText = dynamic(light: rgb(0x6C6E73), dark: rgb(0x8E9196))
    static let tertiaryText = dynamic(light: rgb(0xA0A2A7), dark: rgb(0x5E6166))

    // Règle des couleurs : chacune a un seul sens.
    // Gris et noir : toute l'interface. Accent (bleu doux) : ce qui est choisi ou actif, les liens et les données neutres.
    // Vert : sûr. Orange : à vérifier. Rouge : danger seulement (quitter, arrêter, supprimer, urgent).
    static let accent = dynamic(light: rgb(0x2F6FDE), dark: rgb(0x6EA8FF))
    static let safe = dynamic(light: rgb(0x3BA54A), dark: rgb(0x4FCB62))
    static let review = dynamic(light: rgb(0xE07B1F), dark: rgb(0xFFA23D))
    static let keep = dynamic(light: rgb(0x8C8E93), dark: rgb(0x7D8086))
    static let urgent = dynamic(light: rgb(0xE04646), dark: rgb(0xF05656))

    // MARK: Formes et textes

    static let cardRadius: CGFloat = 16
    static let rowRadius: CGFloat = 10
    static let pagePadding: CGFloat = WindowGrid.pagePadding

    /// Badges, durées, identifiants : monospace, comme dans un outil de journaux.
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    /// Tailles et compteurs : police normale, chiffres de même largeur (les colonnes restent alignées).
    static func number(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight).monospacedDigit()
    }
}

// MARK: - Mouvement

/// Les animations de Vigie : douces, sans rebond brusque, les mêmes partout.
enum VigieMotion {
    /// Déplier, replier, changer de page ou de largeur.
    static let standard = Animation.smooth(duration: 0.32)
    /// Petits retours (survol, coche, filtre).
    static let quick = Animation.smooth(duration: 0.2)
    /// Ce qui glisse d'un endroit à l'autre (le filtre qui fusionne).
    static let glide = Animation.spring(response: 0.45, dampingFraction: 0.86)
}

// MARK: - Niveau (le risque, lu comme un niveau de journal)

enum DSLevel {
    case safe, review, keep, urgent, info

    var color: Color {
        switch self {
        case .safe: return DS.safe
        case .review: return DS.review
        case .keep: return DS.keep
        case .urgent: return DS.urgent
        case .info: return DS.accent
        }
    }

    var label: String {
        switch self {
        case .safe: return tr("SÛR", "SAFE")
        case .review: return tr("À VÉRIFIER", "REVIEW")
        case .keep: return tr("À GARDER", "KEEP")
        case .urgent: return tr("URGENT", "URGENT")
        case .info: return tr("INFO", "INFO")
        }
    }

    init(_ kind: StorageKind) {
        switch kind {
        case .cache, .project: self = .safe
        case .application, .largeFile, .leftover: self = .review
        case .appData, .personal, .systemData: self = .keep
        }
    }
}

/// « SÛR », « À VÉRIFIER » : petit badge en monospace sur fond teinté.
struct LevelBadge: View {
    let level: DSLevel
    var text: String? = nil

    var body: some View {
        Text(text ?? level.label)
            .font(DS.mono(10.5, .semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .foregroundStyle(level.color)
            .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(level.color.opacity(0.13)))
            .fixedSize()
    }
}

// MARK: - Carte

/// Carte : blanche et ombrée en clair, à bord fin en sombre.
struct DSCard<Content: View>: View {
    var padding: CGFloat = 20
    @ViewBuilder var content: Content
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: DS.cardRadius, style: .continuous).fill(DS.surface))
            .overlay(RoundedRectangle(cornerRadius: DS.cardRadius, style: .continuous).strokeBorder(DS.stroke, lineWidth: 1))
            .shadow(color: .black.opacity(scheme == .dark ? 0 : 0.04), radius: 1, y: 1)
            .shadow(color: .black.opacity(scheme == .dark ? 0.35 : 0.05), radius: 18, y: 8)
    }
}

/// Titre de carte : petit, en capitales espacées (« STOCKAGE »), et ce qui va à droite.
struct DSCardHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(DS.secondaryText)
            Spacer()
            trailing
        }
    }
}

// MARK: - Boutons

/// Bouton pilule : contour fin (secondaire) ou plein bleu (principal).
struct PillButtonStyle: ButtonStyle {
    var primary = false
    var tint: Color? = nil

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .padding(.horizontal, 15)
            .padding(.vertical, 8)
            .foregroundStyle(primary ? Color.white : (tint ?? DS.primaryText))
            .background(Capsule().fill(primary ? (tint ?? DS.accent) : DS.well))
            .overlay(Capsule().strokeBorder(primary ? Color.clear : DS.stroke, lineWidth: 1))
            .opacity(configuration.isPressed ? 0.75 : 1)
            .contentShape(Capsule())
    }
}

/// Contrôle segmenté en capsule : le choix est une pastille surélevée.
struct DSSegmented<Value: Hashable>: View {
    @Binding var selection: Value
    let items: [(Value, String)]
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 2) {
            ForEach(items, id: \.0) { value, title in
                let selected = value == selection
                Button {
                    selection = value
                } label: {
                    Text(title)
                        .font(.system(size: 12.5, weight: selected ? .semibold : .regular))
                        .padding(.horizontal, 13)
                        .padding(.vertical, 6)
                        .foregroundStyle(selected ? DS.primaryText : DS.secondaryText)
                        .background {
                            if selected {
                                Capsule().fill(scheme == .dark ? Color(nsColor: DS.rgb(0x252A35)) : .white)
                                    .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Capsule().fill(DS.well))
        .overlay(Capsule().strokeBorder(DS.stroke, lineWidth: 1))
        .fixedSize()
    }
}

/// Pastille d'état : un point coloré et un mot (« ● Analysé il y a 2 h »).
struct StatusPill: View {
    let color: Color
    let text: String
    var pulsing = false

    var body: some View {
        HStack(spacing: 7) {
            Circle().fill(color).frame(width: 7, height: 7)
                .overlay(Circle().stroke(color.opacity(0.35), lineWidth: pulsing ? 4 : 0))
            Text(text).font(.system(size: 12, weight: .medium)).foregroundStyle(DS.primaryText)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 6)
        .background(Capsule().fill(DS.well))
        .overlay(Capsule().strokeBorder(DS.stroke, lineWidth: 1))
        .fixedSize()
    }
}

// MARK: - Progression en étapes

/// Une tâche longue montrée pas à pas : barre en segments, étapes faites avec leur durée, étape en cours en clair.
struct StepProgressCard: View {
    struct Step: Identifiable {
        var id: String { title }
        var symbol: String
        var title: String
        /// Durée, une fois l'étape faite.
        var duration: TimeInterval?
    }

    let title: String
    let subtitle: String
    let elapsed: TimeInterval
    let steps: [Step]
    /// Index de l'étape en cours (`steps.count` : tout est fini).
    let current: Int
    var onOpen: (() -> Void)? = nil

    var body: some View {
        let done = current >= steps.count
        DSCard(padding: 18) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    if done {
                        Image(systemName: "checkmark.circle").font(.system(size: 17, weight: .medium)).foregroundStyle(DS.safe)
                    } else {
                        ProgressView().controlSize(.small)
                    }
                    Text(title).font(.system(size: 14, weight: .medium)).foregroundStyle(done ? DS.primaryText : DS.secondaryText)
                    Spacer()
                    Text(Self.clock(elapsed)).font(DS.mono(12.5)).foregroundStyle(DS.secondaryText)
                }
                HStack {
                    Text(subtitle).font(.system(size: 12)).foregroundStyle(DS.secondaryText)
                    Spacer()
                    Text(done ? tr("\(steps.count) étapes sur \(steps.count)", "\(steps.count) of \(steps.count) steps")
                              : tr("Étape \(current + 1) sur \(steps.count)", "Step \(current + 1) of \(steps.count)"))
                        .font(.system(size: 12)).foregroundStyle(DS.secondaryText)
                }
                HStack(spacing: 4) {
                    ForEach(0..<steps.count, id: \.self) { index in
                        Capsule().fill(index < current ? DS.accent : index == current ? DS.accent.opacity(0.45) : DS.well)
                            .frame(height: 4)
                    }
                }
                VStack(alignment: .leading, spacing: 9) {
                    ForEach(Array(steps.prefix(min(current + 1, steps.count)).enumerated()), id: \.offset) { index, step in
                        let running = index == current
                        HStack(spacing: 11) {
                            Image(systemName: step.symbol).font(.system(size: 13)).foregroundStyle(DS.secondaryText).frame(width: 18)
                            Text(step.title).font(.system(size: 13)).foregroundStyle(running ? DS.secondaryText : DS.primaryText)
                            Spacer()
                            Text(step.duration.map(Self.seconds) ?? "…").font(DS.mono(12)).foregroundStyle(DS.tertiaryText)
                        }
                    }
                }
                if let onOpen {
                    HStack {
                        Spacer()
                        Button(action: onOpen) {
                            HStack(spacing: 5) {
                                Text(tr("Voir le détail", "See details"))
                                Image(systemName: "arrow.up.right").font(.system(size: 11, weight: .semibold))
                            }
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(DS.primaryText)
                    }
                }
            }
        }
    }

    static func clock(_ seconds: TimeInterval) -> String {
        String(format: "%d:%02d", Int(seconds) / 60, Int(seconds) % 60)
    }

    static func seconds(_ value: TimeInterval) -> String {
        value < 10 ? String(format: "%.1fs", value) : "\(Int(value.rounded()))s"
    }
}

// MARK: - Pilules claires

/// « Filtre · 2 ✕ » : une pilule avec un compteur en couleur et de quoi tout effacer.
struct FilterPill: View {
    let symbol: String
    let title: String
    var count: Int? = nil
    var onClear: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: 13)).foregroundStyle(DS.secondaryText)
            Text(title).font(.system(size: 13, weight: .medium)).foregroundStyle(DS.primaryText)
            if let count {
                Text("· \(count)").font(.system(size: 13, weight: .semibold)).foregroundStyle(DS.accent)
            }
            if let onClear {
                Rectangle().fill(DS.separator).frame(width: 1, height: 16)
                Button(action: onClear) { Image(systemName: "xmark").font(.system(size: 11, weight: .semibold)) }
                    .buttonStyle(.plain).foregroundStyle(DS.tertiaryText)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Capsule().fill(DS.surface))
        .overlay(Capsule().strokeBorder(DS.stroke, lineWidth: 1))
        .shadow(color: .black.opacity(0.05), radius: 6, y: 2)
        .fixedSize()
    }
}

/// « ● En ligne » sur fond teinté, ou « ◌ En cours » avec un cercle en pointillés.
struct StatePill: View {
    enum Style { case dot, dashed }
    let text: String
    let color: Color
    var style: Style = .dot

    var body: some View {
        HStack(spacing: 8) {
            switch style {
            case .dot: Circle().fill(color).frame(width: 7, height: 7)
            case .dashed: Circle().strokeBorder(color, style: StrokeStyle(lineWidth: 1.6, dash: [2.5, 2.5])).frame(width: 14, height: 14)
            }
            Text(text).font(.system(size: 13, weight: .semibold)).foregroundStyle(color)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 7)
        .background(Capsule().fill(color.opacity(0.13)))
        .fixedSize()
    }
}

/// Recherche en pilule, avec un bouton rond à droite.
struct SearchPill: View {
    @Binding var text: String
    let prompt: String

    var body: some View {
        HStack(spacing: 8) {
            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
            Circle().fill(DS.surface)
                .frame(width: 28, height: 28)
                .overlay(Image(systemName: "magnifyingglass").font(.system(size: 12, weight: .semibold)).foregroundStyle(DS.secondaryText))
                .shadow(color: .black.opacity(0.08), radius: 3, y: 1)
        }
        .padding(.leading, 14)
        .padding(.trailing, 4)
        .padding(.vertical, 4)
        .background(Capsule().fill(DS.well))
        .overlay(Capsule().strokeBorder(DS.stroke, lineWidth: 1))
    }
}

// MARK: - Grille

/// La grille de la fenêtre : des multiples de 4 pt, les mêmes partout.
/// Vérifier avec `--render x.png --window page --grid` (lignes tous les 8 pt, ligne de base des titres en rouge).
enum WindowGrid {
    /// La barre latérale flottante : sa largeur, et son retrait du bord de la fenêtre.
    static let sidebarInset: CGFloat = 10
    /// Le sous-menu, à droite de la colonne d'icônes (76 pt) dans la carte flottante.
    static let submenuWidth: CGFloat = 232
    static let railWidth: CGFloat = 76
    /// Ligne de base des titres (sous-menu et page), depuis le haut de la fenêtre : les deux tombent sur la même ligne.
    static let titleBaseline: CGFloat = 48
    /// Marge haute d'un titre de cette taille pour que sa ligne de base tombe sur `titleBaseline`.
    static func top(forTitle size: CGFloat) -> CGFloat {
        (titleBaseline - NSFont.systemFont(ofSize: size, weight: .semibold).ascender).rounded()
    }
    /// Marges gauche et droite des pages, et bas de page.
    static let pagePadding: CGFloat = 32
    static let pageBottom: CGFloat = 32
    /// Entre deux blocs d'une page (cartes, grilles, lignes de cartes) et entre deux cartes d'une grille.
    static let gap: CGFloat = 16
    /// Avant un titre de section (en plus de `gap`, le titre a 8 pt au-dessus) : 24 pt en tout.
    static let sectionTop: CGFloat = 8
    /// Intérieur des cartes ; des cartes mises en avant (en haut d'une page).
    static let cardPadding: CGFloat = 16
    static let heroPadding: CGFloat = 20
}

/// `--grid` dans les captures : lignes tous les 8 pt, la ligne de base des titres en rouge,
/// et les bords des colonnes et des pages en bleu (colonne d'icônes, sous-menu, marges de la page).
struct LayoutGridOverlay: View {
    var body: some View {
        Canvas { context, size in
            var lines = Path()
            for y in stride(from: 0, through: size.height, by: 8) {
                lines.move(to: CGPoint(x: 0, y: y)); lines.addLine(to: CGPoint(x: size.width, y: y))
            }
            context.stroke(lines, with: .color(.cyan.opacity(0.12)), lineWidth: 0.5)
            var edges = Path()
            // Barre flottante (retrait, largeur), puis la page et ses marges.
            let card = WindowGrid.railWidth + 1 + WindowGrid.submenuWidth
            let page = Int(WindowGrid.sidebarInset * 2 + card)
            for x in [Int(WindowGrid.sidebarInset), Int(WindowGrid.sidebarInset + WindowGrid.railWidth), Int(WindowGrid.sidebarInset + card), page, page + Int(WindowGrid.pagePadding), Int(size.width) - Int(WindowGrid.pagePadding)] {
                edges.move(to: CGPoint(x: CGFloat(x), y: 0)); edges.addLine(to: CGPoint(x: CGFloat(x), y: size.height))
            }
            context.stroke(edges, with: .color(.blue.opacity(0.6)), lineWidth: 0.5)
            var baseline = Path()
            baseline.move(to: CGPoint(x: 0, y: WindowGrid.titleBaseline)); baseline.addLine(to: CGPoint(x: size.width, y: WindowGrid.titleBaseline))
            context.stroke(baseline, with: .color(.red.opacity(0.8)), lineWidth: 0.5)
        }
        .allowsHitTesting(false)
    }
}

/// Le fond de la fenêtre : le bureau flouté derrière, assombri (ou éclairci) pour rester lisible.
struct WindowGlass: View {
    var body: some View {
        ZStack {
            WindowMaterial()
            DS.canvas.opacity(0.72)
        }
    }
}

private struct WindowMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .underWindowBackground
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

extension View {
    /// La barre latérale flottante : une carte de verre aux grands arrondis, décollée des bords.
    func glassSidebar() -> some View {
        self
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(DS.surface))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(DS.stroke, lineWidth: 0.5))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
    }
}
