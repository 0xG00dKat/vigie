import SwiftUI
import VigieCore

/// Maquette du nouveau design : la Vue d'ensemble (activée par la clé `nouveauDesign` ou l'option `--redesign`).
struct RedesignOverviewPage: View {
    @Environment(AppModel.self) private var model
    @Binding var page: WindowPage?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if model.demoSection == "icons" {
                    IconSheet()
                } else if model.demoSection == "table" {
                    SpaceTableCard(page: $page)
                } else {
                header
                if let step = model.demoScanStep {
                    ScanStepsCard(current: step)
                }
                HeroCard()
                HStack(alignment: .top, spacing: 18) {
                    StorageSummaryCard()
                    RunningCard(page: $page)
                        .frame(width: 300)
                }
                SpaceTableCard(page: $page)
                }
            }
            .padding(.horizontal, DS.pagePadding)
            .padding(.top, 26)
            .padding(.bottom, 32)
            .frame(maxWidth: 980, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(DS.canvas.ignoresSafeArea())
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text(tr("Vue d'ensemble", "Overview")).font(.system(size: 30, weight: .bold)).foregroundStyle(DS.primaryText)
                if model.storageProgress != nil || model.demoScanStep != nil {
                    StatePill(text: tr("Analyse en cours", "Analyzing"), color: DS.accent, style: .dashed)
                } else if let report = model.storage {
                    StatePill(text: tr("Analysé \(Format.elapsed(since: report.date))", "Analyzed \(Format.elapsed(since: report.date))"), color: DS.safe)
                }
            }
            Spacer()
        }
    }
}

/// L'état du Mac, une phrase, la grande action en dégradé, et le bac de commandes tactiles.
private struct HeroCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let health = model.health {
            let level: DSLevel = health.level == .good ? .safe : health.level == .attention ? .review : .urgent
            DSCard(padding: 22) {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 10) {
                        LevelBadge(level: level, text: health.level == .good ? tr("TOUT VA BIEN", "ALL GOOD") : level.label)
                        Text(health.title).font(.system(size: 22, weight: .semibold)).foregroundStyle(DS.primaryText)
                    }
                    Text(health.message).font(.system(size: 14)).foregroundStyle(DS.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 16) {
                        if let title = health.actionTitle() {
                            // Un bouton système, le seul en couleur de la page.
                            Button(title) { model.performHealthAction(fromPanel: false) }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.large)
                                .tint(DS.accent)
                        }
                        Spacer()
                    }
                }
            }
        }
    }
}

/// Le disque : la place libre en grand (monospace), une barre en segments par famille, ce qui a grossi.
private struct StorageSummaryCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let disk = model.disk {
            DSCard {
                VStack(alignment: .leading, spacing: 16) {
                    DSCardHeader(title: tr("Stockage", "Storage")) {
                        Text(tr("\(100 - disk.freePercent) % utilisés", "\(100 - disk.freePercent)% used")).font(DS.number(12)).foregroundStyle(DS.secondaryText)
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(Format.bytes(disk.available, decimal: true)).font(DS.number(40, .semibold)).foregroundStyle(DS.primaryText)
                        Text(tr("libres sur \(Format.bytes(disk.total, decimal: true))", "free of \(Format.bytes(disk.total, decimal: true))"))
                            .font(.system(size: 13)).foregroundStyle(DS.secondaryText)
                    }
                    SegmentBar(report: model.storage, disk: disk, kinds: model.visibleKinds)
                    HStack(spacing: 16) {
                        legend(DS.safe, tr("Sûr", "Safe"))
                        legend(DS.review, tr("À vérifier", "Review"))
                        legend(DS.keep, tr("À garder", "Keep"))
                        legend(DS.accent.opacity(0.25), tr("Libre", "Free"))
                    }
                    if let report = model.visibleReport, model.storageProgress == nil,
                       let growth = DiskDiagnosis.make(report: report, previous: model.storageReference).growthLine() {
                        HStack(alignment: .top, spacing: 8) {
                            Circle().fill(DS.review).frame(width: 7, height: 7).padding(.top, 5)
                            Text(growth).font(.system(size: 12.5, weight: .medium)).foregroundStyle(DS.review).fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: DS.rowRadius, style: .continuous).fill(DS.review.opacity(0.08)))
                        .overlay(alignment: .leading) { Capsule().fill(DS.review).frame(width: 3).padding(.vertical, 6) }
                    }
                }
            }
        }
    }

    private func legend(_ color: Color, _ title: String) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 9, height: 9)
            Text(title).font(.system(size: 12)).foregroundStyle(DS.secondaryText)
        }
    }
}

