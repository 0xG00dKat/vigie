import AppKit
import SwiftUI
import VigieCore

// Bilan : l'œil en haut de la colonne d'icônes lance toutes les analyses de Vigie, puis dit, du plus gros gain au plus
// petit, ce qu'on peut faire pour alléger le Mac. Chaque conseil a un bouton et un lien vers son explication.

/// Un conseil du bilan.
struct CheckupAdvice: Identifiable {
    enum Action {
        case cleanSafe
        case open(WindowPage)
        case openUnusedLargeFiles
        case openDuplicates
        case health(MacHealth)
        case openTrash
    }
    let id: String
    let symbol: String
    let level: DSLevel
    let title: String
    let detail: String
    /// Place récupérable (octets), pour trier et pour le total.
    var space: UInt64 = 0
    let button: String
    let action: Action
    var lesson: String?
}

enum CheckupBuilder {
    @MainActor
    static func advices(_ model: AppModel) -> [CheckupAdvice] {
        var result: [CheckupAdvice] = []
        let report = model.storage
        func size(_ entries: [StorageEntry]) -> UInt64 { entries.reduce(0) { $0 + $1.size } }

        // Vitesse : une app qui s'emballe, la mémoire qui manque, la chaleur.
        if let speed = model.speedHealth, speed.level != .good, speed.action != nil {
            result.append(CheckupAdvice(id: "speed", symbol: "gauge.with.needle", level: speed.level == .critical ? .urgent : .review,
                                        title: speed.title, detail: speed.message,
                                        button: SpeedStateTile.shortTitle(speed) ?? tr("Voir", "See"), action: .health(speed), lesson: "memoire"))
        }
        // Caches qui se recréent tout seuls.
        let safe = size(model.safeCleanItems)
        if safe >= 200_000_000 {
            result.append(CheckupAdvice(id: "caches", symbol: "arrow.triangle.2.circlepath", level: .safe,
                                        title: tr("Vider les caches : \(Format.bytes(safe, decimal: true))", "Clear caches: \(Format.bytes(safe, decimal: true))"),
                                        detail: tr("Des copies que les apps et les outils recréent quand il le faut. Rien de perdu.",
                                                   "Copies that apps and tools rebuild when needed. Nothing lost."),
                                        space: safe, button: tr("Nettoyer", "Clean"), action: .cleanSafe, lesson: "caches"))
        }
        // Projets endormis : leurs dépendances se réinstallent.
        let dormant = size(model.dormantProjects)
        if dormant >= 200_000_000 {
            result.append(CheckupAdvice(id: "dormant", symbol: "moon.zzz", level: .safe,
                                        title: tr("\(model.dormantProjects.count) projet\(model.dormantProjects.count > 1 ? "s" : "") endormi\(model.dormantProjects.count > 1 ? "s" : "") : \(Format.bytes(dormant, decimal: true))",
                                                  "\(model.dormantProjects.count) dormant project\(model.dormantProjects.count > 1 ? "s" : ""): \(Format.bytes(dormant, decimal: true))"),
                                        detail: tr("Pas touchés depuis six mois : leurs dépendances se réinstallent au besoin, ton code reste.",
                                                   "Untouched for six months: their dependencies reinstall when needed, your code stays."),
                                        space: dormant, button: tr("Voir", "See"), action: .open(.storage(.project)), lesson: "disque-se-remplit"))
        }
        if let report {
            // Gros fichiers qu'on n'ouvre plus.
            let unused = LargeFileFilter(unusedOnly: true).apply(report.entries(of: .largeFile))
            let unusedSize = size(unused)
            if unusedSize >= 500_000_000 {
                result.append(CheckupAdvice(id: "large", symbol: "doc", level: .review,
                                            title: tr("\(unused.count) gros fichier\(unused.count > 1 ? "s" : "") pas ouvert\(unused.count > 1 ? "s" : "") depuis 6 mois : \(Format.bytes(unusedSize, decimal: true))",
                                                      "\(unused.count) large file\(unused.count > 1 ? "s" : "") not opened in 6 months: \(Format.bytes(unusedSize, decimal: true))"),
                                            detail: tr("Souvent des installeurs, des vidéos exportées ou des archives. À regarder un par un.",
                                                       "Often installers, exported videos or archives. Look at each one."),
                                            space: unusedSize, button: tr("Voir", "See"), action: .openUnusedLargeFiles, lesson: "disque-se-remplit"))
            }
            // Restes d'apps supprimées.
            let leftovers = report.entries(of: .leftover)
            if size(leftovers) >= 200_000_000 {
                result.append(CheckupAdvice(id: "leftovers", symbol: "shippingbox.and.arrow.backward", level: .review,
                                            title: tr("Restes d'apps supprimées : \(Format.bytes(size(leftovers), decimal: true))", "Leftovers from deleted apps: \(Format.bytes(size(leftovers), decimal: true))"),
                                            detail: tr("Des réglages et des données d'apps qui ne sont plus sur ton Mac.", "Settings and data from apps no longer on your Mac."),
                                            space: size(leftovers), button: tr("Voir", "See"), action: .open(.storage(.leftover)), lesson: "disque-se-remplit"))
            }
        }
        // Doublons.
        if case .done(let groups, _) = model.duplicateSearch {
            let freed = groups.reduce(UInt64(0)) { $0 + $1.freed() }
            if freed >= 100_000_000 {
                result.append(CheckupAdvice(id: "duplicates", symbol: "doc.on.doc", level: .review,
                                            title: tr("Fichiers en double : \(Format.bytes(freed, decimal: true))", "Duplicate files: \(Format.bytes(freed, decimal: true))"),
                                            detail: tr("\(groups.count) fichier\(groups.count > 1 ? "s" : "") en plusieurs exemplaires identiques. Tu choisis la copie à garder.",
                                                       "\(groups.count) file\(groups.count > 1 ? "s" : "") with identical copies. You pick the copy to keep."),
                                            space: freed, button: tr("Voir", "See"), action: .openDuplicates))
            }
        }
        if model.isDeveloper {
            // Anciennes versions de Node, Python…
            let trimmable = model.runtimeEntries.filter { model.cleanup(for: $0) != nil }
            if size(trimmable) >= 200_000_000 {
                result.append(CheckupAdvice(id: "toolchains", symbol: "hammer", level: .review,
                                            title: tr("Anciennes versions d'outils : \(Format.bytes(size(trimmable), decimal: true))", "Old tool versions: \(Format.bytes(size(trimmable), decimal: true))"),
                                            detail: tr("Des versions de Node, Python ou Ruby qu'aucun projet ne demande.", "Node, Python or Ruby versions no project asks for."),
                                            space: size(trimmable), button: tr("Voir", "See"), action: .open(.toolchains)))
            }
            // Docker.
            if let usage = model.docker?.disk {
                let reclaimable = usage.buildCache.reclaimable + usage.images.reclaimable
                if reclaimable >= 1_000_000_000 {
                    result.append(CheckupAdvice(id: "docker", symbol: "shippingbox", level: .review,
                                                title: tr("Docker : \(Format.bytes(reclaimable, decimal: true)) récupérables", "Docker: \(Format.bytes(reclaimable, decimal: true)) reclaimable"),
                                                detail: tr("Cache de construction et images inutilisées. Tes volumes ne sont jamais comptés.", "Build cache and unused images. Your volumes are never counted."),
                                                space: reclaimable, button: tr("Voir", "See"), action: .open(.docker)))
                }
            }
            // Serveur visible sur le Wi-Fi.
            let exposed = model.visibleGroups(in: .dev).filter { !$0.exposedPorts.isEmpty }
            if !exposed.isEmpty {
                result.append(CheckupAdvice(id: "ports", symbol: "wifi", level: .review,
                                            title: tr("\(exposed.map(\.title).joined(separator: ", ")) visible sur le Wi-Fi", "\(exposed.map(\.title).joined(separator: ", ")) visible on the Wi-Fi"),
                                            detail: PortMap.exposedAdvice.text,
                                            button: tr("Voir", "See"), action: .open(.ports), lesson: "ports"))
            }
        }
        // Ce qui démarre avec le Mac.
        let running = model.startupItems.filter { $0.isEnabled && $0.canToggle }
        if running.count >= 3 {
            result.append(CheckupAdvice(id: "startup", symbol: "power", level: .keep,
                                        title: tr("\(running.count) programmes à toi se lancent au démarrage", "\(running.count) of your programs start at login"),
                                        detail: tr("Chacun prend un peu de mémoire en permanence. Coupe ceux dont tu ne te sers pas.",
                                                   "Each one keeps using a bit of memory. Turn off the ones you don't use."),
                                        button: tr("Voir", "See"), action: .open(.speed), lesson: "demarrage"))
        }
        // La corbeille : la place ne revient qu'en la vidant.
        if model.trashedByVigie >= 500_000_000 {
            result.append(CheckupAdvice(id: "trash", symbol: "trash", level: .safe,
                                        title: tr("\(Format.bytes(model.trashedByVigie, decimal: true)) dans la corbeille", "\(Format.bytes(model.trashedByVigie, decimal: true)) in the Trash"),
                                        detail: tr("Mis à la corbeille par Vigie : la place ne revient qu'une fois la corbeille vidée.",
                                                   "Moved to the Trash by Vigie: the space only comes back once you empty it."),
                                        space: model.trashedByVigie, button: tr("Ouvrir", "Open"), action: .openTrash, lesson: "corbeille"))
        }
        // L'urgent d'abord, puis le plus gros gain.
        return result.sorted { a, b in
            let rank = { (level: DSLevel) in level == .urgent ? 0 : 1 }
            if rank(a.level) != rank(b.level) { return rank(a.level) < rank(b.level) }
            return a.space > b.space
        }
    }
}

