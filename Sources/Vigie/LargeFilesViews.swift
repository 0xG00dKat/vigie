import AppKit
import SwiftUI
import VigieCore

// MARK: - Page de la fenêtre

/// Gros fichiers et doublons : deux onglets d'une même page. Rien ne part sans un clic de confirmation,
/// et tout va à la corbeille.
struct LargeFilesPage: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PageHeader(title: tr("Gros fichiers et doublons", "Large files and duplicates"),
                           subtitle: model.largeFilesTab == .duplicates
                               ? tr("Les fichiers présents plusieurs fois, identiques octet pour octet. Tu choisis la copie à garder, les autres vont à la corbeille.",
                                    "Files you have more than once, identical byte for byte. You pick the copy to keep, the others go to the Trash.")
                               : StorageKind.largeFile.pageExplanation) {
                    PageTabs(selection: $model.largeFilesTab, tabs: [
                        (AppModel.LargeFilesTab.files, tr("Gros fichiers", "Large files"), "doc"),
                        (AppModel.LargeFilesTab.duplicates, tr("Doublons", "Duplicates"), "doc.on.doc"),
                    ])
                }
                .padding(.horizontal, -VigieTheme.pagePadding)
                .padding(.bottom, -16)
                if let report = model.storage, !report.entries(of: .largeFile).isEmpty {
                    LargeFilesTopTiles(files: report.entries(of: .largeFile))
                }
                switch model.largeFilesTab {
                case .files: LargeFilesList()
                case .duplicates: BentoCell { DuplicatesView().padding(.horizontal, -VigieTheme.pagePadding + 16) }
                }
            }
            .padding(.horizontal, VigieTheme.pagePadding)
            .padding(.bottom, WindowGrid.pageBottom)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { SelectionBar() }
        .onDisappear { model.clearSelection() }
    }
}

private struct LargeFilesList: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let report = model.storage {
            let all = report.entries(of: .largeFile)
            let shown = model.largeFileFilter.apply(all)
            BentoCell {
                VStack(alignment: .leading, spacing: 10) {
                    LargeFileFilterBar(entries: all)
                    if shown.isEmpty {
                        Text(all.isEmpty ? tr("Aucun fichier de plus de 100 Mo dans ton Bureau, tes Documents, tes Téléchargements ou tes Vidéos.",
                                              "No file over 100 MB in your Desktop, Documents, Downloads or Movies.")
                                         : tr("Aucun fichier ne correspond à ces filtres.", "No file matches these filters."))
                            .font(.system(size: 12.5))
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 12)
                    } else {
                        StorageSectionRows(kind: .largeFile, entries: shown, largest: max(all.map(\.size).max() ?? 1, 1))
                            .padding(.horizontal, -12)
                    }
                }
            }
        } else {
            ScanCard()
        }
    }
}

/// En haut : ce que pèsent les gros fichiers, ceux qu'on n'ouvre plus, et les doublons.
private struct LargeFilesTopTiles: View {
    @Environment(AppModel.self) private var model
    let files: [StorageEntry]

