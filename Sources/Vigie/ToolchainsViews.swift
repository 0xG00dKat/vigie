import AppKit
import SwiftUI
import VigieCore

/// Versions de Node, Python et Ruby, paquets npm globaux et volumes Docker orphelins (mode Développeur).
/// Ce qui peut partir se coche ; le reste dit pourquoi il reste (par défaut, en cours, demandé par un projet).
struct ToolchainsPage: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let entries = model.runtimeEntries
        let reclaimable = entries.filter { model.cleanup(for: $0) != nil }.reduce(UInt64(0)) { $0 + $1.size }
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PageHeader(title: tr("Versions et outils", "Versions and tools"),
                           subtitle: tr("Les versions de Node, Python et Ruby installées au fil des projets, tes paquets npm globaux et les volumes Docker que plus rien n'utilise.",
                                        "The Node, Python and Ruby versions installed over time, your global npm packages and the Docker volumes nothing uses anymore.")) { EmptyView() }
                    .padding(.horizontal, -VigieTheme.pagePadding)
                    .padding(.bottom, -16)
                if model.toolchainsLoaded, !model.runtimeVersions.isEmpty || !model.globalPackages.isEmpty {
                    ToolchainTopTiles(reclaimable: reclaimable)
                }
                if !model.toolchainsLoaded {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(tr("Recherche des versions installées…", "Looking for installed versions…")).foregroundStyle(.secondary)
                    }
                } else {
                    ForEach(RuntimeVersion.Runtime.allCases, id: \.self) { runtime in
                        let versions = model.runtimeVersions.filter { $0.runtime == runtime }
                        if !versions.isEmpty {
                            let rows = versions.map { $0.entry(trashable: model.trashableRuntimePaths.contains($0.path)) }
                            BentoCell { ToolchainSection(title: runtime.title,
                                             subtitle: versions.count > 1
                                                 ? tr("\(versions.count) versions installées. La version par défaut, celle en cours et la dernière de chaque outil restent.",
                                                      "\(versions.count) versions installed. The default one, the one in use and the last one of each tool stay.")
                                                 : tr("Une seule version : rien à alléger.", "A single version: nothing to trim."),
                                             entries: rows) }
                        }
                    }
                    if model.runtimeVersions.isEmpty {
                        EmptyPage(text: tr("Aucune version de Node, Python ou Ruby trouvée (nvm, fnm, volta, pyenv, uv, rbenv, asdf, mise, Homebrew).",
                                           "No Node, Python or Ruby version found (nvm, fnm, volta, pyenv, uv, rbenv, asdf, mise, Homebrew)."))
                    }
                    if !model.globalPackages.isEmpty {
                        BentoCell { ToolchainSection(title: tr("Paquets npm globaux", "Global npm packages"),
                                         subtitle: tr("Installés avec « npm install -g ». Vigie les retire avec le npm qui les a installés.",
                                                      "Installed with “npm install -g”. Vigie removes them with the npm that installed them."),
                                         entries: model.globalPackages.map(\.entry)) }
                    }
                    if !model.orphanVolumes.isEmpty {
                        BentoCell { OrphanVolumesSection(volumes: model.orphanVolumes) }
                    }
                }
            }
            .padding(.horizontal, VigieTheme.pagePadding)
            .padding(.bottom, WindowGrid.pageBottom)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { SelectionBar() }
        .onAppear { model.refreshToolchains() }
        .onDisappear { model.clearSelection() }
    }
}

struct ToolchainSection: View {
    let title: String
    let subtitle: String
    let entries: [StorageEntry]
    /// Dans une case de la fenêtre : pas de marge de page ni de trait sous le titre.
    @Environment(\.flatCards) private var flat

    var body: some View {
        let inset = flat ? 0 : VigieTheme.pagePadding
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title).font(.system(size: flat ? 14 : 13, weight: .semibold))
                Text(Format.bytes(entries.reduce(0) { $0 + $1.size }, decimal: true))
                    .font(.system(size: 12, weight: .medium)).monospacedDigit().foregroundStyle(.secondary)
            }
            .padding(.horizontal, inset)
            Text(subtitle)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, inset)
                .padding(.top, 3)
                .padding(.bottom, 8)
            if !flat { Divider() }
            StorageSectionRows(kind: .appData, entries: entries, largest: max(entries.map(\.size).max() ?? 1, 1))
                .padding(.horizontal, inset - 12)
        }
        .padding(.top, flat ? 0 : 18)
    }
}

/// En haut : combien de versions et de quoi, ce qui s'allège, les restes (npm, volumes Docker).
struct ToolchainTopTiles: View {
    @Environment(AppModel.self) private var model
    let reclaimable: UInt64