struct CheckupPage: View {
    @Environment(AppModel.self) private var model
    @Binding var page: WindowPage?

    var body: some View {
        let advices = CheckupBuilder.advices(model)
        let space = advices.reduce(UInt64(0)) { $0 + $1.space }
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PageHeader(title: tr("Bilan de mon Mac", "My Mac's checkup"),
                           subtitle: tr("Vigie regarde tout (ce qui tourne, le disque, tes projets, ce qui démarre) et te dit comment l'alléger, du plus utile au moins utile.",
                                        "Vigie looks at everything (what runs, the disk, your projects, what starts up) and tells you how to lighten it, most useful first.")) {
                    Button {
                        model.runCheckup()
                    } label: {
                        Label(tr("Refaire le bilan", "Run again"), systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(HUDPillButtonStyle())
                    .disabled(model.checkupRunning)
                }
                .padding(.horizontal, -VigieTheme.pagePadding)
                .padding(.bottom, -16)

                HStack(alignment: .top, spacing: 16) {
                    TopTile(symbol: "checkmark.circle", tint: space > 0 ? DS.safe : DS.keep,
                            title: space > 0 ? tr("Jusqu'à \(Format.bytes(space, decimal: true)) à récupérer", "Up to \(Format.bytes(space, decimal: true)) to get back")
                                             : tr("Rien de gros à récupérer", "Nothing big to get back"),
                            text: tr("En suivant les conseils ci-dessous. Vigie ne fait rien sans ta confirmation.",
                                     "By following the advice below. Vigie does nothing without your confirmation.")) { EmptyView() }
                    if let health = model.speedHealth {
                        TopTile(symbol: "gauge.with.needle", tint: health.level == .critical ? DS.urgent : health.level == .attention ? DS.review : DS.safe,
                                title: health.title, text: health.message, lesson: "memoire") { EmptyView() }
                    }
                    CheckupProgressTile()
                }
                .fixedSize(horizontal: false, vertical: true)

                if advices.isEmpty {
                    HStack(spacing: 10) {
                        Image(systemName: model.checkupRunning ? "hourglass" : "checkmark.circle.fill")
                            .foregroundStyle(model.checkupRunning ? DS.secondaryText : DS.safe)
                        Text(model.checkupRunning ? tr("Vigie regarde ton Mac…", "Vigie is looking at your Mac…")
                                                  : tr("Rien à faire : ton Mac est déjà léger.", "Nothing to do: your Mac is already light."))
                            .font(.system(size: 13.5, weight: .medium))
                        Spacer()
                    }
                    .padding(18)
                    .panelSurface()
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(advices.enumerated()), id: \.element.id) { index, advice in
                            if index > 0 { Divider().padding(.leading, 58) }
                            CheckupAdviceRow(advice: advice, page: $page)
                        }
                    }
                    .panelSurface()
                }
            }
            .padding(.horizontal, VigieTheme.pagePadding)
            .padding(.bottom, WindowGrid.pageBottom)
        }
        .onChange(of: model.storage?.date) { model.refreshDormantProjects() }
        .animation(VigieMotion.standard, value: advices.map(\.id))
    }
}

