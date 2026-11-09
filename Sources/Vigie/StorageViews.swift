import AppKit
import SwiftUI
import VigieCore

/// Vue « Stockage » : ce qui prend de la place, ce que c'est, et comment le nettoyer.
/// Une carte de vue d'ensemble (barre par famille, filtres), puis des sections repliables
/// de lignes compactes : le détail (explication, chemin, dossiers, commande) s'ouvre au clic.
struct StorageListView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    Color.clear.frame(height: 0).id("storage-top")
                    if let progress = model.storageProgress {
                        StorageProgressCard(progress: progress)
                    } else if model.storage == nil {
                        StorageIntroCard()
                    }
                    if let report = model.storage {
                        if model.storageProgress == nil {
                            StorageOverviewCard(report: report)
                        }
                        let largest = max(report.entries.map(\.size).max() ?? 1, 1)
                        ForEach(model.visibleKinds.filter { model.storageFilter == nil || $0 == model.storageFilter }, id: \.self) { kind in
                            let entries = model.displayedEntries(of: kind, in: report)
                            if !entries.isEmpty {
                                Section {
                                    if !model.collapsedStorage.contains(kind) {
                                        VStack(spacing: 0) {
                                            StorageSectionRows(kind: kind, entries: entries, largest: largest)
                                        }
                                        .panelCard()
                                    }
                                } header: {
                                    StorageSectionHeader(kind: kind, entries: entries)
                                        .id("section:" + kind.rawValue)
                                }
                            }
                        }
                    }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { SelectionBar() }
            .onDisappear { model.clearSelection() }
            .onChange(of: model.storageFilter) {
                proxy.scrollTo("storage-top", anchor: .top)
            }
            .onAppear {
                // Mode capture (--expand-storage) : on amène la ligne dépliée en haut du panneau.
                // L'en-tête de section reste épinglé en haut : on vise la ligne précédente (ou l'en-tête) pour ne pas cacher le titre.
                if let target = model.storageScrollTarget, let report = model.storage,
                   let kind = report.entries.first(where: { $0.id == target })?.kind {
                    let entries = report.entries(of: kind)
                    let index = entries.firstIndex { $0.id == target } ?? 0
                    let anchor = index == 0 ? "section:" + kind.rawValue : entries[index - 1].id
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { proxy.scrollTo(anchor, anchor: .top) }
                }
            }
        }
    }
}

/// Lignes d'une section. Projets et apps : les 10 plus gros d'abord, le reste derrière un bouton.
struct StorageSectionRows: View {
    @Environment(AppModel.self) private var model
    @Environment(\.inVigieWindow) private var inWindow
    let kind: StorageKind
    let entries: [StorageEntry]
    let largest: UInt64

    var body: some View {
        let cappable = (kind == .project || kind == .application) && entries.count > 10
        let showAll = model.showAll.contains(kind)
        let shown = cappable && !showAll ? Array(entries.prefix(10)) : entries
        let selectable = shown.filter { model.isSelectable($0) }
        if selectable.count > 1 {
            SelectAllRow(entries: selectable)
        }
        if kind == .largeFile && !inWindow {
            OpenLargeFilesButton()
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
        }
        ForEach(shown) { entry in
            StorageRow(entry: entry, largest: largest, reserveCheckbox: !selectable.isEmpty)
                .id(entry.id)
            Divider().padding(.leading, 42)
        }
        if cappable {
            let rest = entries.dropFirst(10)
            let size = Format.bytes(rest.reduce(0) { $0 + $1.size }, decimal: true)
            Button {
                if showAll { model.showAll.remove(kind) } else { model.showAll.insert(kind) }
            } label: {
                Text(showAll
                     ? tr("Afficher moins", "Show less")
                     : kind == .project
                        ? tr("Voir les \(rest.count) autres projets (\(size))", "Show the \(rest.count) other projects (\(size))")
                        : tr("Voir les \(rest.count) autres apps (\(size))", "Show the \(rest.count) other apps (\(size))"))
            }
            .buttonStyle(.borderless)
            .font(.system(size: 11))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
        }
    }
}

struct StorageIntroCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(tr("Qu'est-ce qui prend de la place ?", "What's taking up space?"))
                .font(.system(size: 14, weight: .semibold))
            Text(tr(
                "Vigie mesure les caches, les dépendances de tes projets, tes applications, tes gros fichiers et les données cachées des apps, puis te dit ce qu'on peut vider sans risque.",
                "Vigie measures caches, your projects' dependencies, your apps, your large files and hidden app data, then tells you what's safe to clear."
            ))
            .font(.system(size: 11.5))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            Button(tr("Analyser le stockage", "Analyze storage")) { model.scanStorage() }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.top, 2)
            Text(tr(
                "Environ une minute. macOS peut te demander l'accès au Bureau, aux Documents et aux Téléchargements : c'est pour mesurer tes fichiers et trouver tes projets. Rien n'est supprimé.",
                "About a minute. macOS may ask for access to your Desktop, Documents and Downloads: it's to measure your files and find your projects. Nothing is deleted."
            ))
            .font(.system(size: 10.5))
            .foregroundStyle(.tertiary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.05)))
        .padding(12)
    }
}