    var body: some View {
        let total = files.reduce(UInt64(0)) { $0 + $1.size }
        let unused = LargeFileFilter(unusedOnly: true).apply(files)
        let unusedSize = unused.reduce(UInt64(0)) { $0 + $1.size }
        HStack(alignment: .top, spacing: 16) {
            TopTile(symbol: "doc", tint: DS.review,
                    title: tr("\(Format.bytes(total, decimal: true)) en \(files.count) fichier\(files.count > 1 ? "s" : "")",
                              "\(Format.bytes(total, decimal: true)) in \(files.count) file\(files.count > 1 ? "s" : "")"),
                    text: tr("Plus de 100 Mo chacun, dans ton Bureau, tes Documents, tes Téléchargements et tes Vidéos.",
                             "Over 100 MB each, in your Desktop, Documents, Downloads and Movies.")) { EmptyView() }
            TopTile(symbol: "clock", tint: unused.isEmpty ? DS.safe : DS.review,
                    title: unused.isEmpty ? tr("Tous ouverts récemment", "All opened recently")
                                          : tr("\(Format.bytes(unusedSize, decimal: true)) pas ouverts depuis 6 mois", "\(Format.bytes(unusedSize, decimal: true)) not opened in 6 months"),
                    text: unused.isEmpty ? tr("Aucun gros fichier oublié.", "No forgotten large file.")
                                         : tr("\(unused.count) fichier\(unused.count > 1 ? "s" : "") : souvent des installeurs ou des exports qu'on n'ouvre plus.",
                                              "\(unused.count) file\(unused.count > 1 ? "s" : ""): often installers or exports nobody opens anymore.")) {
                if !unused.isEmpty, !model.largeFileFilter.unusedOnly {
                    Button(tr("Les voir", "Show them")) {
                        withAnimation(VigieMotion.standard) {
                            model.largeFilesTab = .files
                            model.largeFileFilter = LargeFileFilter(unusedOnly: true)
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            duplicatesTile
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var duplicatesTile: some View {
        switch model.duplicateSearch {
        case .done(let groups, _):
            let freed = groups.reduce(UInt64(0)) { $0 + $1.freed() }
            TopTile(symbol: "doc.on.doc", tint: groups.isEmpty ? DS.safe : DS.review,
                    title: groups.isEmpty ? tr("Aucun doublon", "No duplicates")
                                          : tr("\(Format.bytes(freed, decimal: true)) en doublons", "\(Format.bytes(freed, decimal: true)) in duplicates"),
                    text: groups.isEmpty ? tr("Chaque fichier n'existe qu'une fois.", "Every file exists only once.")
                                         : tr("\(groups.count) fichier\(groups.count > 1 ? "s" : "") en plusieurs exemplaires identiques.",
                                              "\(groups.count) file\(groups.count > 1 ? "s" : "") with identical copies.")) {
                if !groups.isEmpty, model.largeFilesTab != .duplicates {
                    Button(tr("Les voir", "Show them")) { withAnimation(VigieMotion.standard) { model.largeFilesTab = .duplicates } }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }
        case .running(let progress):
            TopTile(symbol: "doc.on.doc", tint: DS.keep, title: tr("Recherche des doublons…", "Looking for duplicates…"),
                    text: tr("Vigie compare le contenu des fichiers, pas leur nom.", "Vigie compares file contents, not names.")) {
                ProgressView(value: progress).tint(VigieTheme.accent)
            }
        case .idle:
            TopTile(symbol: "doc.on.doc", tint: DS.keep, title: tr("Doublons", "Duplicates"),
                    text: tr("Les fichiers présents plusieurs fois, identiques octet pour octet.", "Files you have more than once, identical byte for byte.")) {
                Button(tr("Chercher", "Search")) {
                    model.largeFilesTab = .duplicates
                    model.findDuplicates()
                }
                .buttonStyle(.borderedProminent)
                .tint(VigieTheme.accent)
                .controlSize(.small)
            }
        }
    }
}

/// Filtres : un type à la fois, et « pas ouverts depuis 6 mois ». Avec le total de ce qui est affiché.
struct LargeFileFilterBar: View {
    @Environment(AppModel.self) private var model
    let entries: [StorageEntry]

    /// Une étiquette du filtre : un type de fichier, ou « pas ouverts depuis 6 mois ».
    enum Option: Hashable {
        case category(FileCategory)
        case unused
    }

    var body: some View {
        let filter = model.largeFileFilter
        let categories = FileCategory.allCases.filter { category in entries.contains { $0.fileCategory == category } }
        let shown = filter.apply(entries)
        let options: [(Option, String)] = categories.map { (Option.category($0), $0.shortTitle) }
            + [(Option.unused, tr("Pas ouverts depuis 6 mois", "Not opened in 6 months"))]
        let selection = Binding<Set<Option>>(
            get: {
                Set(filter.categories.map { Option.category($0) } + (filter.unusedOnly ? [Option.unused] : []))
            },
            set: { chosen in
                var next = LargeFileFilter()
                for option in chosen {
                    switch option {
                    case .category(let category): next.categories.insert(category)
                    case .unused: next.unusedOnly = true
                    }
                }
                model.largeFileFilter = next
            })
        VStack(alignment: .leading, spacing: 10) {
            MergeFilterBar(count: shown.count, options: options, selection: selection)
            Text(tr("\(Format.bytes(shown.reduce(0) { $0 + $1.size }, decimal: true)) au total",
                    "\(Format.bytes(shown.reduce(0) { $0 + $1.size }, decimal: true)) in total"))
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }
}

/// Onglets d'une page : l'onglet choisi est plein, dans la couleur d'accent.
struct PageTabs<Tab: Hashable>: View {
    @Binding var selection: Tab
    let tabs: [(Tab, String, String)]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(tabs, id: \.0) { tab, title, symbol in
                let selected = tab == selection
                Button {
                    selection = tab
                } label: {
                    Label(title, systemImage: symbol)
                        .font(.system(size: 12, weight: .medium))
                        .padding(.horizontal, 11)
                        .padding(.vertical, 5)
                        .foregroundStyle(selected ? Color.white : Color.primary)
                        .background(Capsule().fill(selected ? VigieTheme.accent : Color.clear))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Capsule().fill(Color.primary.opacity(0.06)))
        .fixedSize()
    }
}

private extension Optional where Wrapped == CleanState {
    var isDone: Bool {
        if case .done? = self { return true }
        return false
    }
}

struct FilterChip: View {
    let title: String
    let count: Int
    var symbol: String? = nil
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let symbol { Image(systemName: symbol).font(.system(size: 10, weight: .semibold)) }
                Text(title).font(.system(size: 11.5, weight: .medium))
                Text("\(count)")
                    .font(.system(size: 10.5, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(selected ? Color.white.opacity(0.85) : Color.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .foregroundStyle(selected ? Color.white : Color.primary)
            .background(Capsule().fill(selected ? VigieTheme.accent : Color.primary.opacity(0.06)))
            .overlay(Capsule().strokeBorder(Color.primary.opacity(selected ? 0 : 0.08), lineWidth: 0.5))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(count == 0 && !selected)
        .opacity(count == 0 && !selected ? 0.45 : 1)
    }
}

/// Rangée qui passe à la ligne quand il n'y a plus de place.
struct FlowRow: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.reduce(CGFloat(0)) { $0 + $1.height } + spacing * CGFloat(max(0, rows.count - 1))
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.items {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y + (row.height - size.height) / 2), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> [(items: [Int], width: CGFloat, height: CGFloat)] {
        var rows: [(items: [Int], width: CGFloat, height: CGFloat)] = []
        var current: (items: [Int], width: CGFloat, height: CGFloat) = ([], 0, 0)
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = current.items.isEmpty ? size.width : current.width + spacing + size.width
            if needed > width && !current.items.isEmpty {
                rows.append(current)
                current = ([index], size.width, size.height)
            } else {
                current = (current.items + [index], needed, max(current.height, size.height))
            }
        }
        if !current.items.isEmpty { rows.append(current) }
        return rows
    }
}

/// Dans le détail d'un gros fichier : dernière ouverture, et l'avertissement iCloud.
struct LargeFileFacts: View {
    let entry: StorageEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let used = entry.lastUsed {
                Label(tr("Ouvert pour la dernière fois \(Format.ago(used, in: .fr))", "Last opened \(Format.ago(used, in: .en))"),
                      systemImage: "clock")
                    .foregroundStyle(entry.isUnused() ? Color.orange : Color.secondary)
            } else if entry.isUnused() {
                Label(tr("Pas modifié depuis plus de 6 mois", "Not modified in over 6 months"), systemImage: "clock")
                    .foregroundStyle(.orange)
            }
            if entry.inICloud == true {
                Label(tr("Dans iCloud Drive : le mettre à la corbeille le retire aussi de tes autres appareils.",
                         "In iCloud Drive: moving it to the Trash also removes it from your other devices."), systemImage: "icloud")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .font(.system(size: 10.5))
    }
}

/// Dans le panneau : la page complète (filtres, doublons) s'ouvre dans la fenêtre.
struct OpenLargeFilesButton: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button {
            model.windowPageRequest = .storage(.largeFile)
            openWindow(id: VigieWindow.id)
            NSApp.activate()
        } label: {
            Label(tr("Filtrer et chercher les doublons…", "Filter and find duplicates…"), systemImage: "line.3.horizontal.decrease.circle")
        }
        .buttonStyle(.borderless)
        .font(.system(size: 11))
    }
}

extension FileCategory {
    var symbol: String {
        switch self {
        case .video: return "film"
        case .image: return "photo"
        case .audio: return "waveform"
        case .archive: return "archivebox"
        case .document: return "doc.text"
        case .other: return "doc"
        }
    }
}

// MARK: - Doublons

struct DuplicatesView: View {
    @Environment(AppModel.self) private var model
    @State private var showAll = false

    var body: some View {
        switch model.duplicateSearch {
        case .idle:
            VigieCard(padding: 20) {
                HStack(alignment: .top, spacing: 16) {
                    VigieTile(symbol: "doc.on.doc", size: 40)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(tr("Trouver les fichiers en double", "Find duplicate files")).font(.system(size: 16, weight: .semibold))
                        Text(tr("Vigie compare le contenu des fichiers de plus de 1 Mo de ton Bureau, tes Documents, Téléchargements, Vidéos, Images et Musique. Deux fichiers sont des doublons seulement s'ils sont identiques octet pour octet, quel que soit leur nom.",
                                "Vigie compares the content of files over 1 MB in your Desktop, Documents, Downloads, Movies, Pictures and Music. Two files are duplicates only if they're identical byte for byte, whatever their name."))
                            .font(.system(size: 12.5)).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(tr("Jamais proposés : les fichiers de tes projets de code, tes bibliothèques Photos et Musique, et ce qui n'est que dans iCloud. Rien ne quitte ton Mac.",
                                "Never suggested: files in your code projects, your Photos and Music libraries, and what's only in iCloud. Nothing leaves your Mac."))
                            .font(.system(size: 11.5)).foregroundStyle(.tertiary)
                            .fixedSize(horizontal: false, vertical: true)
                        Button(tr("Chercher les doublons", "Find duplicates")) { model.findDuplicates() }
                            .buttonStyle(AccentButtonStyle())
                            .padding(.top, 6)
                    }
                }
            }
            .padding(.horizontal, VigieTheme.pagePadding)
        case .running(let progress):
            VigieCard(padding: 20) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(progress < 0.2 ? tr("Lecture de tes dossiers…", "Reading your folders…")
                                        : tr("Comparaison des fichiers…", "Comparing files…"))
                        .font(.system(size: 14, weight: .semibold))
                    ProgressView(value: progress).tint(VigieTheme.accent)
                    Text(tr("Quelques secondes à une minute, selon le nombre de photos et de vidéos.",
                            "A few seconds to a minute, depending on how many photos and videos you have."))
                        .font(.system(size: 11.5)).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, VigieTheme.pagePadding)
        case .done(let groups, let date):
            let freed = groups.reduce(UInt64(0)) { $0 + $1.freed(keeping: model.kept(in: $1)) }
            let copies = groups.reduce(0) { $0 + $1.files.count - 1 }
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                if groups.isEmpty {
                    Label(tr("Aucun doublon : chaque fichier n'existe qu'une fois.", "No duplicates: every file exists only once."),
                          systemImage: "checkmark.circle.fill")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.green)
                } else {
                    Text(tr("\(copies) copie\(copies > 1 ? "s" : "") en trop · \(Format.bytes(freed, decimal: true)) à récupérer",
                            "\(copies) extra cop\(copies > 1 ? "ies" : "y") · \(Format.bytes(freed, decimal: true)) to reclaim"))
                        .font(.system(size: 13, weight: .semibold))
                }
                Spacer()
                Text(Format.ago(date, in: Localization.current)).font(.system(size: 11)).foregroundStyle(.tertiary)
                Button(tr("Chercher à nouveau", "Search again")) { model.findDuplicates() }
                    .buttonStyle(.borderless)
                    .font(.system(size: 11.5))
            }
            .padding(.horizontal, VigieTheme.pagePadding)
            .padding(.bottom, 10)
            if !groups.isEmpty {
                Text(tr("Pour chaque fichier, Vigie conseille la copie à garder (l'originale, pas celle des Téléchargements ni « (1) »). Clique pour en choisir une autre.",
                        "For each file, Vigie suggests the copy to keep (the original, not the one in Downloads or “(1)”). Click to pick another."))
                    .font(.system(size: 11.5)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, VigieTheme.pagePadding)
                    .padding(.bottom, 10)
                Divider()
                let shown = showAll ? groups : Array(groups.prefix(30))
                ForEach(shown) { group in
                    DuplicateGroupRow(group: group)
                    Divider().padding(.leading, VigieTheme.pagePadding + 30)
                }
                if groups.count > 30 {
                    Button(showAll ? tr("Afficher moins", "Show less") : tr("Voir les \(groups.count - 30) autres", "Show the \(groups.count - 30) others")) {
                        showAll.toggle()
                    }
                    .buttonStyle(.borderless)
                    .font(.system(size: 11.5))
                    .padding(.horizontal, VigieTheme.pagePadding)
                    .padding(.vertical, 8)
                }
            }
        }
    }
}

struct DuplicateGroupRow: View {
    @Environment(AppModel.self) private var model
    let group: DuplicateGroup
    @State private var hovering = false

    var body: some View {
        let id = "dup:" + group.id
        let expanded = model.expandedStorage.contains(id)
        let keep = model.kept(in: group)
        let state = model.duplicateStates[group.id]
        VStack(alignment: .leading, spacing: 0) {
            Button {
                model.toggleStorage(id)
            } label: {
                HStack(spacing: 8) {
                    FileIcon(path: group.files.first?.path ?? "")
                    Text(group.name)
                        .font(.system(size: 12.5, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(tr("\(group.files.count) copies", "\(group.files.count) copies"))
                        .font(.system(size: 9.5, weight: .medium))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.orange.opacity(0.16)))
                        .foregroundStyle(.orange)
                    if case .done? = state {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).font(.system(size: 11))
                    }
                    Spacer(minLength: 6)
                    Text(Format.bytes(group.freed(keeping: keep), decimal: true))
                        .font(.system(size: 11.5, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                        .frame(width: 10)
                }
                .padding(.horizontal, VigieTheme.pagePadding - 12)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if expanded {
                VStack(alignment: .leading, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(group.files) { file in
                            DuplicateFileRow(group: group, file: file, kept: file.path == keep, locked: state == .running || state.isDone)
                        }
                    }
                    .padding(6)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.04)))
                    DuplicateTrashControl(group: group, keep: keep)
                }
                .padding(.leading, VigieTheme.pagePadding + 18)
                .padding(.trailing, VigieTheme.pagePadding)
                .padding(.bottom, 10)
            }
        }
        .background(hovering || expanded ? Color.primary.opacity(0.045) : Color.clear)
        .onHover { hovering = $0 }
    }
}