/// Où en est le bilan : chaque analyse, en cours ou faite.
struct CheckupProgressTile: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let steps = model.checkupSteps
        let done = steps.filter(\.done).count
        TopTile(symbol: "checklist", tint: done == steps.count ? DS.safe : DS.keep,
                title: done == steps.count ? tr("Tout est analysé", "Everything analyzed") : tr("Analyse en cours… \(done)/\(steps.count)", "Analyzing… \(done)/\(steps.count)"),
                text: steps.filter { !$0.done }.map(\.title).joined(separator: " · ").ifEmpty(tr("Processus, disque, projets, outils, démarrage, doublons.", "Processes, disk, projects, tools, startup, duplicates."))) {
            if done < steps.count {
                ProgressView(value: Double(done), total: Double(max(steps.count, 1))).tint(VigieTheme.accent)
            }
        }
    }
}

private extension String {
    func ifEmpty(_ fallback: String) -> String { isEmpty ? fallback : self }
}

struct CheckupAdviceRow: View {
    @Environment(AppModel.self) private var model
    let advice: CheckupAdvice
    @Binding var page: WindowPage?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                VigieTile(symbol: advice.symbol, size: 30)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Circle().fill(advice.level.color).frame(width: 7, height: 7)
                        Text(advice.title).font(.system(size: 13.5, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
                    }
                    Text(advice.detail).font(.system(size: 12)).foregroundStyle(DS.secondaryText).fixedSize(horizontal: false, vertical: true)
                    if let lesson = advice.lesson {
                        Button {
                            withAnimation(VigieMotion.standard) { page = .lesson(lesson) }
                        } label: {
                            Label(tr("Pourquoi ?", "Why?"), systemImage: "lightbulb")
                        }
                        .buttonStyle(.borderless)
                        .font(.system(size: 11.5, weight: .medium))
                        .padding(.top, 2)
                    }
                }
                Spacer(minLength: 12)
                button
            }
            if case .cleanSafe = advice.action, model.safeClean != nil {
                SafeCleanArea(showsButton: false).padding(.leading, 42)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    @ViewBuilder
    private var button: some View {
        switch advice.action {
        case .cleanSafe:
            if model.safeClean == nil {
                Button(advice.button) { model.reviewSafeClean() }.buttonStyle(HUDPillButtonStyle(prominent: true))
            }
        case .health(let health):
            if case .quit(let id, let name)? = health.action {
                ConfirmPill(key: id, title: advice.button, confirm: tr("Quitter \(name) ?", "Quit \(name)?")) {
                    model.performHealthAction(fromPanel: false, health: health)
                }
            } else {
                Button(advice.button) { model.performHealthAction(fromPanel: false, health: health) }
                    .buttonStyle(HUDPillButtonStyle(prominent: true))
            }
        case .open(let target):
            Button(advice.button) { withAnimation(VigieMotion.standard) { page = target } }
                .buttonStyle(HUDPillButtonStyle())
        case .openUnusedLargeFiles:
            Button(advice.button) {
                model.largeFilesTab = .files
                model.largeFileFilter = LargeFileFilter(unusedOnly: true)
                withAnimation(VigieMotion.standard) { page = .storage(.largeFile) }
            }
            .buttonStyle(HUDPillButtonStyle())
        case .openDuplicates:
            Button(advice.button) {
                model.largeFilesTab = .duplicates
                withAnimation(VigieMotion.standard) { page = .storage(.largeFile) }
            }
            .buttonStyle(HUDPillButtonStyle())
        case .openTrash:
            Button(advice.button) { model.openTrash() }.buttonStyle(HUDPillButtonStyle())
        }
    }
}