/// Barre du disque en segments arrondis, colorés par niveau (sûr, à vérifier, à garder), la place libre en bleu pâle.
private struct SegmentBar: View {
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
            let width = geometry.size.width - 4 * 3
            HStack(spacing: 3) {
                ForEach(Array(zip(levels, sizes)), id: \.0) { level, size in
                    if size > 0 { RoundedRectangle(cornerRadius: 4).fill(level.color).frame(width: max(4, width * size / total)) }
                }
                RoundedRectangle(cornerRadius: 4).fill(DS.keep.opacity(0.45)).frame(width: max(4, width * other / total))
                RoundedRectangle(cornerRadius: 4).fill(DS.accent.opacity(0.25))
            }
        }
        .frame(height: 14)
    }
}

extension DSLevel: Hashable {}

/// Ce qui tourne : une ligne par catégorie, nombre et mémoire en monospace.
private struct RunningCard: View {
    @Environment(AppModel.self) private var model
    @Binding var page: WindowPage?

    var body: some View {
        DSCard(padding: 18) {
            VStack(alignment: .leading, spacing: 12) {
                DSCardHeader(title: tr("Ce qui tourne", "Running")) {
                    if let snapshot = model.snapshot {
                        Text(Format.bytes(snapshot.memoryUsed)).font(DS.number(12)).foregroundStyle(DS.secondaryText)
                    }
                }
                ForEach(model.visibleCategories) { category in
                    let groups = model.visibleGroups(in: category)
                    Button {
                        page = category == .dev ? .processes(.dev) : .running
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: category.outlineSymbol).font(.system(size: 13)).foregroundStyle(DS.secondaryText).frame(width: 18)
                            Text(category.title).font(.system(size: 13)).foregroundStyle(DS.primaryText)
                            Spacer()
                            Text("\(groups.count)").font(DS.number(12)).foregroundStyle(DS.tertiaryText)
                            Text(Format.bytes(groups.reduce(0) { $0 + $1.memory })).font(DS.number(13, .medium)).foregroundStyle(DS.primaryText)
                                .frame(width: 70, alignment: .trailing)
                        }
                        .padding(.vertical, 3)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

/// Ce qui prend de la place, en tableau : famille, niveau, part du disque, taille.
private struct SpaceTableCard: View {
    @Environment(AppModel.self) private var model
    @Binding var page: WindowPage?

    var body: some View {
        if let report = model.storage, let disk = model.disk {
            let kinds = model.visibleKinds.filter { !report.entries(of: $0).isEmpty }
            DSCard(padding: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    DSCardHeader(title: tr("Ce qui prend de la place", "What takes up space")) {
                        FilterPill(symbol: "line.3.horizontal.decrease", title: tr("Tout", "All"), count: kinds.count)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                    .padding(.bottom, 12)
                    HStack {
                        Text(tr("Famille", "Category")).frame(maxWidth: .infinity, alignment: .leading)
                        Text(tr("Niveau", "Level")).frame(width: 110, alignment: .leading)
                        Text(tr("Part", "Share")).frame(width: 110, alignment: .leading)
                        Text(tr("Taille", "Size")).frame(width: 80, alignment: .trailing)
                    }
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(DS.tertiaryText)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 6)
                    ForEach(kinds, id: \.self) { kind in
                        let size = report.entries(of: kind).reduce(UInt64(0)) { $0 + $1.size }
                        SpaceRow(kind: kind, size: size, share: Double(size) / Double(max(disk.total, 1))) { page = .storage(kind) }
                    }
                }
                .padding(.bottom, 10)
            }
        }
    }
}

private struct SpaceRow: View {
    let kind: StorageKind
    let size: UInt64
    let share: Double
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        let level = DSLevel(kind)
        Button(action: action) {
            HStack {
                HStack(spacing: 10) {
                    Image(systemName: kind.outlineSymbol).font(.system(size: 13)).foregroundStyle(DS.secondaryText).frame(width: 18)
                    Text(kind.overviewTitle).font(.system(size: 13.5)).foregroundStyle(DS.primaryText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                LevelBadge(level: level).frame(width: 110, alignment: .leading)
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(DS.well)
                        Capsule().fill(level.color.opacity(0.8)).frame(width: max(3, geometry.size.width * min(1, share * 4)))
                    }
                }
                .frame(width: 90, height: 5)
                .frame(width: 110, alignment: .leading)
                Text(Format.bytes(size, decimal: true)).font(DS.number(13.5, .medium)).foregroundStyle(DS.primaryText)
                    .frame(width: 80, alignment: .trailing)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: DS.rowRadius, style: .continuous).fill(hovering ? DS.well : .clear))
            .padding(.horizontal, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// L'analyse du stockage, étape par étape (maquette : étapes et durées fictives).
private struct ScanStepsCard: View {
    let current: Int

    var body: some View {
        let base: [StepProgressCard.Step] = [
            StepProgressCard.Step(symbol: "folder", title: tr("Lu tes dossiers personnels", "Read your folders"), duration: 2.4),
            StepProgressCard.Step(symbol: "arrow.triangle.2.circlepath", title: tr("Mesuré les caches", "Measured caches"), duration: 3.1),
            StepProgressCard.Step(symbol: "app", title: tr("Rangé 86 apps et leurs dossiers", "Sorted 86 apps and their folders"), duration: 5.8),
            StepProgressCard.Step(symbol: "shippingbox", title: tr("Trouvé 28 projets de dev", "Found 28 dev projects"), duration: 1.9),
            StepProgressCard.Step(symbol: "doc", title: tr("Repéré les gros fichiers", "Spotted large files"), duration: 1.2),
            StepProgressCard.Step(symbol: "gearshape", title: tr("Détaillé les Données système", "Broke down System Data"), duration: 2.0),
        ]
        let steps: [StepProgressCard.Step] = base.enumerated().map { index, step in
            var step = step
            if index == current { step.title = step.title.replacingOccurrences(of: "Lu ", with: "Lecture de ") }
            if index >= current { step.duration = nil }
            return step
        }
        StepProgressCard(title: current >= steps.count ? tr("Analyse terminée · 76 Go récupérables", "Analysis done · 76 GB reclaimable")
                                                       : tr("Analyse du stockage", "Storage analysis"),
                         subtitle: tr("Rien n'est supprimé pendant l'analyse", "Nothing is deleted during the analysis"),
                         elapsed: [2.4, 5.5, 11.3, 13.2, 14.4, 16.4][min(current, 5)], steps: steps, current: current, onOpen: {})
    }
}

/// Planche de contrôle : toutes les icônes, sur leur tuile, en clair et en sombre (maquette).
private struct IconSheet: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach([ColorScheme.light, .dark], id: \.self) { scheme in
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(64), spacing: 18), count: 9), spacing: 18) {
                    ForEach(VigieIcon.allCases, id: \.self) { icon in VigieIconTile(icon: icon, size: 56) }
                }
                .padding(22)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(DS.surface))
                .environment(\.colorScheme, scheme)
            }
        }
    }
}