private struct DuplicateFileRow: View {
    @Environment(AppModel.self) private var model
    let group: DuplicateGroup
    let file: DuplicateGroup.File
    let kept: Bool
    /// Pendant et après la mise à la corbeille, le choix ne bouge plus.
    let locked: Bool

    var body: some View {
        HStack(spacing: 8) {
            Button {
                model.duplicateKeep[group.id] = file.path
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: kept ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 14))
                        .foregroundStyle(kept ? VigieTheme.accent : Color.secondary)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(storagePath(file.path))
                            .font(.system(size: 11, weight: kept ? .semibold : .regular))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        HStack(spacing: 6) {
                            Text(tr("modifié \(Format.ago(file.modified, in: .fr))", "modified \(Format.ago(file.modified, in: .en))"))
                            if file.freed < group.size / 2 {
                                Text(tr("· copie du Finder : la jeter ne libère presque rien", "· Finder copy: removing it frees almost nothing"))
                            }
                        }
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                    }
                    Spacer(minLength: 6)
                    Text(kept ? tr("garder", "keep") : tr("corbeille", "Trash"))
                        .font(.system(size: 9.5, weight: .semibold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Capsule().fill((kept ? VigieTheme.accent : Color.orange).opacity(0.14)))
                        .foregroundStyle(kept ? VigieTheme.accent : Color.orange)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(locked)
            Button {
                model.reveal(path: file.path)
            } label: {
                Image(systemName: "folder")
            }
            .buttonStyle(.borderless)
            .help(tr("Afficher dans le Finder", "Show in Finder"))
        }
        .padding(.vertical, 3)
    }
}

