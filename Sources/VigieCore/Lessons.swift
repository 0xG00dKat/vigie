import Foundation

/// « Comprendre mon Mac » : de courtes explications, en mots simples, de ce que Vigie montre.
/// Chaque écran peut renvoyer vers l'une d'elles (« En savoir plus »).
public struct Lesson: Sendable, Identifiable, Equatable {
    public var id: String
    public var symbol: String
    public var title: L
    /// Une phrase, pour la liste.
    public var summary: L
    public var paragraphs: [L]
    /// « À retenir », en une ligne.
    public var takeaway: L
    /// Réservée au mode Développeur (ports, serveurs locaux…).
    public var isDeveloper: Bool

    public init(id: String, symbol: String, title: L, summary: L, paragraphs: [L], takeaway: L, isDeveloper: Bool = false) {
        self.id = id
        self.symbol = symbol
        self.title = title
        self.summary = summary
        self.paragraphs = paragraphs
        self.takeaway = takeaway
        self.isDeveloper = isDeveloper
    }
}

/// Les rubriques de « Comprendre mon Mac ».
public enum LessonTopic: String, CaseIterable, Sendable {
    case basics, speed, disk, battery, developer

    public var title: L {
        switch self {
        case .basics: return L("Les bases", "The basics")
        case .speed: return L("Vitesse et mémoire", "Speed and memory")
        case .disk: return L("Disque et fichiers", "Disk and files")
        case .battery: return L("Batterie et veille", "Battery and sleep")
        case .developer: return L("Développeur", "Developer")
        }
    }
}

extension Lesson {
    /// La rubrique de l'explication.
    public var topic: LessonTopic {
        if isDeveloper { return .developer }
        switch id {
        case "bases-mac", "memoire-vs-disque", "quitter-vs-fermer", "redemarrer", "mises-a-jour", "forcer-a-quitter", "telechargements":
            return .basics
        case "memoire", "swap", "processus", "processeur", "chaleur", "apps-web", "onglets", "demarrage":
            return .speed
        case "batterie", "veille":
            return .battery
        default:
            return .disk
        }
    }
}

public enum Lessons {
    public static func lesson(_ id: String) -> Lesson? { all.first { $0.id == id } }

    public static func visible(developer: Bool) -> [Lesson] { all.filter { developer || !$0.isDeveloper } }

    /// Toutes les explications : les bases d'abord, puis celles de Vigie, puis les nouvelles.
    public static let all: [Lesson] = basics + core + more

