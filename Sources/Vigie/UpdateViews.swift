import SwiftUI
import VigieCore

/// Menu ⚙︎ de l'en-tête : langue, mises à jour et numéro de version.
struct SettingsMenu: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        let language = Binding(
            get: { model.languageSetting },
            set: { model.setLanguage($0) }
        )
        Menu {
            Picker(tr("Langue", "Language"), selection: language) {
                ForEach(LanguageSetting.allCases) { setting in
                    Text(setting.label).tag(setting)
                }
            }
            .pickerStyle(.inline)

            Divider()

            Button(tr("Rechercher une mise à jour", "Check for updates")) {
                model.checkForUpdates(manual: true)
            }
            .disabled(model.update == .checking)
            Toggle(tr("Vérifier chaque jour", "Check every day"), isOn: $model.autoCheckUpdates)

            Divider()

            Text(versionLine)
        } label: {
            Image(systemName: "gearshape")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(tr("Réglages : langue et mises à jour", "Settings: language and updates"))
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
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private func available(_ release: ReleaseInfo) -> some View {
        let current = model.currentVersion?.description ?? "?"
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "arrow.down.circle.fill")
                    .foregroundStyle(Color.accentColor)
                    .font(.system(size: 15))
                VStack(alignment: .leading, spacing: 2) {
                    Text(tr(
                        "Vigie \(release.version) est disponible (tu as la \(current)).",
                        "Vigie \(release.version) is available (you have \(current))."
                    ))
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
                .buttonStyle(PrimaryButtonStyle())
                Button(tr("Nouveautés", "What's new")) {
                    model.open(release.pageURL)
                }
                .buttonStyle(.borderless)
                Spacer(minLength: 0)
                Button(tr("Ignorer cette version", "Skip this version")) {
                    model.ignore(release)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
            }
            .controlSize(.small)
            .font(.system(size: 11))
            Text(tr(
                "Remplace ensuite Vigie dans Applications. Compilée toi-même ? git pull puis ./scripts/build-app.sh.",
                "Then replace Vigie in Applications. Built it yourself? git pull, then ./scripts/build-app.sh."
            ))
            .font(.system(size: 10))
            .foregroundStyle(.tertiary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.accentColor.opacity(0.10)))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.accentColor.opacity(0.35)))
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
                    .fill(Color.accentColor.opacity(configuration.isPressed ? 0.75 : 1))
            )
            .contentShape(Rectangle())
    }
}
