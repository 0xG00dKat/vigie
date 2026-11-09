import AppKit
import SwiftUI
import VigieCore

/// Fenêtre d'accueil : ouverte une fois, au premier lancement (clé `accueilVu`), et à la demande depuis le menu ⚙︎.
/// Une app de la barre des menus n'a pas de fenêtre au départ : sans accueil, un débutant ne la trouverait pas.
@MainActor
enum OnboardingWindow {
    static let seenKey = "accueilVu"
    private static var window: NSWindow?
    private static var closeObserver: NSObjectProtocol?

    static func showIfNeeded(model: AppModel) {
        guard !UserDefaults.standard.bool(forKey: seenKey) else { return }
        show(model: model)
    }

    static func show(model: AppModel) {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate()
            return
        }
        let host = NSHostingController(rootView: OnboardingView(onFinish: { close() }).environment(model))
        let window = NSWindow(contentViewController: host)
        window.title = tr("Bienvenue dans Vigie", "Welcome to Vigie")
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 580, height: 500))
        window.center()
        // Fermer la fenêtre compte comme « vu » : on ne la ressort pas à chaque lancement.
        closeObserver = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { _ in
            MainActor.assumeIsolated {
                UserDefaults.standard.set(true, forKey: seenKey)
                OnboardingWindow.window = nil
            }
        }
        Self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    static func close() {
        UserDefaults.standard.set(true, forKey: seenKey)
        window?.close()
    }
}

/// Trois écrans : ce que fait Vigie et où la trouver, ce qu'elle va demander, comment la voir.
struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    let onFinish: () -> Void
    @State private var page: Int
    @State private var mode: ExperienceMode = ExperienceMode.looksLikeDeveloperMac ? .developer : .simple
    @State private var launchAtLogin = true

    init(startPage: Int = 0, onFinish: @escaping () -> Void) {
        self.onFinish = onFinish
        _page = State(initialValue: startPage)
    }

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch page {
                case 0: welcome
                case 1: promises
                default: choice
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.horizontal, 40)
            .padding(.top, 36)

            HStack {
                HStack(spacing: 7) {
                    ForEach(0..<3) { index in
                        Circle()
                            .fill(index == page ? VigieTheme.accent : Color.primary.opacity(0.15))
                            .frame(width: 7, height: 7)
                    }
                }
                Spacer()
                if page > 0 {
                    Button(tr("Retour", "Back")) { page -= 1 }
                        .buttonStyle(.borderless)
                        .padding(.trailing, 10)
                }
                Button {
                    if page < 2 { page += 1 } else { finish() }
                } label: {
                    Text(page < 2 ? tr("Suivant", "Next") : tr("C'est parti", "Let's go"))
                        .frame(minWidth: 90)
                }
                .buttonStyle(AccentButtonStyle())
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 22)
        }
        .frame(width: 580, height: 500)
        .background(Color(nsColor: .windowBackgroundColor))
        .tint(VigieTheme.accent)
    }

    // MARK: Écrans

    private var welcome: some View {
        VStack(spacing: 16) {
            AppIconImage().frame(width: 92, height: 92)
            Text(tr("Bienvenue dans Vigie", "Welcome to Vigie"))
                .font(.system(size: 26, weight: .bold))
            Text(tr("Vigie t'aide à comprendre ce qui tourne sur ton Mac et ce qui prend de la place, en mots simples. Et à faire le ménage, sans risque.",
                    "Vigie helps you understand what's running on your Mac and what takes up space, in plain words. And to tidy up, safely."))
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            MenuBarHint().padding(.top, 10)
        }
    }

    private var promises: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(tr("Ce que Vigie va te demander", "What Vigie will ask you"))
                .font(.system(size: 24, weight: .bold))
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.bottom, 4)
            PromiseRow(symbol: "lock.shield", tint: VigieTheme.accent,
                       title: tr("L'accès à tes dossiers", "Access to your folders"),
                       text: tr("La première fois que tu regardes l'espace disque, macOS demandera l'accès au Bureau, aux Documents et aux Téléchargements. C'est pour mesurer tes fichiers : réponds « Autoriser ».",
                                "The first time you look at disk space, macOS will ask for access to your Desktop, Documents and Downloads. It's to measure your files: choose “Allow”."))
            PromiseRow(symbol: "hand.raised", tint: VigieTheme.accent,
                       title: tr("Rien ne quitte ton Mac", "Nothing leaves your Mac"),
                       text: tr("Pas de compte, pas de publicité, pas de collecte. Seules exceptions : la recherche de nouvelles versions de Vigie, et « Demander à Claude » si tu cliques dessus.",
                                "No account, no ads, no tracking. The only exceptions: checking for new versions of Vigie, and “Ask Claude” if you click it."))
            PromiseRow(symbol: "arrow.uturn.backward.circle", tint: VigieTheme.accent,
                       title: tr("Rien n'est supprimé sans toi", "Nothing is deleted without you"),
                       text: tr("Vigie te dit ce qui va se passer et demande toujours confirmation. Ce qui n'est pas un fichier temporaire part à la corbeille : tu peux revenir en arrière.",
                                "Vigie tells you what will happen and always asks first. Anything that isn't a temporary file goes to the Trash: you can undo."))
        }
    }

    private var choice: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(tr("Comment veux-tu voir Vigie ?", "How do you want to see Vigie?"))
                .font(.system(size: 24, weight: .bold))
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.bottom, 4)
            ModeChoice(mode: .simple, selected: $mode, recommended: !ExperienceMode.looksLikeDeveloperMac, symbol: "leaf",
                       title: tr("Simple", "Simple"),
                       text: tr("L'essentiel, en mots de tous les jours. Idéal si tu découvres le Mac.",
                                "The essentials, in everyday words. Ideal if you're new to the Mac."))
            ModeChoice(mode: .developer, selected: $mode, recommended: ExperienceMode.looksLikeDeveloperMac, symbol: "terminal",
                       title: tr("Développeur", "Developer"),
                       text: tr("Tout le détail : projets, ports, Docker, commandes de nettoyage.",
                                "Every detail: projects, ports, Docker, cleanup commands."))
            Toggle(tr("Ouvrir Vigie au démarrage du Mac", "Open Vigie when the Mac starts"), isOn: $launchAtLogin)
                .toggleStyle(.checkbox)
                .padding(.top, 6)
            Text(tr("Tu pourras changer ces deux réglages plus tard, dans le menu ⚙︎ de Vigie.",
                    "You can change both later, in Vigie's ⚙︎ menu."))
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
        }
    }

    private func finish() {
        model.setExperience(mode)
        if launchAtLogin != (model.loginItemState == .enabled) { model.setLaunchAtLogin(launchAtLogin) }
        onFinish()
    }
}