struct StorageProgressCard: View {
    let progress: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(tr("Analyse en cours…", "Analyzing…"))
                .font(.system(size: 12.5, weight: .semibold))
            ProgressView(value: progress)
                .progressViewStyle(.linear)
            Text(tr("Vigie parcourt tes dossiers, sans rien modifier.", "Vigie is going through your folders, without changing anything."))
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.05)))
        .padding(12)
    }
}

/// Vue d'ensemble : ce qui est récupérable, une barre découpée par famille et des filtres.
struct StorageOverviewCard: View {
    @Environment(AppModel.self) private var model
    let report: StorageReport

    var body: some View {
        let kinds = model.visibleKinds.filter { !report.entries(of: $0).isEmpty }
        let totals = Dictionary(uniqueKeysWithValues: kinds.map { kind in
            (kind, report.entries(of: kind).reduce(UInt64(0)) { $0 + $1.size })
        })
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline) {
                Text(tr("\(Format.bytes(model.reclaimable(report), decimal: true)) récupérables", "\(Format.bytes(model.reclaimable(report), decimal: true)) reclaimable"))
                    .font(.system(size: 17, weight: .bold))
                Spacer()
                Button(tr("Analyser à nouveau", "Analyze again")) { model.scanStorage() }
                    .buttonStyle(.borderless)
                    .font(.system(size: 11))
            }
            // Les gros fichiers sont déjà comptés dans « Tes fichiers » : pas de part dans la barre.
            StorageBar(kinds: kinds.filter { $0 != .largeFile }, totals: totals)
            FlowLayout(spacing: 5, lineSpacing: 5) {
                StorageFilterChip(title: tr("Tout", "All"), size: nil, tint: nil, selected: model.storageFilter == nil) {
                    model.filterStorage(nil)
                }
                ForEach(kinds, id: \.self) { kind in
                    StorageFilterChip(title: kind.shortTitle, size: totals[kind], tint: kind.tint, selected: model.storageFilter == kind) {
                        model.filterStorage(model.storageFilter == kind ? nil : kind)
                    }
                }
            }
            // Ce qui a grossi depuis l'analyse de référence : souvent la vraie raison du manque de place.
            if model.storageProgress == nil, let growth = DiskDiagnosis.make(report: report, previous: model.storageReference).growthLine() {
                Label(growth, systemImage: "arrow.up.right")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if model.storageProgress == nil {
                SafeCleanArea(showsButton: false)
            }
            if let action = model.lastStorageAction {
                Text(action)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.green)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if model.trashedByVigie > 0 {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Label(tr("\(Format.bytes(model.trashedByVigie, decimal: true)) mis à la corbeille par Vigie : vide-la pour récupérer la place.",
                             "\(Format.bytes(model.trashedByVigie, decimal: true)) moved to the Trash by Vigie: empty it to get the space back."),
                          systemImage: "trash")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button(tr("Ouvrir", "Open")) { model.openTrash() }
                        .buttonStyle(.borderless)
                        .font(.system(size: 11, weight: .medium))
                }
            }
            Text(summaryLine)
                .font(.system(size: 10.5))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(DS.surface))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(DS.stroke, lineWidth: 0.5))
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
    }

    private var summaryLine: String {
        let age = Format.elapsed(since: report.date)
        var parts = [tr("Récupérable = caches et dépendances, qui se recréent. Vigie ne nettoie qu'après ta confirmation.",
                        "Reclaimable = caches and dependencies, which rebuild themselves. Vigie only cleans after you confirm."),
                     tr("Analysé \(age), gardé 24 h", "Analyzed \(age), kept for 24 h")]
        if report.localSnapshots > 0 {
            // macOS efface ces instantanés quand la place manque : rien à faire, juste à savoir.
            parts.append(tr("\(report.localSnapshots) instantanés Time Machine locaux", "\(report.localSnapshots) local Time Machine snapshots"))
        }
        return parts[0] + " " + parts.dropFirst().joined(separator: " · ") + "."
    }
}

/// Barre découpée par famille ; un clic sur une part filtre la liste.
struct StorageBar: View {
    @Environment(AppModel.self) private var model
    let kinds: [StorageKind]
    let totals: [StorageKind: UInt64]

