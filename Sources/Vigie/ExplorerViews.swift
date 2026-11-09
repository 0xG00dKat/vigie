import AppKit
import SwiftUI
import VigieCore

/// Explorer : le dossier personnel en rectangles. Plus un bloc est grand, plus il prend de place, et sa couleur dit
/// quoi en faire (vert : se vide sans risque, orange : à vérifier, gris : à garder). Un clic montre ce que c'est et
/// l'action possible, un double-clic entre dans le dossier, le fil d'Ariane remonte.
struct ExplorerPage: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        // La page prend exactement la taille de la zone de contenu : la liste défile, la carte remplit le reste.
        GeometryReader { geometry in
            content.frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
        }
        .onAppear { model.openExplorer() }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(title: tr("Explorer", "Explore"),
                       subtitle: tr("Ton dossier personnel en rectangles : plus un bloc est grand, plus il prend de place, et sa couleur dit ce qu'il contient (ou, au choix, quoi en faire). Un clic pour savoir ce que c'est, un double-clic pour entrer.",
                                    "Your home folder as blocks: the bigger the block, the more space it takes, and its color tells what it holds (or, if you prefer, what to do with it). Click to learn what it is, double-click to open.")) {
                Button {
                    model.remeasureExplorer()
                } label: {
                    Label(tr("Mesurer à nouveau", "Measure again"), systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .disabled(model.explorerLoading)
            }
            Breadcrumb()
                .padding(.horizontal, VigieTheme.pagePadding)
                .padding(.bottom, 12)
            if model.explorerLoading {
                VStack(spacing: 10) {
                    ProgressView()
                    Text(tr("Mesure de \(storagePath(model.explorerPath))… Pour tout le dossier personnel, compte une vingtaine de secondes.",
                            "Measuring \(storagePath(model.explorerPath))… For the whole home folder, allow about twenty seconds."))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let listing = model.explorerDisplay?.listing {
                // Les rectangles sur toute la largeur ; le détail du bloc choisi (ou la légende) dessous.
                VStack(spacing: WindowGrid.gap) {
                    TreemapView(listing: listing)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    ExplorerDetail(listing: listing)
                }
                .frame(maxHeight: .infinity)
                .padding(.horizontal, VigieTheme.pagePadding)
                .padding(.bottom, WindowGrid.pageBottom)
            } else {
                EmptyPage(text: tr("Impossible de lire ce dossier.", "Can't read this folder."))
            }
        }
    }
}

/// « Dossier personnel › Library › Caches », chaque étape cliquable, et la taille du dossier affiché.
struct Breadcrumb: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let root = model.explorerRoot
        let relative = model.explorerPath == root ? [] : model.explorerPath.dropFirst(root.count + 1).split(separator: "/").map(String.init)
        HStack(spacing: 6) {
            Image(systemName: "house").foregroundStyle(.secondary)
            Button(tr("Dossier personnel", "Home folder")) { model.explore(root) }
                .buttonStyle(.plain)
                .foregroundStyle(relative.isEmpty ? Color.primary : Color.secondary)
            ForEach(Array(relative.enumerated()), id: \.offset) { index, name in
                Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold)).foregroundStyle(.tertiary)
                Button(name) {
                    model.explore(root + "/" + relative.prefix(index + 1).joined(separator: "/"))
                }
                .buttonStyle(.plain)
                .foregroundStyle(index == relative.count - 1 ? Color.primary : Color.secondary)
                .lineLimit(1)
            }
            Spacer()
            if let listing = model.explorerListing, !model.explorerLoading {
                if listing.pending > 0 {
                    HStack(spacing: 5) {
                        ProgressView().controlSize(.mini)
                        Text(tr("\(listing.pending) dossier\(listing.pending > 1 ? "s" : "") en cours de mesure", "\(listing.pending) folder\(listing.pending > 1 ? "s" : "") still measuring"))
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
                Chip(text: tr("\(listing.items.count) éléments · \(Format.bytes(listing.size, decimal: true))",
                              "\(listing.items.count) items · \(Format.bytes(listing.size, decimal: true))"), tint: .secondary)
            }
        }
        .font(.system(size: 12.5, weight: .medium))
    }
}

