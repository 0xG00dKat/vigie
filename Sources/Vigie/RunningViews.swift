import SwiftUI
import VigieCore

/// « Ce qui tourne » : les apps, les programmes discrets et macOS sur une seule page.
/// En haut, trois cartes (un clic filtre) ; puis le filtre qui fusionne dans la pilule des résultats ; puis la liste.
/// Les outils de dev, Docker et les ports gardent leurs pages (mode Développeur).
struct RunningPage: View {
    @Environment(AppModel.self) private var model

    static let categories: [ProcessCategory] = [.apps, .background, .system]

    var body: some View {
        @Bindable var model = model
        let shown = model.runningGroups
        ScrollView {
            VStack(alignment: .leading, spacing: WindowGrid.gap) {
                PageHeader(title: tr("Ce qui tourne", "Running"),
                           subtitle: tr("Les apps ouvertes, les petits programmes sans fenêtre et ce que macOS fait tourner.",
                                        "Open apps, small windowless programs and what macOS runs."),
                           lesson: "processus") { EmptyView() }
                    .padding(.horizontal, -VigieTheme.pagePadding)
                    .padding(.bottom, -16)
                RelaunchBanner()
                HStack(spacing: WindowGrid.gap) {
                    ForEach(Self.categories) { category in
                        RunningCategoryCard(category: category)
                    }
                }
                HStack(alignment: .center) {
                    MergeFilterBar(count: shown.count,
                                   options: Self.categories.map { ($0, $0.title) },
                                   selection: $model.runningFilter)
                    Spacer()
                    Picker("", selection: $model.runningSort) {
                        Text(tr("Mémoire", "Memory")).tag(AppModel.RunningSort.memory)
                        Text(tr("Nom", "Name")).tag(AppModel.RunningSort.name)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
                // Les services de macOS se rangent par rôle (sauf pendant une recherche : on veut le service tout de suite).
                let byRole = !model.isSearching
                let listed = byRole ? shown.filter { $0.category != .system } : shown
                let system = byRole ? shown.filter { $0.category == .system } : []
                if !listed.isEmpty || system.isEmpty {
                    VigieCard(padding: 0) {
                        // Lignes créées à l'affichage seulement, et jamais animées : la liste ne freine pas le filtre.
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(listed.enumerated()), id: \.element.id) { index, group in
                                if index > 0 { Divider().padding(.leading, 50) }
                                GroupRow(group: group)
                                    .padding(.horizontal, 4)
                            }
                        }
                        .transaction { $0.animation = nil }
                        if shown.isEmpty {
                            EmptyPage(text: model.isSearching
                                      ? tr("Rien ne correspond à « \(model.query) ».", "Nothing matches “\(model.query)”.")
                                      : tr("Rien ici pour l'instant.", "Nothing here right now."))
                        }
                    }
                }
                if !system.isEmpty {
                    SystemRolesCard(groups: system)
                }
            }
            .padding(.horizontal, VigieTheme.pagePadding)
            .padding(.bottom, WindowGrid.pageBottom)
        }
    }
}

/// Une carte par famille : combien, la mémoire prise, et un clic pour filtrer la liste.
struct RunningCategoryCard: View {
    @Environment(AppModel.self) private var model
    let category: ProcessCategory
    @State private var hovering = false

