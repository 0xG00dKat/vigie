import AppKit
import AVFoundation
import SwiftUI

/// Animation d'ouverture (« Tourbillon ») : les trois paupières tournent autour du centre et se verrouillent,
/// l'iris apparaît, un clin d'œil, puis tout s'efface sur la fenêtre.
/// Vue pure du temps écoulé `t` (en secondes) : rendue image par image pour les vérifications (`--render x --intro t`).
struct LogoIntro: View {
    static let duration: Double = 3.0
    let t: Double

    /// Largeur de l'œil, en points.
    private let width: CGFloat = 280
    private var height: CGFloat { width / LogoMark.aspectRatio }

    // Minutage (secondes).
    // Un court instant de fond seul, puis les paupières entrent en douceur.
    private let lidStarts = [0.3, 0.42, 0.54]
    private let lidDuration = 1.2
    private let iris = (1.05, 1.6)
    private let blink = (2.25, 2.5)
    private let exit = (2.55, 2.9)
    private let background = (2.6, 3.0)

    private var ink: Color { DS.primaryText }

    var body: some View {
        let leaving = Ease.inOut(Ease.progress(t, exit.0, exit.1))
        ZStack {
            DS.canvas.opacity(1 - Ease.inOut(Ease.progress(t, background.0, background.1)))
            mark
            .scaleEffect(1 + 0.06 * leaving)
            .opacity(1 - leaving)
        }
        .ignoresSafeArea()
    }

    private var mark: some View {
        // Clin d'œil : fermeture rapide, réouverture plus lente.
        let middle = blink.0 + (blink.1 - blink.0) * 0.4
        let closed = t < middle ? Ease.inOut(Ease.progress(t, blink.0, middle)) : 1 - Ease.inOut(Ease.progress(t, middle, blink.1))
        return ZStack {
            lid(.upperLid, index: 0)
            lid(.leftLid, index: 1)
            lid(.lowerLid, index: 2)
            irisView
        }
        .frame(width: width, height: height)
        .scaleEffect(x: 1, y: 1 - 0.92 * closed, anchor: .center)
    }

    /// Chaque paupière part d'un angle différent, tourne autour du centre de l'œil et se verrouille (ressort doux),
    /// avec un léger flou de mouvement qui s'efface quand elle ralentit.
    private func lid(_ part: LogoPart, index: Int) -> some View {
        let progress = Ease.progress(t, lidStarts[index], lidStarts[index] + lidDuration)
        // Départ lent (le mouvement s'élance), arrivée en ressort doux.
        let settle = Ease.spring(Ease.inOut(progress) * 0.35 + progress * 0.65, damping: 0.74)
        let turn = [-160.0, -120.0, -200.0][index]
        return LogoPartShape(part: part)
            .fill(ink)
            .blur(radius: 8 * (1 - Ease.out(min(1, progress * 1.4))))
            .rotationEffect(.degrees(turn * (1 - settle)), anchor: .center)
            .scaleEffect(0.5 + 0.5 * settle, anchor: .center)
            .opacity(Ease.inOut(min(1, progress * 1.8)))
    }

    private var irisView: some View {
        let progress = Ease.progress(t, iris.0, iris.1)
        let anchor = UnitPoint(x: (LogoPaths.irisBounds.midX - LogoPaths.bounds.minX) / LogoPaths.bounds.width,
                               y: (LogoPaths.irisBounds.midY - LogoPaths.bounds.minY) / LogoPaths.bounds.height)
        return LogoPartShape(part: .iris)
            .fill(ink, style: FillStyle(eoFill: true))
            .scaleEffect(0.4 + 0.6 * Ease.spring(progress, damping: 0.68), anchor: anchor)
            .opacity(Ease.out(min(1, progress * 2)))
    }
}

/// Joue l'animation d'ouverture une fois, puis disparaît ; un clic la passe.
struct LogoIntroPlayer: View {
    let start: Date
    let onEnd: () -> Void

    var body: some View {
        TimelineView(.animation) { context in
            LogoIntro(t: max(0, context.date.timeIntervalSince(start)))
        }
        .contentShape(Rectangle())
        .onTapGesture {
            IntroSound.stop()
            onEnd()
        }
        .task {
            try? await Task.sleep(for: .seconds(max(0, start.timeIntervalSinceNow) + LogoIntro.duration))
            onEnd()
        }
    }
}

/// L'animation se joue une seule fois par lancement de Vigie : à la première ouverture de la fenêtre.
/// Jamais si macOS demande de réduire les animations, ni dans les captures.
@MainActor
enum LogoIntroGate {
    static var played = false

    /// L'heure de départ la première fois (avec le son, s'il est permis), puis nil.
    /// Rien si l'animation est coupée dans les Réglages.
    static func claim() -> Date? {
        guard !played else { return nil }
        played = true
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion || !IntroSettings.animation { return nil }
        return start()
    }

    /// Lance l'animation maintenant (et le son s'il est permis) : renvoie l'heure de départ.
    static func start() -> Date {
        guard IntroSettings.sound, IntroSound.uiSoundsEnabled,
              let url = Bundle.main.url(forResource: "ouverture", withExtension: "m4a") else { return Date() }
        return IntroSound.start(url)
    }
}

/// Le son de l'ouverture, démarré sur la même horloge que l'animation : le lecteur est préparé, puis lancé
/// à un instant précis du matériel audio ; l'animation part au même instant.
@MainActor
enum IntroSound {
    private static var player: AVAudioPlayer?
    /// Avance laissée au matériel audio pour démarrer pile à l'heure.
    private static let lead: TimeInterval = 0.08

    /// Réglage de macOS « Jouer les effets sonores de l'interface » (activé si absent).
    static var uiSoundsEnabled: Bool {
        (UserDefaults(suiteName: "com.apple.systemsound")?.object(forKey: "com.apple.sound.uiaudio.enabled") as? Int ?? 1) != 0
    }

    /// Lance le son et renvoie l'heure à laquelle l'animation doit commencer.
    static func start(_ url: URL, volume: Float = 0.25) -> Date {
        player?.stop()
        guard let sound = try? AVAudioPlayer(contentsOf: url) else { return Date() }
        sound.volume = volume
        sound.prepareToPlay()
        sound.play(atTime: sound.deviceCurrentTime + lead)
        player = sound
        return Date().addingTimeInterval(lead)
    }

    static func stop() {
        player?.stop()
        player = nil
    }
}

/// Courbes de vitesse de l'animation d'ouverture.
enum Ease {
    /// Avancement de 0 à 1 entre `start` et `end`.
    static func progress(_ t: Double, _ start: Double, _ end: Double) -> Double {
        min(1, max(0, (t - start) / (end - start)))
    }
    static func out(_ x: Double) -> Double { 1 - pow(1 - x, 3) }
    static func inOut(_ x: Double) -> Double { x < 0.5 ? 4 * x * x * x : 1 - pow(-2 * x + 2, 3) / 2 }
    /// Ressort amorti (comme les animations de macOS) : `x` de 0 à 1, posé à 1.
    /// `damping` bas = plus de rebond (0,4 vif, 0,7 posé).
    static func spring(_ x: Double, damping: Double) -> Double {
        if x <= 0 { return 0 }
        if x >= 1 { return 1 }
        let omega = 7.0 / damping
        let omegaD = omega * sqrt(1 - damping * damping)
        func raw(_ x: Double) -> Double {
            1 - exp(-damping * omega * x) * (cos(omegaD * x) + damping * omega / omegaD * sin(omegaD * x))
        }
        // Raccord exact à 1 en fin de course.
        return raw(x) + (1 - raw(1)) * x
    }
}
