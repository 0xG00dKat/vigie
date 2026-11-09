import SwiftUI
import VigieCore

/// Vue d'ensemble en grille : trois cartes (l'état du Mac, le stockage, la mémoire), puis « ce qui prend de la place »
/// et « ce qui tourne » côte à côte. Le nettoyage sûr et l'analyse prennent toute la largeur quand ils sont en cours.
struct OverviewBento: View {
    @Environment(AppModel.self) private var model
    @Binding var page: WindowPage?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PageHeader(title: tr("Vue d'ensemble", "Overview"),
                           subtitle: tr("Ce qui tourne et ce qui prend de la place, expliqué simplement.",
                                        "What's running and what takes up space, explained simply.")) {
                    VStack(alignment: .trailing, spacing: 6) {
                        if model.storageProgress != nil {
                            Chip(text: tr("Analyse en cours", "Analyzing"), symbol: "hourglass")
                        } else if let report = model.storage {
                            Chip(text: tr("Analysé \(Format.elapsed(since: report.date))", "Analyzed \(Format.elapsed(since: report.date))"), symbol: "checkmark.circle.fill")
                            Button(tr("Analyser à nouveau", "Analyze again")) { model.scanStorage() }
                                .buttonStyle(.borderless)
                                .font(.system(size: 11.5))
                        }
                    }
                }
                .padding(.horizontal, -VigieTheme.pagePadding)
                .padding(.bottom, -16)
                if let update = model.visibleUpdate { UpdateBanner(state: update).padding(.horizontal, -12) }

                HStack(alignment: .top, spacing: 16) {
                    HealthTile()
                    StorageTile(page: $page)
                    MemoryTile(page: $page)
                }
                .fixedSize(horizontal: false, vertical: true)

                // Le récapitulatif du nettoyage sûr (« Libérer … sans risque ») s'ouvre ici, en grand.
                if model.safeClean != nil {
                    CleanupCard()
                }
                if model.storage == nil, model.storageProgress == nil {
                    ScanCard()
                }

                Grid(horizontalSpacing: 16, verticalSpacing: 16) {
                    GridRow(alignment: .top) {
                        if model.storage != nil {
                            BentoCell { SpaceUsageList(page: $page) }
                        }
                        BentoCell { RunningList(page: $page) }
                    }
                }
            }
            .padding(.horizontal, VigieTheme.pagePadding)
            .padding(.bottom, WindowGrid.pageBottom)
        }
    }
}

/// L'état du Mac : le point vert, orange ou rouge, une phrase, une action.
private struct HealthTile: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let health = model.health {
            TopTile(symbol: "eye", tint: StatusCard.color(health.level), title: health.title, text: health.message) {
                if case .quit(let id, let name)? = health.action, model.closeState(id) == .confirming {
                    HStack(spacing: 8) {
                        Button(tr("Quitter \(name) ?", "Quit \(name)?")) { model.performHealthAction(fromPanel: false, health: health) }
                            .buttonStyle(DangerButtonStyle())
                        Button(tr("Annuler", "Cancel")) { model.cancelConfirmation(id) }.buttonStyle(.borderless)
                    }
                } else if let progress = model.storageProgress {
                    ProgressView(value: progress).tint(VigieTheme.accent)
                } else if let title = SpeedStateTile.shortTitle(health) {
                    Button(title) { model.performHealthAction(fromPanel: false, health: health) }
                        .buttonStyle(.borderedProminent)
                        .tint(VigieTheme.accent)
                }
            }
        }
    }
}

/// Le stockage : la place libre en grand, une barre par niveau de risque, ce qui a grossi.
private struct StorageTile: View {
    @Environment(AppModel.self) private var model
    @Binding var page: WindowPage?

