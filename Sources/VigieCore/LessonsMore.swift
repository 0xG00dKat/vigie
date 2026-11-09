import Foundation

extension Lessons {
    /// Les bases : ce qu'il faut savoir d'un Mac avant tout le reste.
    static let basics: [Lesson] = [
        Lesson(
            id: "bases-mac", symbol: "cpu",
            title: L("Les trois pièces d'un Mac", "The three parts of a Mac"),
            summary: L("Le processeur calcule, la mémoire garde sous la main, le disque range.", "The processor computes, memory keeps things at hand, the disk stores."),
            paragraphs: [
                L("Un Mac tient sur trois pièces. Le processeur fait les calculs : il exécute les apps. La mémoire (RAM) est le plan de travail : ce qui est ouvert y est posé pour aller vite. Le disque est l'armoire : tes fichiers, tes apps et macOS y restent même éteint.",
                  "A Mac rests on three parts. The processor does the computing: it runs apps. Memory (RAM) is the workbench: whatever is open sits on it to be fast. The disk is the cupboard: your files, apps and macOS stay there even when it's off."),
                L("Quand le Mac rame, c'est presque toujours l'une des trois qui sature : un processeur occupé par une app qui s'emballe, une mémoire trop pleine, ou un disque presque plein (macOS a besoin de place libre pour travailler).",
                  "When the Mac is sluggish, it's almost always one of the three running out: a processor kept busy by a runaway app, memory too full, or a nearly full disk (macOS needs free space to work)."),
                L("Vigie montre les trois : « Ce qui tourne » et « Vitesse » pour le processeur et la mémoire, « Stockage » pour le disque.",
                  "Vigie shows all three: “Running” and “Speed” for the processor and memory, “Storage” for the disk."),
            ],
            takeaway: L("Processeur = calculer, mémoire = sous la main, disque = rangé.", "Processor = compute, memory = at hand, disk = stored.")),
        Lesson(
            id: "memoire-vs-disque", symbol: "memorychip",
            title: L("Mémoire ou stockage : pas la même chose", "Memory or storage: not the same thing"),
            summary: L("« 16 Go » de mémoire et « 512 Go » de disque ne parlent pas de la même chose.", "“16 GB” of memory and “512 GB” of disk aren't the same thing."),
            paragraphs: [
                L("La mémoire se vide quand tu éteins le Mac : elle ne sert qu'à ce qui est ouvert. Le disque garde tout, même éteint. Les deux se comptent en gigaoctets, d'où la confusion.",
                  "Memory empties when you turn the Mac off: it only holds what's open. The disk keeps everything, even when off. Both are counted in gigabytes, hence the confusion."),
                L("Supprimer des fichiers libère le disque, pas la mémoire. Quitter des apps libère la mémoire, pas le disque. Vigie sépare les deux : « Processus » pour la mémoire, « Stockage » pour le disque.",
                  "Deleting files frees the disk, not memory. Quitting apps frees memory, not the disk. Vigie keeps them apart: “Processes” for memory, “Storage” for the disk."),
            ],
            takeaway: L("Ranger des fichiers ne rend pas le Mac plus rapide ; quitter des apps, si.", "Tidying files doesn't make the Mac faster; quitting apps does.")),
        Lesson(
            id: "quitter-vs-fermer", symbol: "xmark",
            title: L("Fermer une fenêtre ou quitter une app", "Closing a window or quitting an app"),
            summary: L("Sur Mac, fermer la fenêtre laisse souvent l'app ouverte.", "On a Mac, closing the window often leaves the app open."),
            paragraphs: [
                L("Le bouton rouge ferme la fenêtre, pas toujours l'app : Mail, Safari, Slack ou Spotify continuent de tourner, avec leur point sous l'icône du Dock. Elles gardent leur mémoire.",
                  "The red button closes the window, not always the app: Mail, Safari, Slack or Spotify keep running, with their dot under the Dock icon. They keep their memory."),
                L("Pour vraiment quitter : ⌘Q, ou le menu de l'app › Quitter, ou le × de Vigie. Les apps qui ne servent plus libèrent alors leur mémoire tout de suite.",
                  "To really quit: ⌘Q, or the app's menu › Quit, or Vigie's ×. Apps you're not using then free their memory right away."),
            ],
            takeaway: L("Un point sous l'icône du Dock = l'app tourne encore. ⌘Q pour la quitter.", "A dot under the Dock icon = the app is still running. ⌘Q to quit it.")),
        Lesson(
            id: "redemarrer", symbol: "power",
            title: L("Pourquoi redémarrer aide", "Why restarting helps"),
            summary: L("Un redémarrage remet tout à zéro : mémoire, petits programmes, fichiers temporaires.", "A restart resets everything: memory, small programs, temporary files."),
            paragraphs: [
                L("Avec le temps, des petits programmes restent en route, des apps grossissent en mémoire et des fichiers temporaires s'accumulent. Le Mac ne les remet pas tous à zéro tout seul.",
                  "Over time, small programs keep running, apps grow in memory and temporary files pile up. The Mac doesn't reset them all on its own."),
                L("Redémarrer vide la mémoire, relance proprement ce qui doit tourner et fait le ménage des fichiers temporaires. Une fois par semaine ou deux suffit ; après une mise à jour, c'est obligatoire.",
                  "Restarting empties memory, cleanly restarts what needs to run and clears temporary files. Once every week or two is enough; after an update it's required."),
            ],
            takeaway: L("Mac poussif depuis des jours ? Redémarre avant de chercher plus loin.", "Mac sluggish for days? Restart before looking further.")),
        Lesson(
            id: "mises-a-jour", symbol: "arrow.down.circle",
            title: L("Les mises à jour de macOS", "macOS updates"),
            summary: L("Elles corrigent des failles de sécurité : à faire, mais au bon moment.", "They fix security holes: do them, but at the right time."),
            paragraphs: [
                L("Les mises à jour de macOS corrigent surtout des failles de sécurité et des bugs. Elles se téléchargent en arrière-plan (plusieurs gigaoctets) puis demandent un redémarrage.",
                  "macOS updates mostly fix security holes and bugs. They download in the background (several gigabytes) and then ask for a restart."),
                L("Réglages Système › Général › Mise à jour logicielle dit si une version attend. Le téléchargement compte dans les « Données système » jusqu'à l'installation.",
                  "System Settings › General › Software Update tells you whether a version is waiting. The download counts in “System Data” until it's installed."),
            ],
            takeaway: L("Une mise à jour en attente prend de la place : installe-la quand tu peux redémarrer.", "A pending update takes up space: install it when you can restart.")),
        Lesson(
            id: "forcer-a-quitter", symbol: "exclamationmark.triangle",
            title: L("Quand une app ne répond plus", "When an app stops responding"),
            summary: L("La roue qui tourne, puis « Forcer à quitter ».", "The spinning wheel, then “Force Quit”."),
            paragraphs: [
                L("La roue multicolore veut dire que l'app est occupée. Souvent, elle finit son travail toute seule en quelques secondes : attends un peu.",
                  "The spinning wheel means the app is busy. Often it finishes on its own within seconds: wait a little."),
                L("Si rien ne bouge, ⌥⌘Échap ouvre « Forcer à quitter ». Vigie fait pareil : d'abord une fermeture normale, puis « Forcer » si rien ne se passe. Forcer peut perdre ce qui n'était pas enregistré.",
                  "If nothing moves, ⌥⌘Esc opens “Force Quit”. Vigie does the same: a normal quit first, then “Force” if nothing happens. Forcing can lose unsaved work."),
            ],
            takeaway: L("Attends quelques secondes, puis force. Jamais l'inverse.", "Wait a few seconds, then force. Never the other way round.")),
        Lesson(
            id: "telechargements", symbol: "folder",
            title: L("Où vont tes téléchargements", "Where your downloads go"),
            summary: L("Dans le dossier Téléchargements, qui ne se vide jamais tout seul.", "Into the Downloads folder, which never empties on its own."),
            paragraphs: [
                L("Tout ce que tu télécharges va dans Téléchargements, et y reste : installeurs déjà installés, PDF lus une fois, vidéos, archives. C'est souvent l'un des plus gros dossiers du Mac.",
                  "Everything you download goes into Downloads, and stays there: installers already installed, PDFs read once, videos, archives. It's often one of the biggest folders on the Mac."),
                L("Un installeur (.dmg, .pkg) ne sert plus une fois l'app installée. Vigie montre les gros fichiers pas ouverts depuis six mois : ils sont souvent là.",
                  "An installer (.dmg, .pkg) is useless once the app is installed. Vigie shows large files not opened in six months: they're often there."),
            ],
            takeaway: L("Un .dmg déjà installé peut aller à la corbeille.", "A .dmg you've already installed can go to the Trash.")),
    ]