    var body: some View {
        let groups = model.visibleGroups(in: category)
        let memory = groups.reduce(UInt64(0)) { $0 + $1.memory }
        let selected = model.runningFilter.contains(category)
        Button {
            // Sans animation globale : seul le filtre s'anime (la liste change d'un coup, sans ralentir).
            if selected { model.runningFilter.remove(category) } else { model.runningFilter.insert(category) }
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    VigieTile(symbol: category.outlineSymbol, size: 32)
                    Spacer()
                    if category == .system {
                        Text(tr("lecture seule", "read only")).font(.system(size: 10.5, weight: .medium)).foregroundStyle(.tertiary)
                    }
                }
                Text(category.title).font(.system(size: 15, weight: .semibold))
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(groups.count)").font(.system(size: 26, weight: .semibold)).monospacedDigit()
                        .contentTransition(.numericText())
                    Text(memory > 0 ? "· " + Format.bytes(memory) : "").font(.system(size: 13)).foregroundStyle(.secondary).monospacedDigit()
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(DS.surface))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(selected ? Color.primary.opacity(0.85) : Color.primary.opacity(hovering ? 0.18 : 0.08), lineWidth: selected ? 1.5 : 0.5))
            .opacity(category == .system && !selected ? 0.75 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// Filtre qui fusionne : une pilule noire « 24 résultats » ; un clic sur une étiquette la fait glisser dans la pilule
/// (avec un trait), le nombre défile ; un nouveau clic la ressort. Plusieurs choix possibles, aucun = tout.
struct MergeFilterBar<Value: Hashable>: View {
    let count: Int
    let options: [(Value, String)]
    @Binding var selection: Set<Value>
    @Namespace private var space
    @Environment(\.colorScheme) private var scheme

    private var ink: Color { DS.wellSelected }
    private var paper: Color { DS.primaryText }

    var body: some View {
        HStack(spacing: 10) {
            // La pilule des résultats, avec les étiquettes choisies dedans.
            HStack(spacing: 0) {
                HStack(spacing: 5) {
                    Text("\(count)").font(.system(size: 13, weight: .bold)).monospacedDigit()
                        .contentTransition(.numericText(value: Double(count)))
                        .animation(VigieMotion.quick, value: count)
                    Text(count > 1 ? tr("résultats", "results") : tr("résultat", "result"))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(paper.opacity(0.55))
                }
                .padding(.horizontal, 16)
                ForEach(options.filter { selection.contains($0.0) }, id: \.0) { value, title in
                    Rectangle().fill(paper.opacity(0.25)).frame(width: 1, height: 18)
                    chip(value, title, inside: true)
                }
            }
            .frame(height: 32)
            .foregroundStyle(paper)
            .background(Capsule().fill(ink))
            // Les étiquettes libres, à contour.
            ForEach(options.filter { !selection.contains($0.0) }, id: \.0) { value, title in
                chip(value, title, inside: false)
            }
        }
        .animation(VigieMotion.glide, value: selection)
    }

    private func chip(_ value: Value, _ title: String, inside: Bool) -> some View {
        Button {
            if selection.contains(value) { selection.remove(value) } else { selection.insert(value) }
        } label: {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(inside ? paper : DS.primaryText)
                .padding(.horizontal, 14)
                .frame(height: 32)
                .background {
                    // Libre : pastille pleine discrète (comme les onglets) ; dans la pilule : rien (son fond plein).
                    if !inside {
                        Capsule().fill(DS.well)
                    }
                }
                .contentShape(Capsule())
                .matchedGeometryEffect(id: value, in: space)
        }
        .buttonStyle(.plain)
    }
}

/// « Ce que fait macOS » : les services du système rangés par rôle, une ligne repliée par famille
/// (combien de services, la mémoire de toute la famille). Ouverte, une famille montre ses plus gros services d'abord.
struct SystemRolesCard: View {
    let groups: [ProcessGroup]
    @State private var open: Set<SystemRole> = []
    @State private var showAll: Set<SystemRole> = []
    /// Services montrés avant « Afficher les autres ».
    private let firstCount = 8

    var body: some View {
        let families = SystemRoleGroup.make(groups)
        VStack(alignment: .leading, spacing: 8) {
            LearnSectionTitle(tr("Ce que fait macOS · \(groups.count) services, en lecture seule",
                                 "What macOS is doing · \(groups.count) services, read only"))
            VigieCard(padding: 0) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(families.enumerated()), id: \.element.id) { index, family in
                        if index > 0 { Divider().padding(.leading, 62) }
                        familyRow(family)
                        if open.contains(family.role) {
                            let all = showAll.contains(family.role)
                            let visible = all ? family.groups : Array(family.groups.prefix(firstCount))
                            ForEach(visible) { group in
                                Divider().padding(.leading, 62)
                                GroupRow(group: group)
                                    .padding(.leading, 46)
                                    .padding(.trailing, 4)
                            }
                            if !all && family.groups.count > firstCount {
                                Divider().padding(.leading, 62)
                                Button {
                                    showAll.insert(family.role)
                                } label: {
                                    Text(tr("Afficher les \(family.groups.count - firstCount) autres", "Show the \(family.groups.count - firstCount) others"))
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(VigieTheme.accent)
                                        .padding(.vertical, 10)
                                        .padding(.leading, 62)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .transaction { $0.animation = nil }
            }
        }
    }

    private func familyRow(_ family: SystemRoleGroup) -> some View {
        let isOpen = open.contains(family.role)
        return Button {
            if isOpen { open.remove(family.role); showAll.remove(family.role) } else { open.insert(family.role) }
        } label: {
            HStack(spacing: 12) {
                VigieTile(symbol: family.role.symbol, size: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(family.role.title.text).font(.system(size: 13.5, weight: .semibold))
                    Text(family.role.explanation.text)
                        .font(.system(size: 12))
                        .foregroundStyle(DS.secondaryText)
                        .lineLimit(1)
                }
                Spacer(minLength: 12)
                Text(tr("\(family.groups.count) services", "\(family.groups.count) services"))
                    .font(.system(size: 11.5))
                    .foregroundStyle(DS.tertiaryText)
                    .monospacedDigit()
                Text(Format.bytes(family.memory))
                    .font(.system(size: 13, weight: .semibold))
                    .monospacedDigit()
                    .frame(minWidth: 64, alignment: .trailing)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DS.tertiaryText)
                    .rotationEffect(.degrees(isOpen ? 90 : 0))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
