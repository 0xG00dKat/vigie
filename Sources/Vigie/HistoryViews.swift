import Charts
import SwiftUI
import VigieCore

/// Historique : ce qui change dans le temps. Des phrases d'abord (ce qui a grossi, quand le disque sera plein,
/// les apps qui pèsent lourd), puis les courbes du disque et de la mémoire. Tout reste sur le Mac.
struct HistoryPage: View {
    @Environment(AppModel.self) private var model
    @State private var range: HistoryRange = .month

    enum HistoryRange: Hashable, CaseIterable {
        case week, month, quarter, year

        var days: Double {
            switch self {
            case .week: return 7
            case .month: return 30
            case .quarter: return 90
            case .year: return 365
            }
        }

        var title: String {
            switch self {
            case .week: return tr("7 jours", "7 days")
            case .month: return tr("30 jours", "30 days")
            case .quarter: return tr("3 mois", "3 months")
            case .year: return tr("1 an", "1 year")
            }
        }
    }

    var body: some View {
        let recent = model.history.filter { $0.storage == nil && Date().timeIntervalSince($0.date) <= range.days * 86_400 }
        // Au-delà d'une semaine, une moyenne par jour : sinon les mesures fines des derniers jours font des dents de scie.
        let points = range == .week ? recent : HistoryStore.dailyAverages(recent)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PageHeader(title: tr("Historique", "History"),
                           subtitle: tr("Vigie note quelques mesures par jour, sur ton Mac seulement : la place utilisée, la mémoire et les apps qui en prennent le plus.",
                                        "Vigie records a few measurements a day, on your Mac only: space used, memory and the apps using the most."),
                           lesson: "disque-se-remplit") {
                    PageTabs(selection: $range, tabs: HistoryRange.allCases.map { ($0, $0.title, "calendar") })
                }
                .padding(.bottom, -16)
                if model.demoSection == "apps" {
                    HeavyAppsCard(points: points).padding(.horizontal, VigieTheme.pagePadding)
                } else if model.history.filter({ $0.storage == nil }).count < 2 {
                    VigieCard(padding: 20) {
                        Label(tr("Les premières mesures arrivent : Vigie en prend une toutes les 3 heures. Reviens dans quelques jours pour voir les tendances.",
                                 "The first measurements are coming: Vigie takes one every 3 hours. Come back in a few days to see trends."),
                              systemImage: "clock")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, VigieTheme.pagePadding)
                } else {
                    HistoryBento(points: points, raw: model.history.filter { Date().timeIntervalSince($0.date) <= range.days * 86_400 }, range: range, insights: model.historyInsights)
                        .padding(.horizontal, VigieTheme.pagePadding)
                }
            }
            .padding(.bottom, 24)
        }
    }
}

/// L'historique en grille : trois cartes qui résument la période (disque, mémoire, l'app la plus lourde),
/// les deux courbes côte à côte, puis les phrases et le détail des apps.
struct HistoryBento: View {
    let points: [HistoryPoint]
    /// Les mesures brutes de la période (sans moyenne par jour) : l'écart du disque est le même que dans les phrases.
    let raw: [HistoryPoint]
    let range: HistoryPage.HistoryRange
    let insights: [HistoryInsight]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 16) {
                DiskTrendTile(points: raw, range: range, forecast: insights.first { $0.kind == .diskForecast })
                MemoryTrendTile(points: raw)
                HeaviestAppTile(points: points)
            }
            .fixedSize(horizontal: false, vertical: true)

            Grid(horizontalSpacing: 16, verticalSpacing: 16) {
                GridRow(alignment: .top) {
                    BentoCell { DiskHistoryCard(points: points) }
                    BentoCell { MemoryHistoryCard(points: points) }
                }
                GridRow(alignment: .top) {
                    BentoCell { InsightsCard(insights: insights) }
                    BentoCell { HeavyAppsCard(points: points) }
                }
            }
        }
    }
}

/// Le disque sur la période : ce qu'il a pris (ou rendu), et quand il sera plein si ça continue.
private struct DiskTrendTile: View {
    let points: [HistoryPoint]
    let range: HistoryPage.HistoryRange
    let forecast: HistoryInsight?

    var body: some View {
        let first = points.first, last = points.last
        let change = Int64(last?.diskUsed ?? 0) - Int64(first?.diskUsed ?? 0)
        let period = range.title
        let title: String = {
            if abs(change) < 1_000_000_000 { return tr("Disque stable", "Disk stable") }
            let amount = Format.bytes(UInt64(abs(change)), decimal: true)
            return change > 0 ? tr("+\(amount) en \(period)", "+\(amount) in \(period)")
                              : tr("\(amount) libérés en \(period)", "\(amount) freed in \(period)")
        }()
        let free = last.map { tr("\(Format.bytes($0.diskFree, decimal: true)) libres sur \(Format.bytes($0.diskTotal, decimal: true))",
                                 "\(Format.bytes($0.diskFree, decimal: true)) free of \(Format.bytes($0.diskTotal, decimal: true))") } ?? ""
        let tint: Color = forecast != nil || change >= 10_000_000_000 ? .orange : .green
        TopTile(symbol: "internaldrive", tint: tint, title: title,
                text: forecast?.text.text ?? free) {
            if forecast != nil, !free.isEmpty {
                Text(free).font(.system(size: 11.5)).foregroundStyle(.secondary)
            }
        }
    }
}