    var body: some View {
        let sum = max(kinds.reduce(UInt64(0)) { $0 + (totals[$1] ?? 0) }, 1)
        GeometryReader { geometry in
            let spacing: CGFloat = 2
            let available = geometry.size.width - spacing * CGFloat(max(kinds.count - 1, 0))
            HStack(spacing: spacing) {
                ForEach(kinds, id: \.self) { kind in
                    let fraction = Double(totals[kind] ?? 0) / Double(sum)
                    Rectangle()
                        .fill(kind.tint.gradient)
                        .frame(width: max(3, available * fraction))
                        .opacity(model.storageFilter == nil || model.storageFilter == kind ? 1 : 0.3)
                        .contentShape(Rectangle())
                        .onTapGesture { model.filterStorage(model.storageFilter == kind ? nil : kind) }
                        .help("\(kind.shortTitle) · \(Format.bytes(totals[kind] ?? 0, decimal: true))")
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .frame(height: 10)
    }
}

struct StorageFilterChip: View {
    let title: String
    let size: UInt64?
    let tint: Color?
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let tint {
                    Circle().fill(tint).frame(width: 7, height: 7)
                }
                Text(title)
                    .font(.system(size: 11, weight: selected ? .semibold : .regular))
                if let size {
                    Text(Format.bytes(size, decimal: true))
                        .font(.system(size: 10.5))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(selected ? VigieTheme.accent.opacity(0.18) : Color.primary.opacity(0.06)))
            .overlay(Capsule().strokeBorder(selected ? VigieTheme.accent.opacity(0.6) : Color.clear, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// En-tête de section, repliable comme dans la vue Processus.
struct StorageSectionHeader: View {
    @Environment(AppModel.self) private var model
    let kind: StorageKind
    let entries: [StorageEntry]

    var body: some View {
        let open = !model.collapsedStorage.contains(kind)
        let total = entries.reduce(UInt64(0)) { $0 + $1.size }
        Button {
            model.toggleStorageSection(kind)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 8.5, weight: .bold))
                    .rotationEffect(.degrees(open ? 90 : 0))
                    .frame(width: 10)
                Circle().fill(kind.tint).frame(width: 7, height: 7)
                Text(kind.title)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                Text("\(entries.count) · \(Format.bytes(total, decimal: true))")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(.regularMaterial)
    }
}

/// Ligne compacte : icône, nom, signal éventuel, part de la place, taille. Un clic ouvre ou ferme le détail.
struct StorageRow: View {
    @Environment(AppModel.self) private var model
    let entry: StorageEntry
    let largest: UInt64
    /// D'autres lignes de la liste ont une case : on garde sa place pour aligner les icônes.
    var reserveCheckbox = false
    @State private var hovering = false

    var body: some View {
        let expanded = model.expandedStorage.contains(entry.id)
        let selectable = model.isSelectable(entry)
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
            if selectable {
                SelectionBox(selected: model.storageSelection.contains(entry.id)) { model.toggleSelection(entry) }
                    .padding(.leading, 10)
            } else if reserveCheckbox {
                Color.clear.frame(width: 20, height: 22).padding(.leading, 10)
            }
            Button {
                model.toggleStorage(entry.id)
            } label: {
                HStack(spacing: 8) {
                    StorageIcon(entry: entry)
                    Text(entry.displayTitle)
                        .font(.system(size: 12.5, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    StorageBadge(entry: entry)
                    Spacer(minLength: 6)
                    SizeBar(fraction: entry.isProtected ? 0 : Double(entry.size) / Double(largest), tint: entry.kind.tint)
                    Text(entry.isProtected ? "—" : Format.bytes(entry.size, decimal: true))
                        .font(.system(size: 11.5, weight: .medium))
                        .monospacedDigit()
                        // L'orange est réservé à « à vérifier » : une grosse taille est juste plus foncée.
                        .foregroundStyle(entry.size > 5_000_000_000 ? Color.primary : Color.secondary)
                        .frame(minWidth: 50, alignment: .trailing)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                        .frame(width: 10)
                }
                .padding(.leading, selectable || reserveCheckbox ? 8 : 12)
                .padding(.trailing, 12)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(expanded ? "" : entry.explanation.text)
            }
            if expanded {
                StorageDetails(entry: entry)
                    .padding(.leading, 42)
                    .padding(.trailing, 12)
                    .padding(.bottom, 10)
            }
        }
        .background(hovering || expanded ? Color.primary.opacity(0.045) : Color.clear)
        .onHover { hovering = $0 }
    }
}

/// Part d'une ligne par rapport à la plus grosse de l'analyse.
struct SizeBar: View {
    let fraction: Double
    let tint: Color

    var body: some View {
        ZStack(alignment: .leading) {
            Capsule().fill(Color.primary.opacity(0.08))
            Capsule().fill(tint.opacity(0.85))
                .frame(width: fraction > 0 ? max(2, 40 * min(fraction, 1)) : 0)
        }
        .frame(width: 40, height: 4)
    }
}

/// Signal seulement quand il apprend quelque chose : protégé, app inutilisée, projet ancien.
struct StorageBadge: View {
    let entry: StorageEntry

    var body: some View {
        if let (text, color) = label {
            Text(text)
                .font(.system(size: 9.5, weight: .medium))
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(Capsule().fill(color.opacity(0.16)))
                .foregroundStyle(color)
                .fixedSize()
        }
    }

    private var label: (String, Color)? {
        if entry.isProtected { return (tr("protégé", "protected"), .orange) }
        if let note = entry.note { return (note.text, entry.noteIsWarning == true ? .orange : .gray) }
        if entry.kind == .application, let used = entry.modified, Date().timeIntervalSince(used) > 180 * 86_400 {
            return (tr("inutilisée ?", "unused?"), .orange)
        }
        if entry.kind == .project, let modified = entry.modified, Date().timeIntervalSince(modified) > 180 * 86_400 {
            return (tr("projet ancien", "old project"), .orange)
        }
        return nil
    }
}

struct StorageIcon: View {
    let entry: StorageEntry

    var body: some View {
        if FileManager.default.fileExists(atPath: entry.path), entry.kind != .cache {
            Image(nsImage: IconCache.icon(for: entry.path))
                .resizable()
                .interpolation(.high)
                .frame(width: 22, height: 22)
        } else {
            VigieTile(symbol: symbol, size: 21)
                .padding(0.5)
        }
    }

    private var symbol: String {
        switch entry.kind {
        case .cache: return "arrow.triangle.2.circlepath"
        case .project: return "shippingbox.fill"
        case .application: return "app.fill"
        case .largeFile: return "doc.fill"
        case .appData: return "internaldrive.fill"
        case .personal: return "person.fill"
        case .leftover: return "shippingbox.and.arrow.backward"
        case .systemData: return "gearshape.fill"
        }
    }
}

/// Détail d'une ligne ouverte : ce que c'est, où c'est, ce qu'il y a dedans et comment nettoyer.
struct StorageDetails: View {
    @Environment(AppModel.self) private var model
    let entry: StorageEntry

    var body: some View {
        let isApp = entry.kind == .application
        let hasProtected = entry.isProtected || entry.children.contains(where: \.isProtected)
        VStack(alignment: .leading, spacing: 6) {
            Text(entry.explanation.text)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(storagePath(entry.path))
                .font(.system(size: 10.5))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.middle)
            if entry.kind == .largeFile {
                LargeFileFacts(entry: entry)
            }
            if let identifier = entry.leftoverIdentifier, entry.displayTitle != identifier {
                Text(tr("Identifiant de l'app : \(identifier)", "App identifier: \(identifier)"))
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
                    .textSelection(.enabled)
            }
            if model.uninstallStates[entry.path] != nil {
                UninstallPanel(entry: entry)
            } else if !entry.children.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(entry.children) { child in
                        VStack(alignment: .leading, spacing: 1) {
                            HStack(spacing: 6) {
                                Text(child.title.text)
                                    .font(.system(size: 11, weight: .medium))
                                    .lineLimit(1)
                                Spacer(minLength: 4)
                                Text(child.isProtected ? tr("protégé", "protected") : Format.bytes(child.size, decimal: true))
                                    .font(.system(size: 10.5))
                                    .monospacedDigit()
                                    .foregroundStyle(child.isProtected ? Color.orange : Color.secondary)
                                if model.cleanup(for: child) != nil {
                                    CleanControl(entry: child, compact: true)
                                }
                                Button {
                                    model.reveal(path: child.path)
                                } label: {
                                    Image(systemName: "folder")
                                }
                                .buttonStyle(.borderless)
                                .help(tr("Afficher dans le Finder", "Show in Finder"))
                            }
                            // Pour une app, le chemin dit tout (« Données », « Cache »…) ; ailleurs, l'explication.
                            Text(isApp ? storagePath(child.path) : child.explanation.text)
                                .font(.system(size: 10.5))
                                .foregroundStyle(.tertiary)
                                .lineLimit(isApp ? 1 : 2)
                                .truncationMode(isApp ? .middle : .tail)
                            if model.isDeveloper, let command = child.command {
                                CommandRow(label: "", command: command)
                            }
                        }
                        .help(isApp ? child.explanation.text : storagePath(child.path))
                    }
                }
                .padding(7)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.04)))
            }
            if model.isDeveloper, let command = entry.command {
                CommandRow(label: tr("Nettoyage officiel :", "Official cleanup:"), command: command)
            }
            if model.cleanup(for: entry) != nil {
                CleanControl(entry: entry, compact: false)
            }
            HStack(spacing: 12) {
                if !entry.path.isEmpty {
                    Button {
                        model.reveal(path: entry.path)
                    } label: {
                        Label(tr("Afficher dans le Finder", "Show in Finder"), systemImage: "folder")
                    }
                }
                if isApp, model.canUninstall(entry), model.uninstallStates[entry.path] == nil {
                    Button {
                        model.beginUninstall(entry)
                    } label: {
                        Label(tr("Désinstaller…", "Uninstall…"), systemImage: "trash")
                    }
                    .help(tr("Choisis ce qui part : l'app et ses dossiers, à la corbeille.", "Choose what goes: the app and its folders, to the Trash."))
                }
                if hasProtected {
                    Button {
                        model.openFullDiskAccessSettings()
                    } label: {
                        Label(tr("Autoriser l'accès complet au disque", "Allow Full Disk Access"), systemImage: "lock.open")
                    }
                    .help(tr("Réglages Système › Confidentialité et sécurité › Accès complet au disque : ajoute Vigie pour mesurer les dossiers protégés.",
                             "System Settings › Privacy & Security › Full Disk Access: add Vigie to measure protected folders."))
                }
            }
            .buttonStyle(.borderless)
            .font(.system(size: 11))
        }
    }
}