    /// Les nouvelles explications : chaleur, processeur, veille, iCloud, Time Machine, apps web, onglets, et deux pour les développeurs.
    static let more: [Lesson] = [
        Lesson(
            id: "processeur", symbol: "gauge.with.needle",
            title: L("« 100 % de processeur », ça veut dire quoi ?", "What does “100% CPU” mean?"),
            summary: L("Un cœur occupé à fond. Un Mac en a plusieurs, d'où des 300 %.", "One core fully busy. A Mac has several, hence 300%."),
            paragraphs: [
                L("Le processeur a plusieurs cœurs, qui travaillent en même temps. Le Moniteur d'activité compte 100 % par cœur : une app qui en occupe trois affiche 300 %.",
                  "The processor has several cores working at the same time. Activity Monitor counts 100% per core: an app using three of them shows 300%."),
                L("Un pic pendant un export ou une compilation est normal. Une app qui reste au-dessus de 50 % sans rien faire de visible s'est sans doute emballée : Vigie la repère et propose de la quitter.",
                  "A spike during an export or a build is normal. An app staying above 50% while doing nothing visible has probably run away: Vigie spots it and offers to quit it."),
            ],
            takeaway: L("Un pic, c'est normal. Des minutes à fond sans raison, non.", "A spike is normal. Minutes at full load for no reason isn't.")),
        Lesson(
            id: "chaleur", symbol: "thermometer.medium",
            title: L("Pourquoi ton Mac chauffe", "Why your Mac gets hot"),
            summary: L("Le processeur travaille, le Mac évacue la chaleur, et ralentit s'il le faut.", "The processor works, the Mac gets rid of the heat, and slows down if needed."),
            paragraphs: [
                L("Plus le processeur travaille, plus il chauffe. Le Mac évacue la chaleur par ses ventilateurs (ou par sa coque sur un MacBook Air). S'il ne suffit plus, macOS ralentit le processeur pour se protéger : c'est le moment où tout devient lent.",
                  "The harder the processor works, the hotter it gets. The Mac gets rid of the heat through its fans (or its case on a MacBook Air). If that's not enough, macOS slows the processor down to protect itself: that's when everything gets slow."),
                L("Les causes habituelles : une app qui s'emballe, une vidéo ou un appel en visio, une compilation, ou un Mac posé sur un lit ou un canapé qui bouche l'air.",
                  "The usual causes: a runaway app, a video or video call, a build, or a Mac on a bed or sofa that blocks the air."),
            ],
            takeaway: L("Mac chaud et lent : regarde ce qui fait travailler le processeur dans Vitesse.", "Hot and slow Mac: check what keeps the processor busy in Speed.")),
        Lesson(
            id: "veille", symbol: "moon",
            title: L("Pourquoi le Mac ne se met pas en veille", "Why the Mac doesn't go to sleep"),
            summary: L("Une app peut l'en empêcher : une vidéo, un appel, un téléchargement.", "An app can prevent it: a video, a call, a download."),
            paragraphs: [
                L("Une app peut demander au Mac de rester éveillé : un lecteur vidéo, un appel en visio, un téléchargement, une sauvegarde. Tant qu'elle le demande, l'écran reste allumé ou le Mac ne s'endort pas.",
                  "An app can ask the Mac to stay awake: a video player, a video call, a download, a backup. As long as it asks, the screen stays on or the Mac doesn't sleep."),
                L("Parfois une app oublie de lever sa demande : la batterie fond pendant la nuit. Vigie montre qui empêche la veille, et depuis combien de temps, dans Vitesse et batterie.",
                  "Sometimes an app forgets to lift its request: the battery drains overnight. Vigie shows who prevents sleep, and for how long, in Speed and battery."),
            ],
            takeaway: L("Batterie vide au réveil ? Une app a sans doute gardé le Mac éveillé.", "Empty battery in the morning? An app probably kept the Mac awake.")),
        Lesson(
            id: "icloud", symbol: "icloud",
            title: L("iCloud et « Optimiser le stockage »", "iCloud and “Optimize Storage”"),
            summary: L("Tes fichiers peuvent être dans le cloud, sur le Mac, ou les deux.", "Your files can be in the cloud, on the Mac, or both."),
            paragraphs: [
                L("Avec iCloud Drive et « Optimiser le stockage », macOS garde dans le cloud les fichiers que tu n'ouvres pas et ne laisse sur le Mac qu'un raccourci (le petit nuage). Ils se téléchargent quand tu les ouvres.",
                  "With iCloud Drive and “Optimize Storage”, macOS keeps the files you don't open in the cloud and leaves only a shortcut on the Mac (the little cloud). They download when you open them."),
                L("Supprimer un fichier iCloud le supprime partout, sur tous tes appareils. Pour libérer de la place sans rien perdre, mieux vaut laisser macOS les envoyer au cloud.",
                  "Deleting an iCloud file deletes it everywhere, on all your devices. To free up space without losing anything, it's better to let macOS send them to the cloud."),
            ],
            takeaway: L("Un fichier iCloud supprimé l'est partout.", "A deleted iCloud file is gone everywhere.")),
        Lesson(
            id: "time-machine", symbol: "clock.arrow.circlepath",
            title: L("Les instantanés Time Machine", "Time Machine snapshots"),
            summary: L("Des sauvegardes de secours gardées sur le Mac, qui s'effacent seules.", "Backup copies kept on the Mac, which delete themselves."),
            paragraphs: [
                L("Si tu utilises Time Machine, macOS garde aussi des « instantanés » sur le disque du Mac, pour revenir en arrière même sans le disque de sauvegarde. Ils comptent dans la place occupée.",
                  "If you use Time Machine, macOS also keeps “snapshots” on the Mac's disk, to go back in time even without the backup drive. They count in the space used."),
                L("Ils s'effacent tout seuls au bout de 24 heures, ou plus tôt si la place manque. Rien à faire : c'est juste à savoir quand le disque paraît plus plein qu'il ne devrait.",
                  "They delete themselves after 24 hours, or sooner if space runs low. Nothing to do: it's just worth knowing when the disk looks fuller than it should."),
            ],
            takeaway: L("Les instantanés rendent leur place tout seuls.", "Snapshots give their space back on their own.")),
        Lesson(
            id: "apps-web", symbol: "square.grid.2x2",
            title: L("Pourquoi Slack, Discord ou VS Code prennent autant de mémoire", "Why Slack, Discord or VS Code use so much memory"),
            summary: L("Ce sont des navigateurs web déguisés en apps.", "They're web browsers dressed up as apps."),
            paragraphs: [
                L("Beaucoup d'apps (Slack, Discord, Notion, VS Code, Figma, Spotify…) sont construites comme des sites web, avec leur propre navigateur intégré (Electron). Chacune embarque donc un navigateur entier, avec ses processus d'aide.",
                  "Many apps (Slack, Discord, Notion, VS Code, Figma, Spotify…) are built like websites, with their own built-in browser (Electron). Each one carries a whole browser, with its helper processes."),
                L("C'est pour ça qu'une messagerie peut prendre 1 ou 2 Go. Les quitter quand tu ne t'en sers pas, ou utiliser leur version dans le navigateur, libère beaucoup de mémoire.",
                  "That's why a chat app can use 1 or 2 GB. Quitting them when you don't need them, or using their browser version, frees a lot of memory."),
            ],
            takeaway: L("Une app web = un navigateur de plus en mémoire.", "A web app = one more browser in memory.")),
        Lesson(
            id: "onglets", symbol: "globe",
            title: L("Les onglets du navigateur et la mémoire", "Browser tabs and memory"),
            summary: L("Chaque onglet est un petit programme à part.", "Every tab is a separate little program."),
            paragraphs: [
                L("Safari, Chrome, Brave ou Arc ouvrent un processus par onglet (et par extension) : si un site plante, les autres continuent. Mais chaque onglet garde sa mémoire, même en arrière-plan.",
                  "Safari, Chrome, Brave or Arc open one process per tab (and per extension): if a site crashes, the others keep going. But every tab keeps its memory, even in the background."),
                L("Les sites lourds (vidéo, mails, outils en ligne) peuvent prendre plusieurs centaines de mégaoctets chacun. Fermer les onglets qui ne servent plus est souvent le moyen le plus simple d'alléger le Mac.",
                  "Heavy sites (video, mail, online tools) can take several hundred megabytes each. Closing the tabs you no longer need is often the simplest way to lighten the Mac."),
            ],
            takeaway: L("Trente onglets ouverts, c'est trente petits programmes.", "Thirty open tabs are thirty little programs.")),
        Lesson(
            id: "node-modules", symbol: "shippingbox",
            title: L("node_modules et les dépendances", "node_modules and dependencies"),
            summary: L("Chaque projet JavaScript a sa copie de ses dépendances.", "Every JavaScript project has its own copy of its dependencies."),
            paragraphs: [
                L("« npm install » télécharge les dépendances d'un projet dans son dossier node_modules : souvent des centaines de mégaoctets, et une copie par projet. Les compilations (dist, .next, build) s'y ajoutent.",
                  "“npm install” downloads a project's dependencies into its node_modules folder: often hundreds of megabytes, and one copy per project. Builds (dist, .next, build) add to that."),
                L("Tout ça se recrée : un projet endormi peut perdre ses node_modules sans risque, « npm install » les remet. pnpm partage les dépendances entre projets et prend moins de place.",
                  "All of it can be rebuilt: a dormant project can lose its node_modules safely, “npm install” brings them back. pnpm shares dependencies across projects and takes less space."),
            ],
            takeaway: L("node_modules se réinstalle ; ton code, non. Vigie ne touche qu'au premier.", "node_modules reinstalls; your code doesn't. Vigie only touches the first."),
            isDeveloper: true),
        Lesson(
            id: "docker-disque", symbol: "shippingbox",
            title: L("Le disque de Docker ne rétrécit pas tout seul", "Docker's disk doesn't shrink on its own"),
            summary: L("Docker range tout dans un grand fichier qui grossit, sans maigrir.", "Docker keeps everything in one big file that grows but doesn't shrink."),
            paragraphs: [
                L("Sur Mac, Docker range images, conteneurs, volumes et cache dans un disque virtuel (un seul gros fichier). Il grossit à mesure, jusqu'à la taille maximale réglée dans Docker.",
                  "On a Mac, Docker keeps images, containers, volumes and cache in a virtual disk (one big file). It grows as needed, up to the maximum size set in Docker."),
                L("« docker builder prune » et « docker image prune » libèrent de la place dans ce disque. Vigie ne supprime rien elle-même : elle montre ce qui se récupère et donne la commande à copier.",
                  "“docker builder prune” and “docker image prune” free up space inside that disk. Vigie never deletes anything itself: it shows what can be reclaimed and gives the command to copy."),
            ],
            takeaway: L("Le cache de construction est souvent le plus gros, et sans risque.", "The build cache is often the biggest, and safe to clear."),
            isDeveloper: true),
    ]
}