/// Liste à gauche : dossiers et gros fichiers, du plus gros au plus petit.
struct ExplorerList: View {
    @Environment(AppModel.self) private var model
    let listing: FolderListing

    var body: some View {
        VigieCard(padding: 0) {
            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(listing.items) { item in
                        ExplorerListRow(item: item)
                        Divider().padding(.leading, 40)
                    }
                    if listing.other > 0 {
                        HStack(spacing: 10) {
                            Image(systemName: "ellipsis.circle").frame(width: 18).foregroundStyle(.secondary)
                            Text(tr("Petits fichiers", "Small files")).font(.system(size: 12)).foregroundStyle(.secondary)
                            Spacer()
                            Text(Format.bytes(listing.other, decimal: true)).font(.system(size: 11.5)).monospacedDigit().foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                    }
                }
            }
        }
    }
}

struct ExplorerListRow: View {
    @Environment(AppModel.self) private var model
    let item: FolderListing.Item
    @State private var hovering = false
    @AppStorage(ExplorerColors.key) private var colors = ExplorerColors.type.rawValue

    var body: some View {
        let advice = model.explorerAdvice(item.path)
        let selected = model.explorerSelection == item.path
        Button {
            model.explorerSelection = item.path
        } label: {
            HStack(spacing: 10) {
                Image(systemName: item.isHiddenGroup ? "eye.slash" : item.isDirectory ? "folder.fill" : "doc.fill")
                    .frame(width: 18)
                    .foregroundStyle(ExplorerColors(rawValue: colors) == .risk ? advice.level.color : item.kind.color)
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.name).font(.system(size: 12.5, weight: .medium)).lineLimit(1).truncationMode(.middle)
                    Text(Format.bytes(item.size, decimal: true)).font(.system(size: 11)).monospacedDigit().foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                if item.isDirectory {
                    Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold)).foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
            .background(selected ? VigieTheme.accent.opacity(0.12) : hovering ? Color.primary.opacity(0.04) : .clear)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(TapGesture(count: 2).onEnded { if item.isDirectory { model.explore(item.path) } })
        .onHover { hovering = $0 }
        .contextMenu { ExplorerMenu(item: item) }
    }
}

extension FolderListing.Item {
    /// Le bloc « Dossiers cachés » du mode Simple (il n'existe pas sur le disque).
    var isHiddenGroup: Bool { path.hasSuffix("/" + FolderListing.hiddenGroupName) }
    var kind: ContentKind { isHiddenGroup ? .system : ContentKind(path: path, isDirectory: isDirectory) }
    var symbol: String { isHiddenGroup ? "eye.slash" : isDirectory ? "folder" : "doc" }
}

struct ExplorerMenu: View {
    @Environment(AppModel.self) private var model
    let item: FolderListing.Item

    var body: some View {
        if !item.isHiddenGroup {
            Button(tr("Afficher dans le Finder", "Show in Finder")) { model.reveal(path: item.path) }
        }
        if item.isDirectory {
            Button(tr("Ouvrir ce dossier", "Open this folder")) { model.explore(item.path) }
        }
    }
}

/// La carte en rectangles : les 14 plus gros éléments, puis un bloc pour tout le reste.
struct TreemapView: View {
    @Environment(AppModel.self) private var model
    let listing: FolderListing

    var body: some View {
        let shown = Array(listing.items.prefix(14))
        let restItems = listing.items.count - shown.count
        let rest = listing.items.dropFirst(14).reduce(UInt64(0)) { $0 + $1.size } + listing.other
        let sizes = shown.map { Double($0.size) } + (rest > 0 ? [Double(rest)] : [])
        let total = max(sizes.reduce(0, +), 1)
        GeometryReader { geometry in
            // Le cadre est agrandi d'un demi-espace de chaque côté : chaque bloc rend 3 pt, il reste 6 pt entre deux blocs
            // et les bords tombent pile sur ceux de la page.
            let gap = TreemapTile.gap
            let rects = Treemap.layout(sizes, in: CGRect(x: -gap / 2, y: -gap / 2,
                                                          width: geometry.size.width + gap, height: geometry.size.height + gap))
            ZStack(alignment: .topLeading) {
                ForEach(Array(rects.enumerated()), id: \.offset) { index, rect in
                    if index < shown.count {
                        TreemapTile(item: shown[index], advice: model.explorerAdvice(shown[index].path), rect: rect,
                                    share: Double(shown[index].size) / total)
                    } else {
                        TreemapRestTile(count: restItems, size: rest, rect: rect)
                    }
                }
            }
        }
    }
}