/// Nettoyer une ligne : premier clic, puis confirmation avec la taille (annulée au bout de 4 s), puis le résultat.
struct CleanControl: View {
    @Environment(AppModel.self) private var model
    let entry: StorageEntry
    /// Version courte, pour un sous-dossier : une icône, puis « Vider ? ».
    let compact: Bool

    var body: some View {
        if let cleanup = model.cleanup(for: entry) {
            switch model.cleanStates[entry.path] {
            case .confirming?:
                HStack(spacing: 4) {
                    Button(confirmation(cleanup)) { model.clean(entry) }
                        .buttonStyle(DangerButtonStyle())
                    Button {
                        model.cancelClean(entry)
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
                    if !compact { Text(tr("Nettoyage…", "Cleaning…")).font(.system(size: 11)).foregroundStyle(.secondary) }
                }
            case .done(let freed, let inTrash)?:
                Text(done(freed: freed, inTrash: inTrash))
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.green)
                    .fixedSize(horizontal: false, vertical: true)
            case .failed(let message)?:
                Text(tr("Échec : \(message)", "Failed: \(message)"))
                    .font(.system(size: 10.5))
                    .foregroundStyle(.red)
                    .lineLimit(compact ? 1 : 3)
                    .help(message)
            case nil:
                if compact {
                    Button {
                        model.requestClean(entry)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .help(label(cleanup))
                } else {
                    Button {
                        model.requestClean(entry)
                    } label: {
                        if cleanup.goesToTrash || cleanup == .emptyTrash {
                            Label(label(cleanup), systemImage: "trash")
                        } else {
                            Text(label(cleanup))
                        }
                    }
                    .buttonStyle(.borderless)
                    .font(.system(size: 11, weight: .medium))
                    .help(explanation(cleanup))
                }
            }
        }
    }

    private var size: String { Format.bytes(entry.size, decimal: true) }

    private func label(_ cleanup: StorageCleanup) -> String {
        switch cleanup {
        case .command(let command):
            // En mode Simple, la commande se fait oublier : on dit ce qu'elle fait.
            return model.isDeveloper ? tr("Lancer « \(command) »", "Run “\(command)”") : tr("Vider ce cache (\(size))", "Clear this cache (\(size))")
        case .delete: return tr("Vider ce cache (\(size))", "Clear this cache (\(size))")
        case .trash: return tr("Mettre à la corbeille (\(size))", "Move to Trash (\(size))")
        case .trashAll(let paths): return tr("Tout mettre à la corbeille (\(paths.count) éléments, \(size))", "Move all to Trash (\(paths.count) items, \(size))")
        case .emptyTrash: return tr("Vider la corbeille", "Empty the Trash")
        }
    }

    private func confirmation(_ cleanup: StorageCleanup) -> String {
        switch cleanup {
        case .command: return compact ? tr("Lancer ?", "Run?") : tr("Lancer le nettoyage ?", "Run the cleanup?")
        case .delete: return compact ? tr("Vider ?", "Clear?") : tr("Supprimer \(size) ?", "Delete \(size)?")
        case .trash, .trashAll: return compact ? tr("Corbeille ?", "Trash?") : tr("Mettre \(size) à la corbeille ?", "Move \(size) to Trash?")
        case .emptyTrash: return tr("Vider ? C'est définitif", "Empty? It's permanent")
        }
    }

    private func explanation(_ cleanup: StorageCleanup) -> String {
        switch cleanup {
        case .command: return tr("Lance la commande officielle de l'outil : elle sait ce qui peut partir.", "Runs the tool's official command: it knows what can go.")
        case .delete: return tr("Supprimé pour de bon : un cache se recrée tout seul quand l'app en a besoin.", "Deleted for good: a cache rebuilds itself when the app needs it.")
        case .trash: return tr("À la corbeille, pour pouvoir revenir en arrière ; « npm install » les réinstalle.", "To the Trash, so you can undo; “npm install” reinstalls them.")
        case .trashAll: return tr("Tout part à la corbeille : tu peux revenir en arrière.", "Everything goes to the Trash: you can undo.")
        case .emptyTrash: return tr("Efface pour de bon ce qui est dans la corbeille (Vigie le demande au Finder ; la première fois, macOS demande ton accord).",
                                    "Permanently erases what's in the Trash (Vigie asks the Finder; the first time, macOS asks for your approval).")
        }
    }

    private func done(freed: UInt64, inTrash: Bool) -> String {
        let amount = Format.bytes(freed, decimal: true)
        if inTrash { return tr("✓ \(amount) dans la corbeille : vide-la pour récupérer la place", "✓ \(amount) in the Trash: empty it to get the space back") }
        return compact ? "✓ \(amount)" : tr("✓ \(amount) libérés", "✓ \(amount) freed")
    }
}

/// « Nettoyer ce qui est sûr » : le bouton, puis le récapitulatif avant de confirmer, la progression et le résultat.
struct SafeCleanArea: View {
    @Environment(AppModel.self) private var model
    /// Dans le panneau, le bouton est déjà en haut (pastille « Nettoyer ») : ici, seulement le récapitulatif et la suite.
    var showsButton = true

