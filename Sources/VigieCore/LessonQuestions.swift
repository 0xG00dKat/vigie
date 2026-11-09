import Foundation

/// « Par où commencer » : on part de ce qui arrive au Mac (« Mon Mac est lent »…), et chaque question ouvre
/// quelques explications à lire dans l'ordre.
public struct LessonQuestion: Sendable, Identifiable, Equatable {
    public var id: String
    public var symbol: String
    public var title: L
    /// Une phrase sous le titre : ce qu'on va comprendre.
    public var subtitle: L
    /// Les explications, dans l'ordre de lecture.
    public var lessonIDs: [String]
    /// Réservée au mode Développeur.
    public var isDeveloper: Bool

    public init(id: String, symbol: String, title: L, subtitle: L, lessonIDs: [String], isDeveloper: Bool = false) {
        self.id = id
        self.symbol = symbol
        self.title = title
        self.subtitle = subtitle
        self.lessonIDs = lessonIDs
        self.isDeveloper = isDeveloper
    }

    /// Les explications de la question qui existent (et sont visibles dans ce mode).
    public func lessons(developer: Bool) -> [Lesson] {
        lessonIDs.compactMap(Lessons.lesson).filter { developer || !$0.isDeveloper }
    }
}

public enum LessonQuestions {
    public static func question(_ id: String) -> LessonQuestion? { all.first { $0.id == id } }

    public static func visible(developer: Bool) -> [LessonQuestion] { all.filter { developer || !$0.isDeveloper } }

    public static let all: [LessonQuestion] = [
        LessonQuestion(
            id: "lent", symbol: "gauge.with.needle",
            title: L("Mon Mac est lent", "My Mac is slow"),
            subtitle: L("Ce qui le ralentit, et ce qui le fait repartir.", "What slows it down, and what gets it going again."),
            lessonIDs: ["memoire", "swap", "processeur", "apps-web", "onglets", "redemarrer"]),
        LessonQuestion(
            id: "disque-plein", symbol: "internaldrive",
            title: L("Mon disque est plein", "My disk is full"),
            subtitle: L("Où part la place, et ce qu'on peut libérer sans risque.", "Where the space goes, and what you can safely free."),
            lessonIDs: ["disque-se-remplit", "caches", "donnees-systeme", "telechargements", "corbeille", "icloud", "time-machine"]),
        LessonQuestion(
            id: "batterie", symbol: "bolt",
            title: L("Ma batterie se vide vite", "My battery drains fast"),
            subtitle: L("Ce qui la consomme, et si elle s'use.", "What uses it up, and whether it's wearing out."),
            lessonIDs: ["batterie", "veille", "processeur", "apps-web"]),
        LessonQuestion(
            id: "chaleur", symbol: "thermometer.medium",
            title: L("Mon Mac chauffe", "My Mac runs hot"),
            subtitle: L("Pourquoi il chauffe, et quand s'en inquiéter.", "Why it heats up, and when to worry."),
            lessonIDs: ["chaleur", "processeur", "onglets", "demarrage"]),
        LessonQuestion(
            id: "ce-qui-tourne", symbol: "square.grid.2x2",
            title: L("Je ne sais pas ce qui tourne", "I don't know what's running"),
            subtitle: L("Des centaines de programmes : d'où ils viennent, lesquels fermer.", "Hundreds of programs: where they come from, which to close."),
            lessonIDs: ["processus", "quitter-vs-fermer", "demarrage", "apps-web", "forcer-a-quitter"]),
        LessonQuestion(
            id: "debut", symbol: "lightbulb",
            title: L("Je débute sur Mac", "I'm new to the Mac"),
            subtitle: L("Les bases, en quelques minutes.", "The basics, in a few minutes."),
            lessonIDs: ["bases-mac", "memoire-vs-disque", "quitter-vs-fermer", "forcer-a-quitter", "redemarrer", "mises-a-jour", "telechargements"]),
        LessonQuestion(
            id: "dev", symbol: "terminal",
            title: L("Je développe sur ce Mac", "I develop on this Mac"),
            subtitle: L("Ports, dépendances et Docker : ce qui prend la place et la mémoire.", "Ports, dependencies and Docker: what takes space and memory."),
            lessonIDs: ["ports", "node-modules", "docker-disque", "processus"],
            isDeveloper: true),
    ]
}