/// La mémoire sur la période : en moyenne, et au plus haut.
private struct MemoryTrendTile: View {
    let points: [HistoryPoint]

    var body: some View {
        let used = points.compactMap(\.memoryUsed)
        let total = points.compactMap(\.memoryTotal).last ?? 0
        if !used.isEmpty, total > 0 {
            let average = used.reduce(0, +) / UInt64(used.count)
            let peak = used.max() ?? 0
            let share = Double(average) / Double(total)
            TopTile(symbol: "memorychip", tint: share > 0.85 ? .orange : .green,
                    title: tr("\(Format.bytes(average)) en moyenne", "\(Format.bytes(average)) on average"),
                    text: tr("de mémoire, sur \(Format.bytes(total)) · jusqu'à \(Format.bytes(peak)) au plus haut",
                             "of memory, of \(Format.bytes(total)) · up to \(Format.bytes(peak)) at the highest")) {
                EmptyView()
            }
        }
    }
}

/// L'app qui prend le plus de mémoire d'habitude, et quand elle est ouverte.
private struct HeaviestAppTile: View {
    let points: [HistoryPoint]

    var body: some View {
        if let app = HistoryInsights.heavyApps(points, limit: 1).first {
            let total = Double(points.compactMap(\.memoryTotal).last ?? 0)
            let share = total > 0 ? Double(app.typical) / total : 0
            TopTile(symbol: "square.grid.2x2", tint: share > 0.15 ? .orange : .green,
                    title: tr("\(app.name) pèse le plus", "\(app.name) weighs the most"),
                    text: tr("environ \(Format.bytes(app.typical, decimal: true)) en général", "about \(Format.bytes(app.typical, decimal: true)) usually")
                        + (app.presence.map { " · " + $0.text.text.lowercasedFirst } ?? "")) {
                EmptyView()
            }
        }
    }
}

private extension String {
    var lowercasedFirst: String { prefix(1).lowercased() + dropFirst() }
}

/// Les phrases de l'historique, ou « rien à signaler ».
struct InsightsCard: View {
    let insights: [HistoryInsight]

    var body: some View {
        VigieCard(padding: 16) {
            VStack(alignment: .leading, spacing: 10) {
                Text(tr("Ce que racontent les dernières semaines", "What the last few weeks tell"))
                    .font(.system(size: 14, weight: .semibold))
                if insights.isEmpty {
                    Label(tr("Rien de notable : ton disque et ta mémoire sont stables.", "Nothing notable: your disk and memory are stable."),
                          systemImage: "checkmark.circle.fill")
                        .font(.system(size: 12.5))
                        .foregroundStyle(.green)
                }
                ForEach(insights) { insight in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: symbol(insight.kind))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(insight.isWarning ? Color.orange : VigieTheme.accent)
                            .frame(width: 18)
                        Text(insight.text.text)
                            .font(.system(size: 12.5))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private func symbol(_ kind: HistoryInsight.Kind) -> String {
        switch kind {
        case .diskGrowth: return "arrow.up.right"
        case .diskFreed: return "arrow.down.right"
        case .diskForecast: return "exclamationmark.triangle.fill"
        case .appMemory: return "memorychip"
        }
    }
}

struct DiskHistoryCard: View {
    let points: [HistoryPoint]

    var body: some View {
        let gigabyte = 1_000_000_000.0
        let total = Double(points.last?.diskTotal ?? 0) / gigabyte
        // L'axe commence un peu sous le plus bas : une hausse de 30 Go doit se voir sur un disque de 500 Go.
        let lowest = (points.map { Double($0.diskUsed) / gigabyte }.min() ?? 0)
        let floor = max(0, ((lowest - total * 0.1) / 50).rounded(.down) * 50)
        VigieCard(padding: 16) {
            VStack(alignment: .leading, spacing: 10) {
                Text(tr("Place utilisée sur le disque", "Disk space used")).font(.system(size: 14, weight: .semibold))
                Chart {
                    ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                        AreaMark(x: .value("Date", point.date), yStart: .value("", floor),
                                 yEnd: .value(tr("Utilisé", "Used"), Double(point.diskUsed) / gigabyte))
                            .foregroundStyle(VigieTheme.accent.opacity(0.18))
                        LineMark(x: .value("Date", point.date), y: .value(tr("Utilisé", "Used"), Double(point.diskUsed) / gigabyte))
                            .foregroundStyle(VigieTheme.accent)
                    }
                    if total > 0 {
                        RuleMark(y: .value(tr("Capacité", "Capacity"), total))
                            .foregroundStyle(Color.secondary.opacity(0.5))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    }
                }
                .chartYScale(domain: floor...max(total, floor + 1))
                .chartYAxis { AxisMarks { value in
                    AxisGridLine()
                    AxisValueLabel { if let gb = value.as(Double.self) { Text("\(Int(gb)) Go") } }
                } }
                .environment(\.locale, Locale(identifier: Localization.current == .fr ? "fr_FR" : "en_US"))
                .frame(height: 180)
                Text(tr("Pointillés : la capacité du disque.", "Dashed line: the disk's capacity."))
                    .font(.system(size: 10.5)).foregroundStyle(.tertiary)
            }
        }
    }
}

struct MemoryHistoryCard: View {
    let points: [HistoryPoint]

    var body: some View {
        let withMemory = points.filter { $0.memoryUsed != nil }
        let gib = 1_073_741_824.0
        let total = Double(withMemory.last?.memoryTotal ?? 0) / gib
        if !withMemory.isEmpty {
            VigieCard(padding: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(tr("Mémoire utilisée", "Memory used")).font(.system(size: 14, weight: .semibold))
                    Chart {
                        ForEach(Array(withMemory.enumerated()), id: \.offset) { _, point in
                            LineMark(x: .value("Date", point.date), y: .value(tr("Mémoire", "Memory"), Double(point.memoryUsed ?? 0) / gib))
                                .foregroundStyle(VigieTheme.accent)
                                .interpolationMethod(.monotone)
                        }
                    }
                    .chartYScale(domain: 0...max(total, 1))
                    .chartYAxis { AxisMarks { value in
                        AxisGridLine()
                        AxisValueLabel { if let gb = value.as(Double.self) { Text("\(Int(gb)) Go") } }
                    } }
                    .environment(\.locale, Locale(identifier: Localization.current == .fr ? "fr_FR" : "en_US"))
                    .frame(height: 180)
                }
            }
        }
    }
}

/// Les apps les plus lourdes : leur mémoire habituelle et leur maximum, une barre par rapport à la mémoire du Mac,
/// et à quel point elles sont ouvertes (dès qu'il y a assez de mesures pour le dire).
struct HeavyAppsCard: View {
    let points: [HistoryPoint]