    var body: some View {
        let items = model.safeCleanItems
        let total = items.reduce(UInt64(0)) { $0 + $1.size }
        switch model.safeClean {
        case .reviewing?:
            VStack(alignment: .leading, spacing: 5) {
                Text(tr("Vider \(Format.bytes(total, decimal: true)) de caches ?", "Clear \(Format.bytes(total, decimal: true)) of caches?"))
                    .font(.system(size: 12, weight: .semibold))
                Text(tr("Seulement des caches qui se recréent tout seuls, avec la commande officielle de l'outil quand il y en a une. Pas les modèles d'IA, ni tes projets, ni tes fichiers.",
                        "Only caches that rebuild themselves, with the tool's official command when there is one. Not AI models, your projects or your files."))
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(items.prefix(8)) { item in
                        HStack {
                            Text(item.title.text).font(.system(size: 11)).lineLimit(1)
                            Spacer()
                            Text(Format.bytes(item.size, decimal: true)).font(.system(size: 10.5)).monospacedDigit().foregroundStyle(.secondary)
                        }
                    }
                    if items.count > 8 {
                        Text(tr("+ \(items.count - 8) autres", "+ \(items.count - 8) more")).font(.system(size: 10.5)).foregroundStyle(.tertiary)
                    }
                }
                .padding(7)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.05)))
                HStack(spacing: 8) {
                    Button(tr("Nettoyer", "Clean")) { model.runSafeClean() }
                        .buttonStyle(DangerButtonStyle())
                    Button(tr("Annuler", "Cancel")) { model.cancelSafeClean() }
                        .buttonStyle(.borderless)
                        .font(.system(size: 11))
                }
                .controlSize(.small)
            }
        case .running(let done, let count)?:
            VStack(alignment: .leading, spacing: 4) {
                Text(tr("Nettoyage… \(done)/\(count)", "Cleaning… \(done)/\(count)")).font(.system(size: 11)).foregroundStyle(.secondary)
                ProgressView(value: Double(done), total: Double(max(count, 1))).progressViewStyle(.linear)
            }
        case .finished(let freed, let failures)?:
            Text(failures == 0
                 ? tr("✓ \(Format.bytes(freed, decimal: true)) libérés.", "✓ \(Format.bytes(freed, decimal: true)) freed.")
                 : tr("✓ \(Format.bytes(freed, decimal: true)) libérés · \(failures) n'ont pas pu être nettoyés (détail sur chaque ligne).",
                      "✓ \(Format.bytes(freed, decimal: true)) freed · \(failures) couldn't be cleaned."))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.green)
        case nil:
            if !items.isEmpty, showsButton {
                Button {
                    model.reviewSafeClean()
                } label: {
                    Text(tr("Nettoyer ce qui est sûr · \(Format.bytes(total, decimal: true))", "Clean what's safe · \(Format.bytes(total, decimal: true))"))
                }
                .buttonStyle(PrimaryButtonStyle())
                .help(tr("Les caches qui se recréent tout seuls. Un récapitulatif s'affiche avant de nettoyer.",
                         "Caches that rebuild themselves. A summary shows before anything is cleaned."))
            }
        }
    }
}