/// « Mettre les autres à la corbeille », puis confirmation avec la taille (annulée au bout de 4 s), puis le résultat.
private struct DuplicateTrashControl: View {
    @Environment(AppModel.self) private var model
    let group: DuplicateGroup
    let keep: String

    var body: some View {
        let count = group.files.count - 1
        let size = Format.bytes(group.freed(keeping: keep), decimal: true)
        switch model.duplicateStates[group.id] {
        case .confirming?:
            HStack(spacing: 4) {
                Button(tr("Mettre \(count) copie\(count > 1 ? "s" : "") à la corbeille ?", "Move \(count) cop\(count > 1 ? "ies" : "y") to Trash?")) {
                    model.trashDuplicates(group)
                }
                .buttonStyle(DangerButtonStyle())
                Button {
                    model.cancelTrashDuplicates(group)
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
                .help(tr("Annuler", "Cancel"))
            }
            .controlSize(.small)
        case .running?:
            HStack(spacing: 5) {
                ProgressView().controlSize(.small)
                Text(tr("Mise à la corbeille…", "Moving to Trash…")).font(.system(size: 11)).foregroundStyle(.secondary)
            }
        case .done(let freed, _)?:
            Text(tr("\(Format.bytes(freed, decimal: true)) à la corbeille. La place revient quand tu la vides.",
                    "\(Format.bytes(freed, decimal: true)) moved to the Trash. The space comes back when you empty it."))
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.green)
        case .failed(let message)?:
            Text(tr("Échec : \(message)", "Failed: \(message)"))
                .font(.system(size: 10.5))
                .foregroundStyle(.red)
                .lineLimit(3)
        case nil:
            Button {
                model.requestTrashDuplicates(group)
            } label: {
                Label(tr("Mettre \(count == 1 ? "l'autre copie" : "les \(count) autres") à la corbeille (\(size))",
                         "Move \(count == 1 ? "the other copy" : "the \(count) others") to Trash (\(size))"), systemImage: "trash")
            }
            .buttonStyle(.borderless)
            .font(.system(size: 11, weight: .medium))
            .help(tr("Garde la copie cochée ; les autres vont à la corbeille (tu peux revenir en arrière).",
                     "Keeps the checked copy; the others go to the Trash (you can undo)."))
        }
    }
}

/// Icône du fichier (celle du Finder), ou celle de son type pour un fichier fictif.
private struct FileIcon: View {
    let path: String

    var body: some View {
        if FileManager.default.fileExists(atPath: path) {
            Image(nsImage: IconCache.icon(for: path))
                .resizable()
                .interpolation(.high)
                .frame(width: 22, height: 22)
        } else {
            VigieTile(symbol: FileCategory(path: path).symbol, tint: .orange, size: 22)
        }
    }
}
