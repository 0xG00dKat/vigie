import AppKit
import SwiftUI
import VigieCore

/// Réglages de l'ouverture (lus aussi par `LogoIntroGate`, hors de la vue).
enum IntroSettings {
    static let animationKey = "animationOuverture"
    static let soundKey = "sonOuverture"
    static var animation: Bool { UserDefaults.standard.object(forKey: animationKey) as? Bool ?? true }
    static var sound: Bool { UserDefaults.standard.object(forKey: soundKey) as? Bool ?? true }
}

/// Les Réglages, sur une seule page : une colonne centrée, les sections les unes sous les autres.
struct SettingsPage: View {
    @Environment(AppModel.self) private var model
    @Binding var page: WindowPage?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: WindowGrid.gap) {
                PageHeader(title: tr("Réglages", "Settings"),
                           subtitle: tr("Comment Vigie se comporte sur ton Mac.", "How Vigie behaves on your Mac.")) { EmptyView() }
                    .padding(.horizontal, -VigieTheme.pagePadding)
                    .padding(.bottom, -WindowGrid.gap)
                AppearanceSettings()
                GeneralSettings()
                AlertSettings(page: $page)
                OpeningSettings()
                LearnSettings()
                UpdateSettings()
                AboutSettings()
            }
            // Une colonne de lecture, centrée dans la page.
            .frame(maxWidth: 720, alignment: .leading)
            .padding(.horizontal, VigieTheme.pagePadding)
            .padding(.bottom, WindowGrid.pageBottom)
            .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - Briques

/// Une section : son titre en capitales, puis une carte de lignes séparées par un trait.
struct SettingsGroup<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LearnSectionTitle(title)
            VStack(alignment: .leading, spacing: 0) { content }
                .frame(maxWidth: .infinity, alignment: .leading)
                .panelSurface()
        }
    }
}

/// Une ligne : le titre et une phrase d'explication à gauche, le réglage à droite.
struct SettingsRow<Control: View>: View {
    let title: String
    var detail: String? = nil
    var divider = true
    @ViewBuilder var control: Control

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: WindowGrid.gap) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.system(size: 13.5, weight: .semibold))
                    if let detail {
                        Text(detail)
                            .font(.system(size: 12))
                            .foregroundStyle(DS.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: WindowGrid.gap)
                control
            }
            .padding(.horizontal, WindowGrid.cardPadding)
            .padding(.vertical, 14)
            if divider {
                Divider().padding(.leading, WindowGrid.cardPadding)
            }
        }
    }
}

/// Interrupteur des Réglages : à droite, vert d'eau.
struct SettingsSwitch: View {
    @Binding var isOn: Bool

    var body: some View {
        Toggle("", isOn: $isOn)
            .toggleStyle(.switch)
            .labelsHidden()
            .tint(VigieTheme.accent)
            .controlSize(.regular)
    }
}

// MARK: - Rubriques

private struct GeneralSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let language = Binding(get: { model.languageSetting }, set: { model.setLanguage($0) })
        let experience = Binding(get: { model.experience }, set: { model.setExperience($0) })
        SettingsGroup(title: tr("Langue", "Language")) {
            SettingsRow(title: tr("Langue de l'app", "App language"),
                        detail: tr("Automatique suit la langue de macOS.", "Automatic follows macOS's language."), divider: false) {
                Picker("", selection: language) {
                    ForEach(LanguageSetting.allCases) { Text($0.label).tag($0) }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
            }
        }
        SettingsGroup(title: tr("Mode", "Mode")) {
            SettingsRow(title: tr("Ce que Vigie montre", "What Vigie shows"),
                        detail: tr("Simple : l'essentiel, en mots simples. Développeur : en plus les projets, les ports, Docker et les commandes.",
                                   "Simple: the essentials, in plain words. Developer: also projects, ports, Docker and commands."), divider: false) {
                Picker("", selection: experience) {
                    Text(tr("Simple", "Simple")).tag(ExperienceMode.simple)
                    Text(tr("Développeur", "Developer")).tag(ExperienceMode.developer)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .fixedSize()
            }
        }
        SettingsGroup(title: tr("Démarrage et Dock", "Startup and Dock")) {
            SettingsRow(title: tr("Ouvrir Vigie au démarrage", "Open Vigie at login"),
                        detail: tr("Vigie se lance avec ta session, dans la barre des menus.", "Vigie starts with your session, in the menu bar.")) {
                SettingsSwitch(isOn: Binding(get: { model.loginItemState != .disabled }, set: { model.setLaunchAtLogin($0) }))
            }
            SettingsRow(title: tr("Toujours dans le Dock", "Always in the Dock"),
                        detail: tr("Sinon, Vigie n'apparaît dans le Dock que pendant que sa fenêtre est ouverte.",
                                   "Otherwise, Vigie only shows in the Dock while its window is open.")) {
                DockSwitch()
            }
            SettingsRow(title: tr("Écrans d'accueil", "Welcome screens"),
                        detail: tr("Revoir les trois écrans du premier lancement.", "See the three first-launch screens again."), divider: false) {
                Button(tr("Revoir", "Show")) { OnboardingWindow.show(model: model) }
                    .buttonStyle(HUDPillButtonStyle())
            }
        }
    }
}