/// Désinstaller : l'app et ses dossiers, cochables ; un dossier protégé ou partagé avec une autre app reste décoché.
struct UninstallPanel: View {
    @Environment(AppModel.self) private var model
    let entry: StorageEntry

    var body: some View {
        let items = AppUninstaller.items(for: entry)
        VStack(alignment: .leading, spacing: 6) {
            switch model.uninstallStates[entry.path] {
            case .choosing(let selected)?:
                let chosen = items.filter { selected.contains($0.path) && $0.blocked == nil }
                let size = chosen.reduce(UInt64(0)) { $0 + $1.size }
                Text(tr("Désinstaller \(entry.title.text) ?", "Uninstall \(entry.title.text)?"))
                    .font(.system(size: 12, weight: .semibold))
                Text(tr("Tout part à la corbeille : tu peux revenir en arrière.", "Everything goes to the Trash: you can undo."))
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(items) { item in
                        HStack(alignment: .top, spacing: 6) {
                            Toggle("", isOn: Binding(get: { selected.contains(item.path) && item.blocked == nil },
                                                     set: { _ in model.toggleUninstallItem(item.path, of: entry) }))
                                .toggleStyle(.checkbox)
                                .labelsHidden()
                                .disabled(item.blocked != nil)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(item.title.text).font(.system(size: 11, weight: .medium)).lineLimit(1)
                                Text(item.blocked?.text ?? storagePath(item.path))
                                    .font(.system(size: 10))
                                    .foregroundStyle(item.blocked == nil ? Color.secondary : Color.orange)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            Spacer(minLength: 4)
                            Text(Format.bytes(item.size, decimal: true)).font(.system(size: 10.5)).monospacedDigit().foregroundStyle(.secondary)
                        }
                        .opacity(item.blocked == nil ? 1 : 0.6)
                    }
                }
                .padding(7)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.04)))
                if selected.contains(entry.path), model.isRunning(entry.path) {
                    Text(tr("\(entry.title.text) sera quittée d'abord.", "\(entry.title.text) will be quit first."))
                        .font(.system(size: 10.5))
                        .foregroundStyle(.orange)
                }
                HStack(spacing: 8) {
                    Button(tr("Mettre \(chosen.count) élément\(chosen.count > 1 ? "s" : "") à la corbeille (\(Format.bytes(size, decimal: true)))",
                              "Move \(chosen.count) item\(chosen.count > 1 ? "s" : "") to Trash (\(Format.bytes(size, decimal: true)))")) {
                        model.uninstall(entry)
                    }
                    .buttonStyle(DangerButtonStyle())
                    .disabled(chosen.isEmpty)
                    Button(tr("Annuler", "Cancel")) { model.cancelUninstall(entry) }
                        .buttonStyle(.borderless)
                        .font(.system(size: 11))
                }
                .controlSize(.small)
            case .running?:
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text(tr("Désinstallation…", "Uninstalling…")).font(.system(size: 11)).foregroundStyle(.secondary)
                }
            case .failed(let message)?:
                Text(tr("Échec : \(message)", "Failed: \(message)")).font(.system(size: 11)).foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                Button(tr("Fermer", "Close")) { model.cancelUninstall(entry) }
                    .buttonStyle(.borderless)
                    .font(.system(size: 11))
            case nil:
                EmptyView()
            }
        }
    }
}