struct TreemapTile: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var scheme
    let item: FolderListing.Item
    let advice: ExplorerAdvice
    let rect: CGRect
    /// Part du dossier affiché.
    var share: Double = 0
    @State private var hovering = false
    @AppStorage(ExplorerColors.key) private var colors = ExplorerColors.type.rawValue

    /// Espace entre deux blocs.
    static let gap: CGFloat = 6
    /// Retrait du texte dans un bloc, le même partout : les noms d'une même rangée tombent à la même hauteur.
    static let inset: CGFloat = 11

    var body: some View {
        let width = max(rect.width - Self.gap, 1)
        let height = max(rect.height - Self.gap, 1)
        let selected = model.explorerSelection == item.path
        let tint = ExplorerColors(rawValue: colors) == .risk ? advice.level.color : item.kind.color
        let radius = min(14, min(width, height) / 3)
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            // Du verre teinté : la couleur dit le contenu (ou le risque), sans gros aplat.
            .fill(DS.surface)
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(tint.opacity((scheme == .dark ? 0.26 : 0.2) + (hovering || selected ? 0.12 : 0))))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(selected ? DS.accent : tint.opacity(0.55), lineWidth: selected ? 2 : 0.8))
            .overlay(alignment: .topLeading) {
                if width > 88 && height > 44 {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 5) {
                            Image(systemName: item.symbol)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(tint)
                            Text(item.name)
                                .font(.system(size: width > 160 ? 13 : 11.5, weight: .semibold))
                                .foregroundStyle(DS.primaryText)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Text(Format.bytes(item.size, decimal: true))
                            .font(.system(size: width > 160 ? 12 : 10.5))
                            .foregroundStyle(DS.secondaryText)
                            .monospacedDigit()
                        // Un dossier à garder peut contenir des caches : on le dit sur le bloc.
                        if advice.level != .safe, advice.reclaimableInside >= 100_000_000, height > 84, width > 120 {
                            SafeNote(text: tr("\(Format.bytes(advice.reclaimableInside, decimal: true)) sans risque",
                                              "\(Format.bytes(advice.reclaimableInside, decimal: true)) safe"))
                                .padding(.top, 4)
                        }
                    }
                    .padding(Self.inset)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if width > 88 && height > 76 {
                    Text(share >= 0.01 ? "\(Int((share * 100).rounded())) %" : "< 1 %")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(DS.secondaryText)
                        .monospacedDigit()
                        .padding(Self.inset)
                }
            }
            .frame(width: width, height: height)
            .offset(x: rect.minX + Self.gap / 2, y: rect.minY + Self.gap / 2)
            .onHover { hovering = $0 }
            .animation(VigieMotion.quick, value: hovering)
            .animation(VigieMotion.standard, value: colors)
            .gesture(TapGesture(count: 2).onEnded { if item.isDirectory { model.explore(item.path) } }
                .exclusively(before: TapGesture().onEnded { model.explorerSelection = item.path }))
            .contextMenu { ExplorerMenu(item: item) }
            .help("\(item.name) · \(Format.bytes(item.size, decimal: true))")
    }
}

struct TreemapRestTile: View {
    let count: Int
    let size: UInt64
    let rect: CGRect

    var body: some View {
        let width = max(rect.width - TreemapTile.gap, 1)
        let height = max(rect.height - TreemapTile.gap, 1)
        let radius = min(14, min(width, height) / 3)
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(DS.surface)
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(DS.stroke, lineWidth: 0.8))
            .overlay(alignment: .topLeading) {
                if width > 88 && height > 44 {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(count > 0 ? tr("\(count) autres", "\(count) more") : tr("Petits fichiers", "Small files"))
                            .font(.system(size: 11.5, weight: .semibold)).foregroundStyle(DS.primaryText).lineLimit(1)
                        Text(Format.bytes(size, decimal: true)).font(.system(size: 10.5)).foregroundStyle(DS.secondaryText).monospacedDigit()
                    }
                    .padding(TreemapTile.inset)
                }
            }
            .frame(width: width, height: height)
            .offset(x: rect.minX + TreemapTile.gap / 2, y: rect.minY + TreemapTile.gap / 2)
    }
}