    static let core: [Lesson] = [
        Lesson(
            id: "memoire", symbol: "memorychip",
            title: L("La mémoire (RAM)", "Memory (RAM)"),
            summary: L("Le plan de travail du Mac : ce qui est ouvert y est posé.", "The Mac's workbench: whatever is open sits on it."),
            paragraphs: [
                L("La mémoire, c'est le plan de travail du Mac. Chaque app ouverte, chaque onglet, chaque document y prend un peu de place pour être prêt tout de suite.",
                  "Memory is the Mac's workbench. Every open app, tab and document takes a little room on it so it's ready right away."),
                L("Une mémoire bien remplie n'est pas un problème : macOS garde exprès des choses en mémoire pour aller plus vite, et les retire dès qu'il faut de la place. C'est quand elle déborde vraiment que le Mac ralentit.",
                  "Full memory isn't a problem: macOS deliberately keeps things in memory to be faster, and drops them as soon as room is needed. It's when it truly overflows that the Mac slows down."),
                L("Pour savoir si ça va, regarde la « pression » de la mémoire (dans Vitesse et batterie) plutôt que le nombre de gigaoctets utilisés.",
                  "To know if things are fine, look at memory “pressure” (in Speed and battery) rather than the number of gigabytes used."),
            ],
            takeaway: L("Mémoire pleine ne veut pas dire Mac lent. Une pression en rouge, si.", "Full memory doesn't mean a slow Mac. Red pressure does.")),
        Lesson(
            id: "swap", symbol: "arrow.left.arrow.right",
            title: L("Quand la mémoire déborde (le « swap »)", "When memory overflows (“swap”)"),
            summary: L("Le Mac range sur le disque ce qui ne tient plus en mémoire.", "The Mac puts on disk what no longer fits in memory."),
            paragraphs: [
                L("Quand le plan de travail est plein, macOS compresse d'abord ce qui y est posé. S'il manque encore de la place, il range une partie sur le disque : c'est le « swap » (Vigie dit « rangé sur le disque »).",
                  "When the workbench is full, macOS first compresses what's on it. If there's still not enough room, it moves part of it to the disk: that's “swap” (Vigie says “moved to disk”)."),
                L("Le disque est bien plus lent que la mémoire : quand beaucoup de choses y sont rangées, passer d'une app à l'autre devient poussif. Un peu de swap est normal ; plusieurs gigaoctets en continu, c'est le signe qu'il y a trop d'ouvert pour ce Mac.",
                  "The disk is much slower than memory: when a lot is moved there, switching apps gets sluggish. A little swap is normal; several gigabytes all the time means too much is open for this Mac."),
                L("Le remède : quitter les apps qui prennent le plus de mémoire (Vigie les montre), ou fermer des onglets.",
                  "The fix: quit the apps using the most memory (Vigie shows them), or close some tabs."),
            ],
            takeaway: L("Beaucoup de swap = trop d'ouvert. Quitte une ou deux grosses apps.", "Lots of swap = too much open. Quit one or two big apps.")),
        Lesson(
            id: "processus", symbol: "square.stack.3d.up",
            title: L("Pourquoi des centaines de processus ?", "Why hundreds of processes?"),
            summary: L("Une app, c'est souvent des dizaines de petits programmes.", "One app is often dozens of small programs."),
            paragraphs: [
                L("Un processus, c'est un programme qui tourne. Le Moniteur d'activité en montre souvent plus de mille : c'est normal.",
                  "A process is a running program. Activity Monitor often shows over a thousand: that's normal."),
                L("macOS lui-même en fait tourner des centaines (réseau, notifications, sauvegarde…). Et une seule app en lance souvent beaucoup : un navigateur crée un processus par onglet et par extension, pour qu'un onglet qui plante n'emporte pas tout.",
                  "macOS itself runs hundreds (network, notifications, backup…). And a single app often starts many: a browser creates one per tab and extension, so a crashing tab doesn't take everything down."),
                L("Vigie les regroupe par app : quitter l'app arrête tous ses processus d'un coup. La rubrique Système (macOS) n'est jamais fermable.",
                  "Vigie groups them by app: quitting the app stops all its processes at once. The System section (macOS) can never be closed."),
            ],
            takeaway: L("Le nombre de processus ne dit rien. Ce qui compte : quelle app prend la mémoire et le processeur.", "The process count means nothing. What matters: which app uses memory and CPU.")),
        Lesson(
            id: "disque-se-remplit", symbol: "internaldrive",
            title: L("Pourquoi le disque se remplit tout seul", "Why the disk fills up on its own"),
            summary: L("Caches, mises à jour, sauvegardes, téléchargements : ça s'accumule.", "Caches, updates, backups, downloads: it adds up."),
            paragraphs: [
                L("Même sans rien enregistrer, le disque se remplit : les apps gardent des copies pour aller plus vite (les caches), macOS télécharge des mises à jour et des voix ou des modèles d'IA, les messageries gardent les photos reçues, et le dossier Téléchargements grossit.",
                  "Even without saving anything, the disk fills up: apps keep copies to be faster (caches), macOS downloads updates, voices or AI models, messaging apps keep received photos, and the Downloads folder grows."),
                L("Il faut garder de la marge : sous 10 à 15 % d'espace libre, le Mac ralentit, et les mises à jour de macOS peuvent échouer faute de place.",
                  "Keep some room: below 10 to 15% free space, the Mac slows down, and macOS updates can fail for lack of space."),
                L("Vigie te dit ce qui a grossi depuis la dernière analyse, et ce qui se vide sans risque. L'Historique montre la tendance sur plusieurs semaines.",
                  "Vigie tells you what grew since the last analysis, and what's safe to clear. History shows the trend over weeks."),
            ],
            takeaway: L("Garde au moins 15 % libres. Commence par « Nettoyer ce qui est sûr ».", "Keep at least 15% free. Start with “Clean what's safe”.")),
        Lesson(
            id: "caches", symbol: "arrow.triangle.2.circlepath",
            title: L("Les caches et fichiers temporaires", "Caches and temporary files"),
            summary: L("Des copies pour aller plus vite, qui se refont toutes seules.", "Copies to go faster, which come back on their own."),
            paragraphs: [
                L("Un cache, c'est une copie que garde une app pour ne pas refaire le même travail : les images d'un site déjà visité, une musique déjà écoutée, un fichier déjà téléchargé.",
                  "A cache is a copy an app keeps so it doesn't redo the same work: images from a site you've visited, music you've played, a file already downloaded."),
                L("Les vider ne fait rien perdre : l'app les recrée quand elle en a besoin. La première ouverture qui suit peut juste être un peu plus lente.",
                  "Clearing them loses nothing: the app recreates them when needed. The next first launch may just be a little slower."),
                L("Ils reviennent avec le temps : c'est normal de les vider de temps en temps, quand la place manque.",
                  "They come back over time: it's normal to clear them now and then, when space runs low."),
            ],
            takeaway: L("Vider un cache est sans risque, mais il revient.", "Clearing a cache is safe, but it comes back.")),
        Lesson(
            id: "donnees-systeme", symbol: "gearshape",
            title: L("Les « Données système »", "“System Data”"),
            summary: L("La grosse case grise des Réglages, et ce qu'elle cache.", "The big gray box in Settings, and what it hides."),
            paragraphs: [
                L("Dans Réglages Système › Général › Stockage, une barre grise « Données système » prend souvent des dizaines de gigaoctets. macOS y range tout ce qui n'entre pas dans une autre case : caches, journaux, sauvegardes locales de Time Machine, systèmes des simulateurs d'iPhone, voix et modèles d'IA téléchargés…",
                  "In System Settings › General › Storage, a gray “System Data” bar often takes tens of gigabytes. macOS puts there everything that doesn't fit another box: caches, logs, local Time Machine snapshots, iPhone simulator runtimes, downloaded voices and AI models…"),
                L("Une partie est gérée par macOS lui-même (il la libère quand la place manque) ; une autre se vide sans risque ; le reste est à garder. Vigie la détaille et dit, pour chaque morceau, ce qu'on peut en faire.",
                  "Part of it is managed by macOS itself (it frees it when space runs low); part can be safely cleared; the rest should stay. Vigie breaks it down and says, for each piece, what can be done."),
            ],
            takeaway: L("« Données système » n'est pas une seule chose : regarde le détail avant de t'inquiéter.", "“System Data” isn't one thing: look at the details before worrying.")),
        Lesson(
            id: "corbeille", symbol: "trash",
            title: L("La corbeille et la place qui ne revient pas", "The Trash and space that doesn't come back"),
            summary: L("Mettre à la corbeille ne libère rien tant qu'on ne la vide pas.", "Moving to the Trash frees nothing until you empty it."),
            paragraphs: [
                L("Ce qui va à la corbeille reste sur le disque : c'est ce qui permet de revenir en arrière. La place ne revient qu'une fois la corbeille vidée.",
                  "What goes to the Trash stays on the disk: that's what lets you undo. The space only comes back once the Trash is emptied."),
                L("C'est pour ça que Vigie met tes fichiers à la corbeille (tu peux les récupérer) et rappelle combien attend d'être vidé. Les caches, eux, sont supprimés directement : ils se recréent.",
                  "That's why Vigie moves your files to the Trash (you can get them back) and reminds you how much is waiting to be emptied. Caches, though, are deleted directly: they rebuild."),
            ],
            takeaway: L("Pas de place libérée ? Vide la corbeille.", "No space freed? Empty the Trash.")),
        Lesson(
            id: "batterie", symbol: "battery.75percent",
            title: L("La batterie : cycles et santé", "The battery: cycles and health"),
            summary: L("Elle s'use avec les cycles, et c'est normal.", "It wears with cycles, and that's normal."),
            paragraphs: [
                L("Un cycle, c'est l'équivalent d'une charge complète, même en plusieurs fois (deux fois 50 % = un cycle). Une batterie de Mac portable est prévue pour garder la plus grande partie de sa capacité pendant des centaines de cycles.",
                  "A cycle is the equivalent of one full charge, even over several sessions (twice 50% = one cycle). A MacBook battery is designed to keep most of its capacity for hundreds of cycles."),
                L("La « santé » (capacité maximale) baisse doucement avec le temps. Quand macOS indique « Révision recommandée », la batterie peut être remplacée.",
                  "“Health” (maximum capacity) slowly drops over time. When macOS shows “Service Recommended”, the battery can be replaced."),
                L("Ce qui vide la batterie au quotidien : une app qui travaille en arrière-plan, ou qui empêche le Mac de dormir. Vigie les montre dans Vitesse et batterie.",
                  "What drains the battery day to day: an app working in the background, or keeping the Mac awake. Vigie shows them in Speed and battery."),
            ],
            takeaway: L("Les cycles qui montent, c'est normal. Une app qui empêche la veille, c'est à régler.", "Rising cycles are normal. An app preventing sleep is worth fixing.")),
        Lesson(
            id: "demarrage", symbol: "power",
            title: L("Ce qui démarre avec le Mac", "What starts with the Mac"),
            summary: L("Des aides d'apps qui se lancent toutes seules.", "App helpers that start on their own."),
            paragraphs: [
                L("Beaucoup d'apps installent une petite aide qui démarre avec ta session : pour chercher des mises à jour, afficher une icône dans la barre des menus, ou synchroniser des fichiers.",
                  "Many apps install a small helper that starts with your session: to check for updates, show a menu bar icon, or sync files."),
                L("La plupart sont utiles. Mais celles d'apps que tu n'utilises plus prennent un peu de mémoire et de batterie pour rien. Vigie les relie à leur app ; macOS permet de les couper dans Réglages Système › Général › Ouverture.",
                  "Most are useful. But those from apps you no longer use take a bit of memory and battery for nothing. Vigie links them to their app; macOS lets you turn them off in System Settings › General › Login Items."),
            ],
            takeaway: L("Une aide d'une app que tu n'utilises plus peut être coupée.", "A helper from an app you no longer use can be turned off.")),
        Lesson(
            id: "ports", symbol: "point.3.connected.trianglepath.dotted",
            title: L("Les ports et les serveurs locaux", "Ports and local servers"),
            summary: L("Qui écoute, et qui peut s'y connecter.", "Who listens, and who can connect."),
            paragraphs: [
                L("Un serveur de dev « écoute » sur un port (3000, 5173, 8080…). Un seul programme peut tenir un port à la fois : d'où « port déjà utilisé » quand un ancien serveur tourne encore.",
                  "A dev server “listens” on a port (3000, 5173, 8080…). Only one program can hold a port at a time: hence “port already in use” when an old server is still running."),
                L("L'adresse compte : 127.0.0.1 (localhost) n'est joignable que depuis ce Mac ; 0.0.0.0 l'ouvre aux autres appareils du même réseau, au café comme au bureau. Pour un serveur de dev, 127.0.0.1 suffit presque toujours.",
                  "The address matters: 127.0.0.1 (localhost) is only reachable from this Mac; 0.0.0.0 opens it to other devices on the same network, at a café or the office. For a dev server, 127.0.0.1 is almost always enough."),
            ],
            takeaway: L("Port pris : la page Ports dit par qui. Serveur en orange : il est visible sur le Wi-Fi.", "Port taken: the Ports page says by whom. Orange server: it's visible on the Wi-Fi."),
            isDeveloper: true),
    ]
}