/// « Toujours dans le Dock » est rangé hors du modèle : l'interrupteur garde son propre état.
private struct DockSwitch: View {
    @State private var on = DockPresence.alwaysInDock

    var body: some View {
        SettingsSwitch(isOn: $on)
            .onChange(of: on) { DockPresence.alwaysInDock = on }
    }
}

private struct AlertSettings: View {
    @Environment(AppModel.self) private var model
    @Binding var page: WindowPage?

    var body: some View {
        @Bindable var model = model
        SettingsGroup(title: tr("Alertes", "Alerts")) {
            SettingsRow(title: tr("Me prévenir si le Mac ralentit", "Warn me when the Mac slows down"),
                        detail: tr("Une notification si une app fait travailler ton Mac depuis 5 min, si la mémoire manque, s'il chauffe ou si une app l'empêche de dormir. Au plus une fois par heure.",
                                   "A notification if an app has kept your Mac busy for 5 min, if memory runs short, if it gets hot or if an app keeps it awake. At most once an hour.")) {
                SettingsSwitch(isOn: $model.speedAlertsEnabled)
            }
            SettingsRow(title: tr("Disque presque plein", "Disk almost full"),
                        detail: tr("Sous 15 % d'espace libre : le pourcentage à côté de l'œil dans la barre des menus, un bandeau et une notification.",
                                   "Below 15% free space: the percentage next to the eye in the menu bar, a banner and a notification."), divider: false) {
                Text(tr("Toujours actif", "Always on"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(DS.tertiaryText)
            }
        }
        SettingsGroup(title: tr("Règles", "Rules")) {
            SettingsRow(title: tr("Tes règles", "Your rules"),
                        detail: model.rules.isEmpty
                            ? tr("Aucune règle pour l'instant. Par exemple : « préviens-moi si Slack dépasse 4 Go ».", "No rules yet. For example: “warn me if Slack goes over 4 GB”.")
                            : tr("\(model.rules.count) règle(s) active(s).", "\(model.rules.count) active rule(s)."),
                        divider: false) {
                Button(tr("Ouvrir", "Open")) { withAnimation(VigieMotion.standard) { page = .rules } }
                    .buttonStyle(HUDPillButtonStyle())
            }
        }
    }
}

private struct OpeningSettings: View {
    @Environment(AppModel.self) private var model
    @AppStorage(IntroSettings.animationKey) private var animation = true
    @AppStorage(IntroSettings.soundKey) private var sound = true

    var body: some View {
        SettingsGroup(title: tr("Ouverture", "Opening")) {
            SettingsRow(title: tr("Animation à l'ouverture", "Opening animation"),
                        detail: tr("L'œil s'assemble à la première ouverture de la fenêtre, une fois par lancement. Jamais si « Réduire les animations » est activé dans macOS.",
                                   "The eye assembles the first time the window opens, once per launch. Never if “Reduce motion” is on in macOS.")) {
                SettingsSwitch(isOn: $animation)
            }
            SettingsRow(title: tr("Son à l'ouverture", "Opening sound"),
                        detail: tr("Un petit son pendant l'animation, seulement si les effets sonores de l'interface sont activés dans macOS.",
                                   "A short sound during the animation, only if interface sound effects are on in macOS.")) {
                SettingsSwitch(isOn: $sound)
                    .disabled(!animation)
            }
            SettingsRow(title: tr("Aperçu", "Preview"),
                        detail: tr("Rejouer l'animation maintenant, avec le son s'il est activé.", "Replay the animation now, with the sound if it's on."),
                        divider: false) {
                Button(tr("Voir", "Play")) { model.introReplay = Date() }
                    .buttonStyle(HUDPillButtonStyle())
            }
        }
    }
}

private struct LearnSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let total = Lessons.visible(developer: model.isDeveloper).count
        let read = Lessons.visible(developer: model.isDeveloper).filter { model.readLessons.contains($0.id) }.count
        SettingsGroup(title: tr("Comprendre mon Mac", "Understand my Mac")) {
            SettingsRow(title: tr("Explications lues", "Explanations read"),
                        detail: tr("\(read) sur \(total) cochées. Tout décocher les fait réapparaître comme nouvelles.",
                                   "\(read) of \(total) ticked. Unticking them all shows them as new again."), divider: false) {
                Button(tr("Tout décocher", "Untick all")) { model.resetReadLessons() }
                    .buttonStyle(HUDPillButtonStyle())
                    .disabled(read == 0)
            }
        }
    }
}