/// Bascule « Processus | Stockage » de l'en-tête.
struct ModePicker: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Picker("", selection: $model.mode) {
            Text(model.isDeveloper ? tr("Processus", "Processes") : tr("Ce qui tourne", "Running")).tag(PanelMode.processes)
            Text(tr("Vitesse", "Speed")).tag(PanelMode.speed)
            Text(model.isDeveloper ? tr("Stockage", "Storage") : tr("Espace disque", "Disk space")).tag(PanelMode.storage)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
        .controlSize(.small)
    }
}

/// Mise en page qui passe à la ligne quand la place manque (filtres de la vue d'ensemble).
struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    var lineSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0, widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width {
                x = 0
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            x += size.width + spacing
            widest = max(widest, x - spacing)
            lineHeight = max(lineHeight, size.height)
        }
        return CGSize(width: proposal.width ?? widest, height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, lineHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                x = bounds.minX
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}

extension StorageKind {
    /// Couleur de la famille : barre, pastilles, icônes.
    var tint: Color {
        switch self {
        // Vert : sans risque. Orange : à vérifier avant. Gris : à garder, ou géré par macOS.
        case .cache: return .green
        case .project, .application, .largeFile, .leftover: return .orange
        case .appData, .personal, .systemData: return .gray
        }
    }
}