/// Couleurs de l'explorateur : par type de contenu (par défaut, pour se repérer) ou par risque (pour faire le ménage).
enum ExplorerColors: String {
    case type = "type", risk = "risque"
    static let key = "couleursExplorateur"
}

extension ContentKind {
    /// Teintes réservées à l'explorateur, sans vert ni orange ni rouge : ces trois-là disent le risque partout dans Vigie.
    var color: Color {
        switch self {
        case .media: return DS.dynamic(light: NSColor(srgbRed: 0.53, green: 0.40, blue: 0.80, alpha: 1), dark: NSColor(srgbRed: 0.62, green: 0.50, blue: 0.88, alpha: 1))
        case .documents: return DS.dynamic(light: NSColor(srgbRed: 0.27, green: 0.50, blue: 0.82, alpha: 1), dark: NSColor(srgbRed: 0.38, green: 0.60, blue: 0.92, alpha: 1))
        case .apps: return DS.dynamic(light: NSColor(srgbRed: 0.78, green: 0.36, blue: 0.56, alpha: 1), dark: NSColor(srgbRed: 0.86, green: 0.46, blue: 0.64, alpha: 1))
        case .dev: return VigieTheme.accent
        case .caches: return DS.dynamic(light: NSColor(srgbRed: 0.70, green: 0.56, blue: 0.16, alpha: 1), dark: NSColor(srgbRed: 0.78, green: 0.64, blue: 0.24, alpha: 1))
        case .system: return DS.dynamic(light: NSColor(srgbRed: 0.42, green: 0.48, blue: 0.56, alpha: 1), dark: NSColor(srgbRed: 0.50, green: 0.56, blue: 0.64, alpha: 1))
        case .other: return DS.keep.opacity(0.7)
        }
    }
}

extension ExplorerAdvice.Level {
    /// Mêmes couleurs que le reste de Vigie : vert sûr, orange à vérifier, gris à garder.
    var color: Color {
        switch self {
        // Règle des couleurs : vert sûr, orange à vérifier, gris à garder, gris clair quand Vigie n'a rien à en dire.
        case .safe: return DS.safe
        case .review: return DS.review
        case .keep: return DS.keep
        case .unknown: return DS.keep.opacity(0.55)
        }
    }

    var title: String {
        switch self {
        case .safe: return tr("se vide sans risque", "safe to clear")
        case .review: return tr("à vérifier", "review first")
        case .keep: return tr("à garder", "keep")
        case .unknown: return tr("tes dossiers", "your folders")
        }
    }
}

/// Sous la carte : la légende, ou le détail du bloc choisi avec ce qu'on peut en faire.
struct ExplorerDetail: View {
    @Environment(AppModel.self) private var model
    let listing: FolderListing

    var body: some View {
        if let path = model.explorerSelection, let item = listing.items.first(where: { $0.path == path }) {
            selected(item, advice: model.explorerAdvice(path))
        } else {
            legend
        }
    }

    @AppStorage(ExplorerColors.key) private var colors = ExplorerColors.type.rawValue