private struct UpdateSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        SettingsGroup(title: tr("Mises à jour", "Updates")) {
            SettingsRow(title: tr("Vigie \(model.currentVersion?.description ?? "?")", "Vigie \(model.currentVersion?.description ?? "?")"),
                        detail: status) {
                if case .available(let release) = model.update {
                    Button(tr("Télécharger", "Download")) { NSWorkspace.shared.open(release.downloadURL ?? release.pageURL) }
                        .buttonStyle(HUDPillButtonStyle(prominent: true))
                } else {
                    Button(tr("Rechercher", "Check")) { model.checkForUpdates(manual: true) }
                        .buttonStyle(HUDPillButtonStyle())
                        .disabled(model.update == .checking)
                }
            }
            SettingsRow(title: tr("Vérifier chaque jour", "Check every day"),
                        detail: tr("Une fois par jour, Vigie regarde sur GitHub s'il existe une nouvelle version.",
                                   "Once a day, Vigie checks GitHub for a new version."), divider: false) {
                SettingsSwitch(isOn: $model.autoCheckUpdates)
            }
        }
    }

    private var status: String {
        switch model.update {
        case .idle: return tr("Tu peux vérifier à tout moment.", "You can check at any time.")
        case .checking: return tr("Recherche en cours…", "Checking…")
        case .upToDate: return tr("Vigie est à jour.", "Vigie is up to date.")
        case .available(let release): return tr("La version \(release.version) est disponible.", "Version \(release.version) is available.")
        case .failed(let reason): return tr("Impossible de vérifier : \(reason)", "Couldn't check: \(reason)")
        }
    }
}

private struct AboutSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        LearnSectionTitle(tr("À propos", "About"))
            .padding(.bottom, -8)
        HStack(alignment: .center, spacing: WindowGrid.gap) {
            AppIconImage().frame(width: 72, height: 72)
            VStack(alignment: .leading, spacing: 4) {
                Text("Vigie").font(.system(size: 20, weight: .semibold))
                Text(tr("Version \(model.currentVersion?.description ?? "?")", "Version \(model.currentVersion?.description ?? "?")"))
                    .font(.system(size: 12.5)).foregroundStyle(DS.secondaryText)
                Text(tr("Le Moniteur d'activité, en lisible.", "Activity Monitor, made readable."))
                    .font(.system(size: 12.5)).foregroundStyle(DS.secondaryText)
            }
            Spacer()
        }
        .padding(WindowGrid.heroPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panelSurface()
        SettingsGroup(title: tr("Informations", "Information")) {
            SettingsRow(title: tr("Auteur", "Author"), detail: "G00dKat") { EmptyView() }
            SettingsRow(title: tr("Licence", "License"),
                        detail: tr("MIT : libre d'utiliser, de modifier et de partager.", "MIT: free to use, modify and share.")) { EmptyView() }
            SettingsRow(title: tr("Code source", "Source code"), detail: "github.com/\(model.updateRepository)") {
                Button(tr("Ouvrir", "Open")) {
                    if let url = URL(string: "https://github.com/\(model.updateRepository)") { NSWorkspace.shared.open(url) }
                }
                .buttonStyle(HUDPillButtonStyle())
            }
            SettingsRow(title: tr("Moniteur d'activité", "Activity Monitor"),
                        detail: tr("L'outil de macOS, pour tout voir dans le détail.", "macOS's tool, to see everything in detail."), divider: false) {
                Button(tr("Ouvrir", "Open")) { model.openActivityMonitor() }
                    .buttonStyle(HUDPillButtonStyle())
            }
        }
    }
}