    var body: some View {
        let versions = model.runtimeVersions
        let byRuntime = RuntimeVersion.Runtime.allCases.compactMap { runtime -> String? in
            let size = versions.filter { $0.runtime == runtime }.reduce(UInt64(0)) { $0 + $1.size }
            return size > 0 ? "\(runtime.title) \(Format.bytes(size, decimal: true))" : nil
        }
        HStack(alignment: .top, spacing: 16) {
            TopTile(symbol: "hammer", tint: DS.safe,
                    title: tr("\(versions.count) version\(versions.count > 1 ? "s" : "") installée\(versions.count > 1 ? "s" : "")",
                              "\(versions.count) installed version\(versions.count > 1 ? "s" : "")"),
                    text: byRuntime.joined(separator: " · ")) { EmptyView() }
            TopTile(symbol: "checkmark.circle", tint: reclaimable > 0 ? DS.review : DS.safe,
                    title: reclaimable > 0 ? tr("\(Format.bytes(reclaimable, decimal: true)) à alléger", "\(Format.bytes(reclaimable, decimal: true)) to trim")
                                           : tr("Rien à alléger", "Nothing to trim"),
                    text: tr("Les anciennes versions qu'aucun projet ne demande. La version par défaut, celle en cours et la dernière restent toujours.",
                             "Old versions no project asks for. The default one, the one in use and the latest always stay.")) { EmptyView() }
            if !model.orphanVolumes.isEmpty {
                let size = model.orphanVolumes.reduce(UInt64(0)) { $0 + $1.size }
                TopTile(symbol: "externaldrive", tint: DS.review,
                        title: tr("\(model.orphanVolumes.count) volume\(model.orphanVolumes.count > 1 ? "s" : "") Docker orphelin\(model.orphanVolumes.count > 1 ? "s" : "")",
                                  "\(model.orphanVolumes.count) orphan Docker volume\(model.orphanVolumes.count > 1 ? "s" : "")"),
                        text: tr("\(Format.bytes(size, decimal: true)) que plus aucun conteneur n'utilise. À vérifier : Vigie n'en supprime jamais.",
                                 "\(Format.bytes(size, decimal: true)) no container uses anymore. Review them: Vigie never deletes one.")) { EmptyView() }
            } else {
                TopTile(symbol: "shippingbox", tint: DS.safe,
                        title: tr("\(model.globalPackages.count) paquet\(model.globalPackages.count > 1 ? "s" : "") npm globa\(model.globalPackages.count > 1 ? "ux" : "l")",
                                  "\(model.globalPackages.count) global npm package\(model.globalPackages.count > 1 ? "s" : "")"),
                        text: tr("Installés avec « npm install -g », à retirer si tu ne t'en sers plus.", "Installed with “npm install -g”, remove them if you no longer use them.")) { EmptyView() }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// Volumes Docker sans conteneur. Vigie n'en supprime jamais : un volume peut garder la base de données d'un projet.
struct OrphanVolumesSection: View {
    let volumes: [DockerVolume]
    @State private var copied: String?

    @Environment(\.flatCards) private var flat

    var body: some View {
        let inset = flat ? 0 : VigieTheme.pagePadding
        if !volumes.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(tr("Volumes Docker orphelins", "Orphan Docker volumes")).font(.system(size: flat ? 14 : 13, weight: .semibold))
                    Chip(text: Format.bytes(volumes.reduce(0) { $0 + $1.size }, decimal: true), tint: .secondary)
                }
                .padding(.horizontal, inset)
                Text(tr("Aucun conteneur, même arrêté, ne les utilise. Un volume peut garder la base de données d'un projet : Vigie n'en supprime jamais. Copie la commande si tu es sûr.",
                        "No container, even stopped, uses them. A volume can hold a project's database: Vigie never deletes one. Copy the command if you're sure."))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, inset)
                    .padding(.top, 3)
                    .padding(.bottom, 8)
                Divider()
                ForEach(volumes) { volume in
                    HStack(spacing: 10) {
                        Image(systemName: "externaldrive").foregroundStyle(.secondary).frame(width: 20)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(volume.isAnonymous ? tr("Volume anonyme", "Anonymous volume") : volume.name)
                                .font(.system(size: 12.5, weight: .medium))
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Text(volume.isAnonymous
                                 ? tr("Créé sans nom par un conteneur disparu : presque toujours un reste.", "Created without a name by a container that's gone: almost always a leftover.")
                                 : volume.project.map { tr("Données du projet Compose « \($0) ».", "Data of the Compose project “\($0)”.") } ?? tr("Volume nommé.", "Named volume."))
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(Format.bytes(volume.size, decimal: true)).font(.system(size: 11.5, weight: .medium)).monospacedDigit().foregroundStyle(.secondary)
                        Button(copied == volume.name ? tr("Copié", "Copied") : tr("Copier la commande", "Copy command")) {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(volume.removeCommand, forType: .string)
                            copied = volume.name
                        }
                        .buttonStyle(.borderless)
                        .font(.system(size: 11))
                        .help(volume.removeCommand)
                    }
                    .padding(.horizontal, inset)
                    .padding(.vertical, 7)
                    Divider().padding(.leading, inset + 30)
                }
            }
            .padding(.top, 18)
        }
    }
}