    var body: some View {
        let apps = HistoryInsights.heavyApps(points)
        let measured = points.filter { $0.apps != nil }.count
        let total = Double(points.compactMap(\.memoryTotal).last ?? 0)
        if !apps.isEmpty {
            VigieCard(padding: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(tr("Les apps qui prennent le plus de mémoire", "The apps using the most memory")).font(.system(size: 14, weight: .semibold))
                    HStack {
                        Text(tr("App", "App")).frame(maxWidth: .infinity, alignment: .leading)
                        Text(tr("En général", "Usually")).frame(width: 90, alignment: .trailing)
                        Text(tr("Au plus", "At most")).frame(width: 90, alignment: .trailing)
                    }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.tertiary)
                    ForEach(apps, id: \.name) { app in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(alignment: .firstTextBaseline) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(app.name).font(.system(size: 12.5, weight: .medium))
                                    if let presence = app.presence {
                                        Text(presence.text.text).font(.system(size: 11)).foregroundStyle(.secondary)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                Text(Format.bytes(app.typical, decimal: true)).font(.system(size: 12.5, weight: .semibold)).monospacedDigit()
                                    .frame(width: 90, alignment: .trailing)
                                Text(Format.bytes(app.peak, decimal: true)).font(.system(size: 12)).monospacedDigit().foregroundStyle(.secondary)
                                    .frame(width: 90, alignment: .trailing)
                            }
                            if total > 0 {
                                // Part de la mémoire du Mac : foncé en général, clair jusqu'au maximum.
                                GeometryReader { geometry in
                                    ZStack(alignment: .leading) {
                                        Capsule().fill(Color.primary.opacity(0.06))
                                        Capsule().fill(VigieTheme.accent.opacity(0.3)).frame(width: geometry.size.width * min(1, Double(app.peak) / total))
                                        Capsule().fill(VigieTheme.accent).frame(width: geometry.size.width * min(1, Double(app.typical) / total))
                                    }
                                }
                                .frame(height: 5)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    Text(measured < HistoryInsights.measuresForHabits
                         ? tr("Encore peu de mesures (\(measured)) : Vigie en prend une toutes les 3 heures, les habitudes se précisent au fil des jours. La barre montre la part de la mémoire du Mac.",
                              "Few measurements so far (\(measured)): Vigie takes one every 3 hours, habits get clearer over the days. The bar shows the share of the Mac's memory.")
                         : tr("La barre montre la part de la mémoire du Mac : foncée en général, claire jusqu'au plus haut relevé.",
                              "The bar shows the share of the Mac's memory: dark usually, light up to the highest reading."))
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}