// MARK: - Apparence

/// Le thème de Vigie : clair, sombre, ou celui du Mac.
enum ThemeChoice: String {
    case system, light, dark

    var appearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }
}

/// Change le thème de toute l'app ; depuis les Réglages, le nouveau thème se révèle à partir de la miniature cliquée :
/// un rectangle arrondi qui grandit en accélérant jusqu'à couvrir la fenêtre, avec déjà l'interface du nouveau thème dedans.
@MainActor
enum ThemeSwitcher {
    static let key = "apparence"

    static var stored: ThemeChoice { ThemeChoice(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .system }

    static func applyStored() { NSApp.appearance = stored.appearance }

    /// `origin` : la miniature, dans les coordonnées de la fenêtre (origine en haut à gauche, comme SwiftUI).
    static func switchTo(_ choice: ThemeChoice, from origin: CGRect?, cornerRadius: CGFloat = 10) {
        UserDefaults.standard.set(choice.rawValue, forKey: key)
        guard let origin, let window = NSApp.keyWindow, let content = window.contentView,
              !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
              let snapshot = content.bitmapImageRepForCachingDisplay(in: content.bounds) else {
            NSApp.appearance = choice.appearance
            return
        }
        // 1. Une image de la fenêtre dans l'ancien thème, posée par-dessus.
        content.cacheDisplay(in: content.bounds, to: snapshot)
        let image = NSImage(size: content.bounds.size)
        image.addRepresentation(snapshot)
        let cover = NSImageView(frame: content.bounds)
        cover.image = image
        cover.imageScaling = .scaleAxesIndependently
        cover.wantsLayer = true
        cover.autoresizingMask = [.width, .height]
        content.addSubview(cover)
        // 2. Dessous, l'app passe au nouveau thème.
        NSApp.appearance = choice.appearance
        // 3. Un trou en rectangle arrondi s'ouvre dans l'image, depuis la miniature, jusqu'à tout découvrir.
        let bounds = cover.bounds
        let start = CGRect(x: origin.minX, y: bounds.height - origin.maxY, width: origin.width, height: origin.height)
        let reach = [CGPoint(x: bounds.minX, y: bounds.minY), CGPoint(x: bounds.maxX, y: bounds.minY),
                     CGPoint(x: bounds.minX, y: bounds.maxY), CGPoint(x: bounds.maxX, y: bounds.maxY)]
            .map { hypot($0.x - start.midX, $0.y - start.midY) }.max() ?? 0
        let end = CGRect(x: start.midX - reach - 80, y: start.midY - reach - 80, width: (reach + 80) * 2, height: (reach + 80) * 2)
        func hole(_ rect: CGRect, _ radius: CGFloat) -> CGPath {
            let path = CGMutablePath()
            path.addRect(bounds.insetBy(dx: -4, dy: -4))
            path.addRoundedRect(in: rect, cornerWidth: radius, cornerHeight: radius)
            return path
        }
        let mask = CAShapeLayer()
        mask.frame = bounds
        mask.fillRule = .evenOdd
        mask.path = hole(end, end.width * 0.18)
        cover.layer?.mask = mask
        let grow = CABasicAnimation(keyPath: "path")
        grow.fromValue = hole(start, cornerRadius)
        grow.toValue = mask.path
        grow.duration = 0.42
        // Un court instant à la taille de la miniature : l'app a le temps de se redessiner dans le nouveau thème.
        grow.beginTime = CACurrentMediaTime() + 0.06
        grow.fillMode = .backwards
        // Lent au départ, puis de plus en plus vite : le nouveau thème envahit la fenêtre.
        grow.timingFunction = CAMediaTimingFunction(controlPoints: 0.55, 0.0, 0.9, 0.5)
        CATransaction.begin()
        CATransaction.setCompletionBlock { cover.removeFromSuperview() }
        mask.add(grow, forKey: "reveal")
        CATransaction.commit()
    }
}

private struct AppearanceSettings: View {
    @State private var choice = ThemeSwitcher.stored
    @State private var frames: [ThemeChoice: CGRect] = [:]
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        // En mode « Mac », la miniature allumée suit le thème du moment.
        let shown: ThemeChoice = choice == .system ? (scheme == .dark ? .dark : .light) : choice
        SettingsGroup(title: tr("Apparence", "Appearance")) {
            HStack(alignment: .top, spacing: 20) {
                Spacer(minLength: 0)
                ForEach([ThemeChoice.dark, .light], id: \.self) { theme in
                    ThemeThumbnail(theme: theme, selected: shown == theme) {
                        guard choice != theme else { return }
                        choice = theme
                        ThemeSwitcher.switchTo(theme, from: frames[theme])
                    }
                    .background(GeometryReader { geometry in
                        Color.clear
                            .onAppear { frames[theme] = geometry.frame(in: .global) }
                            .onChange(of: geometry.frame(in: .global)) { frames[theme] = geometry.frame(in: .global) }
                    })
                }
                Spacer(minLength: 0)
            }
            .padding(WindowGrid.cardPadding)
            Divider().padding(.leading, WindowGrid.cardPadding)
            SettingsRow(title: tr("Suivre le Mac", "Follow the Mac"),
                        detail: tr("Clair le jour, sombre le soir : comme macOS.", "Light by day, dark at night: like macOS."), divider: false) {
                SettingsSwitch(isOn: Binding(
                    get: { choice == .system },
                    set: { follow in
                        let next: ThemeChoice = follow ? .system : (scheme == .dark ? .dark : .light)
                        choice = next
                        ThemeSwitcher.switchTo(next, from: nil)
                    }))
            }
        }
    }
}

