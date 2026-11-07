import Foundation

/// Langues de l'interface.
public enum Language: String, CaseIterable, Sendable {
    case fr, en

    /// Nom de la langue dans sa propre langue, pour le menu de choix.
    public var nativeName: String {
        switch self {
        case .fr: return "Français"
        case .en: return "English"
        }
    }
}

/// Langue courante de Vigie. Choisie au lancement (réglage de l'utilisateur ou langue du système),
/// lue aussi depuis le fil d'arrière-plan qui construit les groupes : protégée par un verrou.
public enum Localization {
    private static let lock = NSLock()
    private static var storage: Language = systemLanguage()

    public static var current: Language {
        get {
            lock.lock()
            defer { lock.unlock() }
            return storage
        }
        set {
            lock.lock()
            storage = newValue
            lock.unlock()
        }
    }

    /// Première langue gérée dans les préférences du système, l'anglais à défaut.
    public static func systemLanguage(preferred: [String] = Locale.preferredLanguages) -> Language {
        for identifier in preferred {
            if identifier.hasPrefix("fr") { return .fr }
            if identifier.hasPrefix("en") { return .en }
        }
        return .en
    }
}

/// Un texte en français et en anglais. Les deux sont obligatoires : un texte non traduit ne compile pas.
/// Pour ajouter une langue, ajouter un champ ici puis suivre les erreurs du compilateur.
public struct L: Sendable, Hashable {
    public let fr: String
    public let en: String

    public init(_ fr: String, _ en: String) {
        self.fr = fr
        self.en = en
    }

    public var text: String { text(in: Localization.current) }

    public func text(in language: Language) -> String {
        switch language {
        case .fr: return fr
        case .en: return en
        }
    }
}

/// Raccourci pour un texte d'interface : `tr("Quitter", "Quit")`.
public func tr(_ fr: String, _ en: String) -> String {
    L(fr, en).text
}