/// L'icône de Vigie, telle que macOS la dessine (repli : un œil, hors du paquet .app).
struct AppIconImage: View {
    var body: some View {
        if Bundle.main.bundleURL.pathExtension == "app", let image = NSApp?.applicationIconImage {
            Image(nsImage: image).resizable().interpolation(.high)
        } else {
            Image(systemName: "eye.circle.fill").resizable().foregroundStyle(VigieTheme.accent)
        }
    }
}

/// Une barre des menus dessinée en petit : « Vigie est ici ».
struct MenuBarHint: View {
    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 14) {
                Spacer()
                Image(systemName: "wifi").foregroundStyle(.secondary)
                Image(systemName: "battery.75percent").foregroundStyle(.secondary)
                Image(nsImage: MenuBarIcon.image)
                    .renderingMode(.template)
                    .foregroundStyle(.primary)
                    .padding(5)
                    .background(Circle().fill(VigieTheme.accent.opacity(0.18)))
                    .overlay(Circle().strokeBorder(VigieTheme.accent, lineWidth: 1.5))
                Text("9:41").font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .frame(width: 330)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.06)))
            HStack(spacing: 6) {
                Image(systemName: "arrow.up.right")
                Text(tr("Vigie est ici, en haut à droite de l'écran. Clique sur l'œil pour l'ouvrir.",
                        "Vigie lives here, at the top right of the screen. Click the eye to open it."))
            }
            .font(.system(size: 12.5, weight: .medium))
            .foregroundStyle(VigieTheme.accent)
        }
    }
}

struct PromiseRow: View {
    let symbol: String
    let tint: Color
    let title: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VigieTile(symbol: symbol, tint: tint, size: 36)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 14, weight: .semibold))
                Text(text)
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct ModeChoice: View {
    let mode: ExperienceMode
    @Binding var selected: ExperienceMode
    let recommended: Bool
    let symbol: String
    let title: String
    let text: String

    var body: some View {
        let isSelected = selected == mode
        Button {
            selected = mode
        } label: {
            HStack(alignment: .top, spacing: 14) {
                VigieTile(symbol: symbol, tint: isSelected ? VigieTheme.accent : .gray, size: 36)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 7) {
                        Text(title).font(.system(size: 14, weight: .semibold))
                        if recommended { Chip(text: tr("conseillé", "recommended")) }
                    }
                    Text(text)
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundStyle(isSelected ? VigieTheme.accent : Color.secondary)
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(isSelected ? VigieTheme.accent.opacity(0.08) : Color(nsColor: .controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(isSelected ? VigieTheme.accent : Color.primary.opacity(0.1), lineWidth: isSelected ? 1.5 : 0.5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
