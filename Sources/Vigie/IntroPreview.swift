import AppKit
import SwiftUI

/// `Vigie --intro-preview [dossier-de-sons]` : une fenêtre qui joue l'animation d'ouverture devant la fenêtre de Vigie
/// (Mac fictif), avec un bouton par son du dossier pour la rejouer avec ce son. Outil de mise au point.
@MainActor
enum IntroPreview {
    static func run(soundsFolder: String?) {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        // L'aperçu rejoue l'animation lui-même : la fenêtre de fond ne la joue pas.
        LogoIntroGate.played = true
        let model = AppModel(startImmediately: false)
        model.loadDemo()
        let sounds = soundsFolder.map { folder in
            ((try? FileManager.default.contentsOfDirectory(atPath: folder)) ?? [])
                .filter { ["wav", "aiff", "caf", "m4a"].contains(($0 as NSString).pathExtension) }
                .sorted()
                .map { URL(fileURLWithPath: folder).appendingPathComponent($0) }
        } ?? []
        let host = NSHostingView(rootView: IntroPreviewView(sounds: sounds).environment(model))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1200, height: 830),
                              styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "Vigie — aperçu de l'animation d'ouverture"
        window.contentView = host
        window.center()
        window.makeKeyAndOrderFront(nil)
        app.activate(ignoringOtherApps: true)
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { _ in
            NSApp.terminate(nil)
        }
        app.run()
    }
}

struct IntroPreviewView: View {
    let sounds: [URL]
    @State private var start = Date()
    @State private var playing: URL?

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                VigieWindow()
                TimelineView(.animation) { context in
                    let t = context.date.timeIntervalSince(start)
                    if t < LogoIntro.duration { LogoIntro(t: max(0, t)) }
                }
                .allowsHitTesting(false)
            }
            .frame(width: 1200, height: 760)
            .clipped()
            HStack(spacing: 8) {
                Button("Rejouer sans son") { replay(nil) }
                ForEach(sounds, id: \.self) { url in
                    Button(url.deletingPathExtension().lastPathComponent) { replay(url) }
                        .buttonStyle(.borderedProminent)
                        .tint(playing == url ? VigieTheme.accent : .gray)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .frame(height: 70)
        }
    }

    private func replay(_ url: URL?) {
        playing = url
        IntroSound.stop()
        // Même démarrage que dans l'app : le son et l'animation partent ensemble.
        start = url.map { IntroSound.start($0) } ?? Date()
    }
}