    private var legend: some View {
        let safe = listing.items.reduce(UInt64(0)) { total, item in
            let advice = model.explorerAdvice(item.path)
            return total + (advice.level == .safe ? item.size : advice.reclaimableInside)
        }
        let byRisk = ExplorerColors(rawValue: colors) == .risk
        // Par type : seulement les types présents dans ce dossier, dans l'ordre de la légende.
        let kinds = ContentKind.allCases.filter { kind in listing.items.prefix(14).contains { $0.kind == kind } }
        return VigieCard(padding: 12) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Picker("", selection: $colors) {
                        Text(tr("Par type", "By type")).tag(ExplorerColors.type.rawValue)
                        Text(tr("Par risque", "By risk")).tag(ExplorerColors.risk.rawValue)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                    .controlSize(.small)
                    Spacer()
                }
                FlowRow(spacing: 14) {
                    if byRisk {
                        ForEach([ExplorerAdvice.Level.safe, .review, .keep], id: \.self) { level in
                            swatch(level.color, level.title.prefix(1).uppercased() + level.title.dropFirst())
                        }
                    } else {
                        ForEach(kinds, id: \.self) { kind in swatch(kind.color, kind.title.text) }
                    }
                    if safe > 0 {
                        SafeNote(text: tr("\(Format.bytes(safe, decimal: true)) se vident sans risque ici", "\(Format.bytes(safe, decimal: true)) can be safely cleared here"),
                                 size: 11.5)
                            .fixedSize()
                    }
                }
                Text(tr("Clique sur un bloc pour savoir ce que c'est et ce que Vigie peut en faire.", "Click a block to learn what it is and what Vigie can do with it."))
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func swatch(_ color: Color, _ title: String) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 3).fill(color).frame(width: 12, height: 12)
            Text(title).font(.system(size: 11.5))
        }
        .fixedSize()
    }

    private func selected(_ item: FolderListing.Item, advice: ExplorerAdvice) -> some View {
        VigieCard(padding: 14) {
            HStack(alignment: .top, spacing: 12) {
                VigieTile(symbol: item.isHiddenGroup ? "eye.slash" : item.isDirectory ? "folder.fill" : "doc.fill", tint: advice.level.color, size: 34)
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        Text(advice.entry?.title.text ?? item.name).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                        Text(Format.bytes(item.size, decimal: true)).font(.system(size: 12.5)).monospacedDigit().foregroundStyle(.secondary)
                        Chip(text: advice.level.title, tint: advice.level == .unknown ? .secondary : advice.level.color)
                    }
                    Text(advice.explanation?.text ?? (item.isDirectory
                        ? tr("Vigie n'a rien de particulier à en dire. Double-clique pour voir ce qu'il contient.",
                             "Vigie has nothing particular to say about it. Double-click to see what's inside.")
                        : tr("Un fichier. Vigie n'y touche pas d'elle-même.", "A file. Vigie doesn't touch it on its own.")))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if advice.level != .safe, advice.reclaimableInside > 0 {
                        SafeNote(text: tr("Contient \(Format.bytes(advice.reclaimableInside, decimal: true)) de caches et de dépendances qui se vident sans risque.",
                                          "Contains \(Format.bytes(advice.reclaimableInside, decimal: true)) of caches and dependencies that can be safely cleared."),
                                 size: 11.5)
                    }
                    FlowRow(spacing: 8) {
                        if let entry = advice.entry, model.cleanup(for: entry) != nil {
                            CleanControl(entry: entry, compact: false)
                        } else if advice.level != .safe, advice.reclaimableInside > 0 {
                            Button {
                                model.windowPageRequest = .storage(advice.reclaimableKind ?? .cache)
                            } label: {
                                Text(tr("Voir ce qui se vide  ›", "See what can be cleared  ›")).fixedSize()
                            }
                        }
                        if item.isDirectory {
                            Button {
                                model.explore(item.path)
                            } label: {
                                Text(tr("Ouvrir  ›", "Open  ›")).fixedSize()
                            }
                        }
                        if !item.isHiddenGroup {
                            Button {
                                model.reveal(path: item.path)
                            } label: {
                                Text(tr("Afficher dans le Finder", "Show in Finder"))
                                    .fixedSize()
                            }
                        }
                    }
                    .buttonStyle(HUDPillButtonStyle())
                    .padding(.top, 4)
                }
                Spacer(minLength: 0)
                Button {
                    model.explorerSelection = nil
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
                .help(tr("Fermer", "Close"))
            }
        }
    }
}


/// « 27 Go sans risque » : un petit point vert et le texte en couleur normale (le vert dit « sûr », sans en faire trop).
struct SafeNote: View {
    let text: String
    var size: CGFloat = 11
    var tint: Color = DS.safe

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Circle().fill(tint).frame(width: 6, height: 6).alignmentGuide(.firstTextBaseline) { $0[.bottom] - 0.5 }
            Text(text)
                .font(.system(size: size, weight: .medium))
                .foregroundStyle(DS.primaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
