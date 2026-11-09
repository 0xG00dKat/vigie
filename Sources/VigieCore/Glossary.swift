import Foundation

/// Le glossaire de « Comprendre mon Mac » : les mots que Vigie (et macOS) emploient, en une phrase chacun.
public struct GlossaryTerm: Sendable, Identifiable, Equatable {
    public var id: String { term.fr }
    public var term: L
    public var definition: L
    /// Explication à lire pour aller plus loin.
    public var lesson: String?
    public var isDeveloper: Bool = false
}

public enum Glossary {
    public static func visible(developer: Bool) -> [GlossaryTerm] {
        terms.filter { developer || !$0.isDeveloper }.sorted { $0.term.text.localizedCompare($1.term.text) == .orderedAscending }
    }

    public static let terms: [GlossaryTerm] = [
        GlossaryTerm(term: L("Mémoire (RAM)", "Memory (RAM)"), definition: L("Le plan de travail du Mac : ce qui est ouvert y est posé pour aller vite. Elle se vide à l'extinction.", "The Mac's workbench: whatever is open sits on it to be fast. It empties when the Mac turns off."), lesson: "memoire"),
        GlossaryTerm(term: L("Disque (stockage)", "Disk (storage)"), definition: L("L'armoire du Mac : tes fichiers, tes apps et macOS, gardés même éteint.", "The Mac's cupboard: your files, apps and macOS, kept even when off."), lesson: "memoire-vs-disque"),
        GlossaryTerm(term: L("Processeur (CPU)", "Processor (CPU)"), definition: L("Ce qui fait les calculs. Il a plusieurs cœurs qui travaillent en même temps.", "What does the computing. It has several cores working at the same time."), lesson: "processeur"),
        GlossaryTerm(term: L("Cœur", "Core"), definition: L("Une partie du processeur capable de travailler seule. 100 % = un cœur occupé à fond.", "A part of the processor that can work on its own. 100% = one core fully busy."), lesson: "processeur"),
        GlossaryTerm(term: L("Swap", "Swap"), definition: L("Ce que le Mac range sur le disque quand la mémoire est pleine. Lent : beaucoup de swap = Mac poussif.", "What the Mac moves to the disk when memory is full. Slow: lots of swap = sluggish Mac."), lesson: "swap"),
        GlossaryTerm(term: L("Pression de la mémoire", "Memory pressure"), definition: L("Ce que macOS pense de sa mémoire : assez, un peu juste, ou il en manque. Plus parlant que le nombre de Go.", "What macOS thinks of its memory: enough, a bit tight, or not enough. More telling than the number of GB."), lesson: "memoire"),
        GlossaryTerm(term: L("Processus", "Process"), definition: L("Un programme en train de tourner. Une app en lance souvent plusieurs (un par onglet, par extension…).", "A program that's running. An app often starts several (one per tab, per extension…)."), lesson: "processus"),
        GlossaryTerm(term: L("Cache", "Cache"), definition: L("Une copie gardée pour aller plus vite la fois suivante. Se recrée tout seul : le vider ne fait rien perdre.", "A copy kept to be faster next time. Rebuilds itself: clearing it loses nothing."), lesson: "caches"),
        GlossaryTerm(term: L("Données système", "System Data"), definition: L("La case grise des Réglages : caches, sauvegardes, mises à jour, fichiers de macOS.", "The grey box in Settings: caches, backups, updates, macOS files."), lesson: "donnees-systeme"),
        GlossaryTerm(term: L("Agent de lancement", "Launch agent"), definition: L("Un petit programme qui démarre avec ta session : mises à jour, icône de la barre des menus, synchronisation.", "A small program that starts with your session: updates, menu bar icon, sync."), lesson: "demarrage"),
        GlossaryTerm(term: L("Instantané Time Machine", "Time Machine snapshot"), definition: L("Une sauvegarde de secours gardée sur le Mac. S'efface seule au bout de 24 h ou quand la place manque.", "A backup copy kept on the Mac. Deletes itself after 24 h or when space runs low."), lesson: "time-machine"),
        GlossaryTerm(term: L("Cycle de batterie", "Battery cycle"), definition: L("100 % de charge utilisés, en une ou plusieurs fois. La batterie s'use avec les cycles.", "100% of charge used, in one go or several. The battery wears with cycles."), lesson: "batterie"),
        GlossaryTerm(term: L("Veille", "Sleep"), definition: L("Le Mac s'endort pour économiser l'énergie. Une app peut l'en empêcher (vidéo, appel, téléchargement).", "The Mac goes to sleep to save energy. An app can prevent it (video, call, download)."), lesson: "veille"),
        GlossaryTerm(term: L("Corbeille", "Trash"), definition: L("Là où vont les fichiers supprimés. La place ne revient qu'une fois vidée.", "Where deleted files go. The space only comes back once it's emptied."), lesson: "corbeille"),
        GlossaryTerm(term: L("iCloud Drive", "iCloud Drive"), definition: L("Tes fichiers dans le cloud d'Apple, synchronisés entre tes appareils. Supprimer ici supprime partout.", "Your files in Apple's cloud, synced across your devices. Deleting here deletes everywhere."), lesson: "icloud"),
        GlossaryTerm(term: L("Electron", "Electron"), definition: L("Ce qui fait tourner beaucoup d'apps (Slack, VS Code…) comme des sites web, avec leur propre navigateur.", "What runs many apps (Slack, VS Code…) like websites, with their own browser."), lesson: "apps-web"),
        GlossaryTerm(term: L("Port", "Port"), definition: L("Le numéro sur lequel un serveur attend des connexions (3000, 8080…). Un seul programme par port.", "The number a server waits for connections on (3000, 8080…). One program per port."), lesson: "ports", isDeveloper: true),
        GlossaryTerm(term: L("localhost (127.0.0.1)", "localhost (127.0.0.1)"), definition: L("L'adresse de ce Mac pour lui-même : un serveur qui y écoute n'est joignable que d'ici.", "This Mac's address for itself: a server listening there is only reachable from here."), lesson: "ports", isDeveloper: true),
        GlossaryTerm(term: L("node_modules", "node_modules"), definition: L("Les dépendances d'un projet JavaScript, une copie par projet. Se réinstallent avec « npm install ».", "A JavaScript project's dependencies, one copy per project. Reinstall with “npm install”."), lesson: "node-modules", isDeveloper: true),
        GlossaryTerm(term: L("Conteneur Docker", "Docker container"), definition: L("Un programme isolé avec tout ce qu'il lui faut (une base de données, un serveur…), lancé par Docker.", "An isolated program with everything it needs (a database, a server…), run by Docker."), lesson: "docker-disque", isDeveloper: true),
    ]
}
