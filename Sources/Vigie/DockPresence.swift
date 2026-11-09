import AppKit
import SwiftUI

/// Vigie vit dans la barre des menus, sans icône dans le Dock (`LSUIElement`). Mais son icône peut disparaître
/// de la barre des menus (cachée par l'encoche, ou par trop d'icônes) : il faut toujours un autre chemin.
///
/// - Tant que la fenêtre est ouverte, Vigie a son icône dans le Dock (et dans ⌘Tab), comme une app normale.
/// - « Toujours dans le Dock » (menu ⚙︎, clé `toujoursDansLeDock`) la garde même fenêtre fermée.
/// - Rouvrir Vigie (Launchpad, Spotlight, Finder, clic sur l'icône du Dock) ouvre la fenêtre.
@MainActor
enum DockPresence {
    static let alwaysKey = "toujoursDansLeDock"
    /// Seulement dans l'app lancée normalement : jamais pendant un rendu (`--render`), qui n'a pas d'icône.
    static var enabled = false

    /// Ouvre la fenêtre (scène SwiftUI) : donné par une vue qui existe toujours, l'icône de la barre des menus.
    static var openWindow: (() -> Void)?
    private static weak var window: NSWindow?

    static var alwaysInDock: Bool {
        get { UserDefaults.standard.bool(forKey: alwaysKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: alwaysKey)
            apply()
        }
    }

    static func windowAttached(_ window: NSWindow) {
        self.window = window
        apply()
    }

    static func windowClosed() {
        window = nil
        // Laisser la fenêtre finir de se fermer avant de retirer l'icône (sinon macOS active une autre app trop tôt).
        DispatchQueue.main.async { apply() }
    }

    static func apply() {
        guard enabled else { return }
        let wanted: NSApplication.ActivationPolicy = alwaysInDock || window != nil ? .regular : .accessory
        guard NSApp.activationPolicy() != wanted else { return }
        NSApp.setActivationPolicy(wanted)
        if wanted == .regular, let window {
            // Passer en app « normale » peut faire perdre le premier plan : on le reprend.
            window.makeKeyAndOrderFront(nil)
            NSApp.activate()
        }
    }

    /// Depuis le panneau de la barre des menus : le refermer, puis montrer la fenêtre. Ouvrir une fenêtre de la même
    /// app ne ferme pas le panneau tout seul (il ne se ferme que quand on clique ailleurs).
    static func openFromPanel(_ dismiss: DismissAction? = nil) {
        dismiss?()
        closePanel()
        showWindow()
    }

    /// Ferme le panneau s'il est encore à l'écran (filet de sécurité si `dismiss` n'a rien fait).
    static func closePanel() {
        // Le panneau de MenuBarExtra : sa classe le dit, ou c'est un panneau flottant au niveau de la barre des menus.
        for candidate in NSApp.windows where candidate.isVisible && candidate !== window
            && (String(describing: type(of: candidate)).contains("MenuBarExtra")
                || (candidate is NSPanel && candidate.level.rawValue >= NSWindow.Level.statusBar.rawValue)) {
            candidate.close()
        }
    }

    /// Clic sur l'icône du Dock, ou Vigie relancée alors qu'elle tourne déjà.
    static func showWindow() {
        if let window {
            if window.isMiniaturized { window.deminiaturize(nil) }
            window.makeKeyAndOrderFront(nil)
        } else {
            openWindow?()
        }
        NSApp.activate()
    }
}

final class VigieAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated {
            DockPresence.enabled = true
            DockPresence.apply()
            // Thème choisi dans les Réglages (clair, sombre, ou celui du Mac).
            ThemeSwitcher.applyStored()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        MainActor.assumeIsolated { DockPresence.showWindow() }
        return false
    }
}

/// Posée dans la fenêtre : dit à `DockPresence` quand elle s'ouvre et quand elle se ferme.
struct DockPresenceObserver: NSViewRepresentable {
    func makeNSView(context: Context) -> ObserverView { ObserverView() }
    func updateNSView(_ view: ObserverView, context: Context) {}

    final class ObserverView: NSView {
        private var token: NSObjectProtocol?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let token { NotificationCenter.default.removeObserver(token) }
            token = nil
            guard let window else { return }
            // Pas de trait sous la barre d'outils : elle se fond dans la page au lieu d'avoir l'air posée dessus.
            window.titlebarSeparatorStyle = .none
            DockPresence.windowAttached(window)
            token = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { _ in
                MainActor.assumeIsolated { DockPresence.windowClosed() }
            }
        }
    }
}

/// Donne à `DockPresence` de quoi ouvrir la fenêtre, depuis l'icône de la barre des menus (toujours créée,
/// même quand macOS la cache faute de place).
struct WindowOpenerRegistration: ViewModifier {
    @Environment(\.openWindow) private var openWindow

    func body(content: Content) -> some View {
        content.onAppear {
            DockPresence.openWindow = { openWindow(id: VigieWindow.id) }
        }
    }
}