/// Une miniature de fenêtre (barre latérale, titres, cartes) dans un thème ; elle grossit au survol,
/// et le nom du thème s'écrit dessous quand elle est choisie.
private struct ThemeThumbnail: View {
    let theme: ThemeChoice
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        let dark = theme == .dark
        VStack(spacing: 8) {
            Button(action: action) {
                MiniWindow(dark: dark)
                    .frame(width: 150, height: 100)
                    .scaleEffect(hovering ? 1.06 : 1)
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: hovering)
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            Text(dark ? tr("Sombre", "Dark") : tr("Clair", "Light"))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(DS.primaryText)
                .opacity(selected ? 1 : 0)
                .animation(VigieMotion.quick, value: selected)
        }
    }
}

/// La fenêtre en miniature : trois pastilles, une colonne de lignes, un titre et trois cartes.
private struct MiniWindow: View {
    let dark: Bool

    var body: some View {
        let background = dark ? Color(white: 0.11) : .white
        let sidebar = dark ? Color(white: 0.14) : Color(white: 0.955)
        let block = dark ? Color(white: 0.2) : Color(white: 0.92)
        let line = dark ? Color(white: 0.26) : Color(white: 0.86)
        let border = dark ? Color(white: 0.24) : Color(white: 0.85)
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 10, style: .continuous).fill(background)
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 3) {
                        Circle().fill(Color(red: 1, green: 0.37, blue: 0.34)).frame(width: 5, height: 5)
                        Circle().fill(Color(red: 1, green: 0.74, blue: 0.18)).frame(width: 5, height: 5)
                        Circle().fill(Color(red: 0.16, green: 0.79, blue: 0.25)).frame(width: 5, height: 5)
                    }
                    .padding(.bottom, 6)
                    ForEach([26.0, 20, 24], id: \.self) { width in
                        Capsule().fill(line).frame(width: width, height: 3)
                    }
                    Spacer()
                    HStack(spacing: 3) {
                        Circle().fill(line).frame(width: 7, height: 7)
                        Capsule().fill(line).frame(width: 14, height: 3)
                    }
                }
                .padding(8)
                .frame(width: 46, alignment: .leading)
                .frame(maxHeight: .infinity, alignment: .top)
                .background(sidebar)
                VStack(alignment: .leading, spacing: 4) {
                    Capsule().fill(line).frame(width: 28, height: 3).padding(.top, 14)
                    Capsule().fill(line.opacity(0.7)).frame(width: 44, height: 3)
                    HStack(spacing: 4) {
                        ForEach(0..<3, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: 3, style: .continuous).fill(block).frame(width: 22, height: 16)
                        }
                    }
                    .padding(.top, 6)
                    Spacer()
                    Capsule().fill(line.opacity(0.7)).frame(width: 36, height: 3)
                }
                .padding(.leading, 8)
                .padding(.bottom, 9)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(border, lineWidth: 1)
        }
        .shadow(color: .black.opacity(dark ? 0.3 : 0.08), radius: 4, y: 2)
    }
}