/// Chemin abrégé avec « ~ », y compris pour le dossier personnel fictif du mode démo.
func storagePath(_ path: String) -> String {
    PathRules.abbreviate(path, home: path.hasPrefix(DemoData.home) ? DemoData.home : NSHomeDirectory())
}

// MARK: - Sélection de plusieurs lignes

/// Case à cocher d'une ligne qui peut aller à la corbeille.
struct SelectionBox: View {
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: selected ? "checkmark.square.fill" : "square")
                .font(.system(size: 14))
                .foregroundStyle(selected ? VigieTheme.accent : Color.secondary)
                .frame(width: 20, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(selected ? tr("Décocher", "Uncheck") : tr("Cocher pour mettre à la corbeille avec d'autres", "Check to move to the Trash with others"))
    }
}

/// « Tout cocher » au-dessus d'une liste.
struct SelectAllRow: View {
    @Environment(AppModel.self) private var model
    let entries: [StorageEntry]

    var body: some View {
        let all = entries.allSatisfy { model.storageSelection.contains($0.id) }
        HStack(spacing: 8) {
            SelectionBox(selected: all) { model.setSelection(entries, selected: !all) }
            Text(all ? tr("Tout décocher", "Uncheck all") : tr("Tout cocher (\(entries.count))", "Check all (\(entries.count))"))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.leading, 10)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture { model.setSelection(entries, selected: !all) }
    }
}

/// Barre du bas quand des lignes sont cochées : combien, quelle taille, et un bouton pour tout mettre à la corbeille
/// (confirmation annulée au bout de 4 s, comme partout).
struct SelectionBar: View {
    @Environment(AppModel.self) private var model
    @Environment(\.inVigieWindow) private var inWindow

    var body: some View {
        let selected = model.selectedEntries
        let size = Format.bytes(selected.reduce(0) { $0 + $1.size }, decimal: true)
        if !selected.isEmpty || model.selectionState != nil {
            HStack(spacing: 10) {
                switch model.selectionState {
                case .running(let done, let total)?:
                    ProgressView().controlSize(.small)
                    Text(tr("Mise à la corbeille… \(done)/\(total)", "Moving to Trash… \(done)/\(total)"))
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                    Spacer()
                case .finished(let freed, let failures)?:
                    Image(systemName: failures == 0 ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(failures == 0 ? Color.green : Color.orange)
                    Text(failures == 0
                         ? tr("\(Format.bytes(freed, decimal: true)) à la corbeille. La place revient quand tu la vides.",
                              "\(Format.bytes(freed, decimal: true)) moved to the Trash. The space comes back when you empty it.")
                         : tr("\(Format.bytes(freed, decimal: true)) à la corbeille, \(failures) élément\(failures > 1 ? "s" : "") n'a pas pu partir.",
                              "\(Format.bytes(freed, decimal: true)) moved to the Trash, \(failures) item\(failures > 1 ? "s" : "") could not be moved."))
                        .font(.system(size: 12, weight: .medium))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    if !selected.isEmpty { trashButton(selected.count, size) }
                default:
                    Text(tr("\(selected.count) coché\(selected.count > 1 ? "s" : "") · \(size)", "\(selected.count) checked · \(size)"))
                        .font(.system(size: 12, weight: .semibold))
                    Button(tr("Tout décocher", "Uncheck all")) { model.clearSelection() }
                        .buttonStyle(.borderless)
                        .font(.system(size: 11.5))
                    Spacer()
                    if model.selectionState == .confirming {
                        Button(tr("Mettre \(size) à la corbeille ?", "Move \(size) to Trash?")) { model.trashSelection() }
                            .buttonStyle(DangerButtonStyle())
                        Button {
                            model.cancelTrashSelection()
                        } label: {
                            Image(systemName: "xmark")
                        }
                        .buttonStyle(.borderless)
                        .help(tr("Annuler", "Cancel"))
                    } else {
                        trashButton(selected.count, size)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.bar)
            .overlay(alignment: .top) { Divider() }
        }
    }

    @ViewBuilder
    private func trashButton(_ count: Int, _ size: String) -> some View {
        let button = Button {
            model.requestTrashSelection()
        } label: {
            Label(inWindow ? tr("Mettre à la corbeille (\(size))", "Move to Trash (\(size))") : tr("Corbeille", "Trash"), systemImage: "trash")
                .lineLimit(1)
        }
        .help(tr("Les \(count) éléments cochés vont à la corbeille : tu peux revenir en arrière.",
                 "The \(count) checked items go to the Trash: you can undo."))
        if inWindow { button.buttonStyle(AccentButtonStyle()) } else { button.buttonStyle(PrimaryButtonStyle()) }
    }
}