    var body: some View {
        if let disk = model.disk {
            let tint: Color = disk.isLow ? .red : disk.isTight ? .orange : .green
            TopTile(symbol: "internaldrive", tint: tint,
                    title: tr("\(Format.bytes(disk.available, decimal: true)) libres", "\(Format.bytes(disk.available, decimal: true)) free"),
                    text: tr("sur \(Format.bytes(disk.total, decimal: true)) · \(100 - disk.freePercent) % utilisés",
                             "of \(Format.bytes(disk.total, decimal: true)) · \(100 - disk.freePercent)% used")) {
                VStack(alignment: .leading, spacing: 8) {
                    RiskBar(report: model.storage, disk: disk, kinds: model.visibleKinds)
                    if let report = model.storage {
                        HStack(spacing: 12) {
                            legend(DS.safe, tr("Sûr", "Safe"), model.reclaimable(report))
                            legend(DS.review, tr("À vérifier", "Review"), size(report, .review))
                        }
                    }
                    if let report = model.visibleReport, model.storageProgress == nil,
                       let growth = DiskDiagnosis.make(report: report, previous: model.storageReference).growthLine() {
                        Text(growth).font(.system(size: 11)).foregroundStyle(.orange).lineLimit(2)
                    }
                }
            }
        }
    }

    private func size(_ report: StorageReport, _ level: DSLevel) -> UInt64 {
        model.visibleKinds.filter { $0 != .largeFile && DSLevel($0) == level }
            .reduce(0) { sum, kind in sum + report.entries(of: kind).reduce(0) { $0 + $1.size } }
    }

    private func legend(_ color: Color, _ title: String, _ value: UInt64) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(title).font(.system(size: 11.5)).foregroundStyle(.secondary)
            Text(Format.bytes(value, decimal: true)).font(.system(size: 11.5, weight: .semibold)).monospacedDigit()
        }
        .fixedSize()
    }
}

/// Barre du disque : sûr, à vérifier, à garder, le reste, puis la place libre.
struct RiskBar: View {
    let report: StorageReport?
    let disk: DiskStatus
    let kinds: [StorageKind]

    var body: some View {
        let total = Double(max(disk.total, 1))
        let levels: [DSLevel] = [.safe, .review, .keep]
        let sizes = levels.map { level in
            Double(kinds.filter { $0 != .largeFile && DSLevel($0) == level }.reduce(UInt64(0)) { sum, kind in
                sum + (report?.entries(of: kind).reduce(0) { $0 + $1.size } ?? 0)
            })
        }
        let used = Double(disk.total - disk.available)
        let other = max(0, used - sizes.reduce(0, +))
        GeometryReader { geometry in
            HStack(spacing: 2) {
                ForEach(Array(zip(levels.indices, sizes)), id: \.0) { index, size in
                    if size / total > 0.003 {
                        Rectangle().fill(levels[index].color).frame(width: geometry.size.width * size / total)
                    }
                }
                Rectangle().fill(DS.keep.opacity(0.35)).frame(width: geometry.size.width * other / total)
                Rectangle().fill(Color.primary.opacity(0.07))
            }
            .clipShape(Capsule())
        }
        .frame(height: 10)
    }
}

/// La mémoire : utilisée sur le total, l'état (pression), l'app qui en prend le plus.
private struct MemoryTile: View {
    @Environment(AppModel.self) private var model
    @Binding var page: WindowPage?

