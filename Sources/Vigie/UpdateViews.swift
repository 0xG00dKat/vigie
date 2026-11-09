import SwiftUI
import VigieCore

/// Menu ⚙︎ du panneau : la fenêtre, les Réglages (dans la fenêtre), les mises à jour, le Moniteur d'activité et Quitter.
struct SettingsMenu: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    /// Dans le panneau : un bouton rond, et ce qui était en bas du panneau (Moniteur d'activité, démarrage, Quitter).
    var round = false
    /// Dans le panneau de la barre des menus : ouvrir la fenêtre le referme.
    var inPanel = false
    /// Sans fond (l'en-tête du panneau en verre).
    var plain = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Menu {
            // Un menu court : tous les réglages sont dans la fenêtre (Réglages).
            if inPanel {
                // Depuis le panneau : il se referme quand la fenêtre s'ouvre.
                Button(tr("Ouvrir dans une fenêtre", "Open in a window")) { DockPresence.openFromPanel(dismiss) }
                Button(tr("Réglages…", "Settings…")) {
                    model.windowPageRequest = .settings
                    DockPresence.openFromPanel(dismiss)
                }
            } else {
                OpenWindowButton()
                Button(tr("Réglages…", "Settings…")) {
                    model.windowPageRequest = .settings
                    openWindow(id: VigieWindow.id)
                    NSApp.activate()
                }
            }
            Button(tr("Rechercher une mise à jour", "Check for updates")) {
                model.checkForUpdates(manual: true)
            }
            .disabled(model.update == .checking)
            Divider()
            Button(tr("Ouvrir le Moniteur d'activité", "Open Activity Monitor")) { model.openActivityMonitor() }
            Divider()

            Text(versionLine)
            Button(tr("Quitter Vigie", "Quit Vigie")) { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        } label: {
            if plain {
                Image(systemName: "gearshape")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(DS.secondaryText)
                    .frame(width: 26, height: 26)
            } else if round {
                Image(systemName: "gearshape")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(DS.secondaryText)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(DS.well))
            } else {
                Image(systemName: "gearshape")
            }
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(tr("Réglages, fenêtre et Quitter", "Settings, window and Quit"))
    }

    private var versionLine: String {
        let version = model.currentVersion?.description ?? "?"
        return tr("Vigie \(version)", "Vigie \(version)")
    }
}

/// Bandeau en tête de liste : nouvelle version, ou résultat d'une recherche lancée à la main.
struct UpdateBanner: View {
    @Environment(AppModel.self) private var model
    let state: UpdateState

    var body: some View {
        switch state {
        case .checking:
            message(icon: "arrow.triangle.2.circlepath", color: .secondary,
                    title: tr("Recherche d'une mise à jour…", "Checking for updates…"), detail: nil, closable: false)
        case .upToDate(let latest):
            let current = model.currentVersion?.description ?? "?"
            message(
                icon: "checkmark.circle.fill", color: .green,
                title: tr("Vigie est à jour (\(current)).", "Vigie is up to date (\(current))."),
                detail: latest == nil ? tr("Aucune version n'est encore publiée sur GitHub.", "No version has been published on GitHub yet.") : nil,
                closable: true
            )
        case .failed(let reason):
            message(icon: "exclamationmark.triangle.fill", color: .orange,
                    title: tr("Impossible de vérifier les mises à jour.", "Couldn't check for updates."), detail: reason, closable: true)
        case .available(let release):
            available(release)
        case .idle:
            EmptyView()
        }
    }

    private func message(icon: String, color: Color, title: String, detail: String?, closable: Bool) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(color)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 11.5, weight: .medium))
                if let detail {
                    Text(detail)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            if closable {
                Button {
                    model.dismissUpdateMessage()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
                .help(tr("Fermer", "Close"))
            }
        }
        .padding(12)
        .panelSurface()
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private func available(_ release: ReleaseInfo) -> some View {
        let current = model.currentVersion?.description ?? "?"
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "arrow.down.circle.fill")
                    .foregroundStyle(VigieTheme.accent)
                    .font(.system(size: 15))
                VStack(alignment: .leading, spacing: 2) {
                    Text(current == "?"
                         ? tr("Vigie \(release.version) est disponible.", "Vigie \(release.version) is available.")
                         : tr("Vigie \(release.version) est disponible (tu as la \(current)).",
                              "Vigie \(release.version) is available (you have \(current))."))
                    .font(.system(size: 12, weight: .semibold))
                    if !release.summary.isEmpty {
                        Text(release.summary)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 10) {
                Button(tr("Télécharger", "Download")) {
                    model.open(release.downloadURL ?? release.pageURL)
                }
                .buttonStyle(HUDPillButtonStyle(prominent: true))
                Button(tr("Nouveautés", "What's new")) {
                    model.open(release.pageURL)
                }
                .buttonStyle(HUDPillButtonStyle())
                Spacer(minLength: 0)
                Button(tr("Ignorer cette version", "Skip this version")) {
                    model.ignore(release)
                }
                .buttonStyle(.plain)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(DS.secondaryText)
            }
            .padding(.top, 2)
            Text(tr(
                "Remplace ensuite Vigie dans Applications. Compilée toi-même ? git pull puis ./scripts/build-app.sh.",
                "Then replace Vigie in Applications. Built it yourself? git pull, then ./scripts/build-app.sh."
            ))
            .font(.system(size: 10))
            .foregroundStyle(.tertiary)
            .fixedSize(horizontal: false, vertical: true)
        }
        // Une carte de verre, comme le reste de la fenêtre.
        .padding(WindowGrid.cardPadding)
        .panelSurface()
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}

/// Bouton principal bleu, bleu même quand la fenêtre n'a pas le focus.
struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(VigieTheme.accent.opacity(configuration.isPressed ? 0.75 : 1))
            )
            .contentShape(Rectangle())
    }
}