    var body: some View {
        if let snapshot = model.snapshot {
            let pressure = model.performance?.memory.pressure ?? .normal
            let tint: Color = pressure == .critical ? .red : pressure == .warning ? .orange : .green
            let ratio = Double(snapshot.memoryUsed) / Double(max(snapshot.memoryTotal, 1))
            TopTile(symbol: "memorychip", tint: tint,
                    title: tr("\(Format.bytes(snapshot.memoryUsed)) de mémoire", "\(Format.bytes(snapshot.memoryUsed)) of memory"),
                    text: tr("sur \(Format.bytes(snapshot.memoryTotal)) · \(pressure == .normal ? "assez pour l'instant" : pressure == .warning ? "un peu juste" : "il en manque")",
                             "of \(Format.bytes(snapshot.memoryTotal)) · \(pressure == .normal ? "enough for now" : pressure == .warning ? "a bit tight" : "not enough")"),
                    lesson: "memoire") {
                VStack(alignment: .leading, spacing: 8) {
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.primary.opacity(0.07))
                            Capsule().fill(tint).frame(width: geometry.size.width * min(1, ratio))
                        }
                    }
                    .frame(height: 10)
                    if let top = model.memoryGroups.first {
                        Button {
                            page = .speed
                        } label: {
                            HStack(spacing: 5) {
                                Text(tr("Le plus gourmand :", "Hungriest:")).foregroundStyle(.secondary)
                                Text(top.title).fontWeight(.semibold)
                                Text(Format.bytes(top.memory)).foregroundStyle(.secondary).monospacedDigit()
                            }
                            .font(.system(size: 11.5))
                            .lineLimit(1)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

/// « Ce qui prend de la place » : une ligne par famille, son niveau, sa taille.
private struct SpaceUsageList: View {
    @Environment(AppModel.self) private var model
    @Binding var page: WindowPage?

    var body: some View {
        if let report = model.storage, let disk = model.disk {
            let kinds = model.visibleKinds.filter { !report.entries(of: $0).isEmpty }
            VStack(alignment: .leading, spacing: 4) {
                Text(tr("Ce qui prend de la place", "What takes up space")).font(.system(size: 15, weight: .semibold))
                    .padding(.bottom, 6)
                ForEach(kinds, id: \.self) { kind in
                    let entries = report.entries(of: kind)
                    let size = entries.reduce(UInt64(0)) { $0 + $1.size }
                    CompactRow(symbol: kind.outlineSymbol, title: kind.overviewTitle, badge: kind.reviewBadge,
                               detail: percent(Double(size) / Double(max(disk.total, 1))),
                               value: Format.bytes(size, decimal: true)) {
                        page = .storage(kind)
                    }
                }
            }
        }
    }
}

/// « Ce qui tourne » : les familles de processus, leur nombre et leur mémoire.
private struct RunningList: View {
    @Environment(AppModel.self) private var model
    @Binding var page: WindowPage?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(tr("Ce qui tourne", "What's running")).font(.system(size: 15, weight: .semibold))
            if let snapshot = model.snapshot {
                Text(model.processSummary(snapshot)).font(.system(size: 11.5)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 6)
            }
            ForEach(model.visibleCategories) { category in
                let groups = model.visibleGroups(in: category)
                CompactRow(symbol: category.outlineSymbol, title: category.title, badge: nil,
                           detail: "\(groups.count)",
                           value: Format.bytes(groups.reduce(0) { $0 + $1.memory })) {
                    if category == .dev {
                        page = .processes(.dev)
                    } else {
                        model.runningFilter = [category]
                        page = .running
                    }
                }
            }
        }
    }
}

/// Ligne compacte d'une carte : tuile, titre et étiquette, détail discret, valeur, chevron.
private struct CompactRow: View {
    let symbol: String
    let title: String
    let badge: (text: String, color: Color)?
    let detail: String
    let value: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                VigieTile(symbol: symbol, size: 26)
                Text(title).font(.system(size: 13, weight: .medium)).lineLimit(1)
                if let badge {
                    // Le niveau en un point de couleur (le mot au survol) : les noms gardent la place.
                    Circle().fill(badge.color).frame(width: 7, height: 7).help(badge.text)
                }
                Spacer(minLength: 8)
                Text(detail).font(.system(size: 11.5)).monospacedDigit().foregroundStyle(.tertiary)
                Text(value).font(.system(size: 13, weight: .semibold)).monospacedDigit()
                    .frame(minWidth: 62, alignment: .trailing)
                Image(systemName: "chevron.right").font(.system(size: 9.5, weight: .semibold)).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(hovering ? Color.primary.opacity(0.05) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .padding(.horizontal, -8)
    }
}
