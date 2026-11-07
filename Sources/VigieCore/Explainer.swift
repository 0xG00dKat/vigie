import Foundation

/// Explications en langage simple (français et anglais), tirées d'une liste intégrée.
/// Pour le reste, l'interface propose « Demander à Claude ».
public enum Explainer {
    // MARK: - Apps

    static let browser = L(
        "Navigateur web : un processus par onglet, extension et pour le GPU, d'où leur nombre. Les onglets reviennent à la réouverture.",
        "Web browser: one process per tab, extension and for the GPU, hence the count. Tabs come back when you reopen it."
    )
    static let editor = L(
        "Éditeur de code : extensions, terminaux et serveurs de langage ont chacun leur processus. Le quitter arrête ses terminaux.",
        "Code editor: extensions, terminals and language servers each get their own process. Quitting it stops its terminals."
    )
    static let terminal = L(
        "Terminal. Le quitter arrête ce qui tourne dedans, serveurs de dev compris.",
        "Terminal. Quitting it stops whatever runs inside, dev servers included."
    )
    static let cloudSync = L(
        "Synchronise tes fichiers avec le cloud. Le quitter met la synchronisation en pause jusqu'à sa réouverture.",
        "Syncs your files with the cloud. Quitting it pauses syncing until you reopen it."
    )
    static let messaging = L(
        "Messagerie. La quitter coupe l'arrivée des nouveaux messages et des notifications.",
        "Messaging app. Quitting it stops new messages and notifications."
    )
    static let jetbrains = L(
        "Environnement de développement JetBrains. Le quitter arrête aussi ses terminaux et ses outils.",
        "JetBrains IDE. Quitting it also stops its terminals and tools."
    )
    static let docker = L(
        "Docker Desktop : fait tourner des conteneurs (bases de données, serveurs…). Le quitter arrête tous les conteneurs en cours.",
        "Docker Desktop: runs containers (databases, servers…). Quitting it stops every running container."
    )
    static let simulatorService = L(
        "Service des simulateurs iPhone de Xcode. Il reste ouvert après usage ; le fermer est sans risque.",
        "Xcode's iPhone simulator service. It stays open after use; closing it is safe."
    )
    static let chatGPT = L("App de bureau ChatGPT.", "ChatGPT desktop app.")
    static let launcher = L("lanceur d'apps et raccourcis.", "app launcher and shortcuts.")
    static let passwords = L("gestionnaire de mots de passe.", "password manager.")

    static let appsByID: [String: L] = [
        // Navigateurs
        "com.operasoftware.Opera": browser,
        "com.operasoftware.OperaGX": browser,
        "app.zen-browser.zen": browser,
        "com.brave.Browser": browser,
        "com.google.Chrome": browser,
        "com.google.Chrome.canary": browser,
        "org.mozilla.firefox": browser,
        "org.mozilla.firefoxdeveloperedition": browser,
        "com.apple.Safari": browser,
        "company.thebrowser.Browser": browser,
        "company.thebrowser.dia": browser,
        "com.microsoft.edgemac": browser,
        "com.vivaldi.Vivaldi": browser,
        "org.chromium.Chromium": browser,
        "ai.perplexity.comet": browser,
        "com.openai.atlas": browser,
        // Éditeurs et outils de dev
        "com.microsoft.VSCode": editor,
        "com.microsoft.VSCodeInsiders": editor,
        "com.todesktop.230313mzl4w4u92": editor,
        "dev.zed.Zed": editor,
        "com.exafunction.windsurf": editor,
        "com.sublimetext.4": editor,
        "com.apple.dt.Xcode": L(
            "Xcode, l'environnement d'Apple pour créer des apps iPhone et Mac. Il lance aussi le simulateur et des outils de compilation.",
            "Xcode, Apple's environment for building iPhone and Mac apps. It also launches the simulator and build tools."
        ),
        "com.apple.CoreSimulator.CoreSimulatorService": simulatorService,
        "com.apple.CoreSimulator.SimulatorTrampoline": L("Service des simulateurs iPhone de Xcode.", "Xcode's iPhone simulator service."),
        "com.apple.iphonesimulator": L(
            "Simulateur iPhone/iPad de Xcode. Le quitter éteint les appareils simulés.",
            "Xcode's iPhone/iPad simulator. Quitting it shuts down the simulated devices."
        ),
        "com.docker.docker": docker,
        "dev.orbstack.OrbStack": L(
            "OrbStack : fait tourner des conteneurs Docker et des machines Linux. Le quitter les arrête.",
            "OrbStack: runs Docker containers and Linux machines. Quitting it stops them."
        ),
        "com.postmanlabs.mac": L("Postman : outil pour tester des API.", "Postman: a tool for testing APIs."),
        "com.tinyapp.TablePlus": L("TablePlus : client de bases de données.", "TablePlus: a database client."),
        // Terminaux
        "com.apple.Terminal": terminal,
        "com.googlecode.iterm2": terminal,
        "dev.warp.Warp-Stable": terminal,
        "com.mitchellh.ghostty": terminal,
        "net.kovidgoyal.kitty": terminal,
        "com.github.wez.wezterm": terminal,
        // IA
        "com.anthropic.claudefordesktop": L(
            "App de bureau Claude. Ses sessions Claude Code sont rangées dans « Dev & terminal » ; la quitter les arrête.",
            "Claude desktop app. Its Claude Code sessions are listed under “Dev & terminal”; quitting it stops them."
        ),
        "com.openai.chat": chatGPT,
        "com.openai.codex": L(
            "App Codex d'OpenAI (agent de code). La quitter arrête ses tâches en cours.",
            "OpenAI's Codex app (coding agent). Quitting it stops its running tasks."
        ),
        // Communication
        "com.tinyspeck.slackmacgap": messaging,
        "com.hnc.Discord": messaging,
        "net.whatsapp.WhatsApp": messaging,
        "ru.keepcoder.Telegram": messaging,
        "com.apple.MobileSMS": messaging,
        "com.microsoft.teams2": messaging,
        "us.zoom.xos": L("Zoom : visioconférence. Le quitter coupe un appel en cours.", "Zoom: video calls. Quitting it ends a call in progress."),
        "com.apple.mail": L("Mail d'Apple. Le quitter coupe la réception des nouveaux e-mails.", "Apple Mail. Quitting it stops new email from arriving."),
        // Productivité
        "notion.id": L("Notion : notes et documents.", "Notion: notes and documents."),
        "md.obsidian": L("Obsidian : prise de notes.", "Obsidian: note-taking."),
        "com.linear": L("Linear : suivi des tickets et des projets.", "Linear: issue and project tracking."),
        "com.figma.Desktop": L("Figma : design d'interfaces.", "Figma: interface design."),
        "com.apple.Notes": L("Notes d'Apple.", "Apple Notes."),
        "com.apple.iCal": L("Calendrier d'Apple.", "Apple Calendar."),
        "com.apple.reminders": L("Rappels d'Apple.", "Apple Reminders."),
        "com.apple.Preview": L("Aperçu : affiche les PDF et les images.", "Preview: shows PDFs and images."),
        "com.apple.TextEdit": L("TextEdit : éditeur de texte d'Apple.", "TextEdit: Apple's text editor."),
        "com.apple.calculator": L("Calculette d'Apple.", "Apple Calculator."),
        "com.apple.ActivityMonitor": L("Moniteur d'activité : l'outil d'Apple que Vigie simplifie.", "Activity Monitor: the Apple tool Vigie simplifies."),
        "com.apple.systempreferences": L("Réglages Système.", "System Settings."),
        "com.apple.AppStore": L("App Store.", "App Store."),
        "com.apple.Music": L("Musique d'Apple.", "Apple Music."),
        "com.spotify.client": L("Spotify : musique.", "Spotify: music."),
        "com.apple.Photos": L("Photos d'Apple.", "Apple Photos."),
        "com.apple.finder": L(
            "Le Finder : le bureau, les fenêtres de fichiers et la corbeille. macOS le relance aussitôt : Vigie ne le ferme pas.",
            "The Finder: your desktop, file windows and Trash. macOS restarts it right away, so Vigie never closes it."
        ),
        // Synchronisation
        "com.getdropbox.dropbox": cloudSync,
        "com.google.drivefs": cloudSync,
        "com.microsoft.OneDrive": cloudSync,
        // Utilitaires
        "com.raycast.macos": L("Raycast : " + launcher.fr, "Raycast: " + launcher.en),
        "com.runningwithcrayons.Alfred": L("Alfred : " + launcher.fr, "Alfred: " + launcher.en),
        "com.knollsoft.Rectangle": L("Rectangle : range les fenêtres avec des raccourcis clavier.", "Rectangle: arranges windows with keyboard shortcuts."),
        "com.1password.1password": L("1Password : " + passwords.fr, "1Password: " + passwords.en),
        "com.bitwarden.desktop": L("Bitwarden : " + passwords.fr, "Bitwarden: " + passwords.en),
        "com.surteesstudios.Bartender": L("Bartender : range les icônes de la barre des menus.", "Bartender: organizes menu bar icons."),
        "pl.maketheweb.cleanshotx": L("CleanShot X : captures d'écran.", "CleanShot X: screenshots."),
    ]

    static let appsByName: [String: L] = [
        "kdrive": cloudSync,
        "dropbox": cloudSync,
        "google drive": cloudSync,
        "codexbar": L(
            "Petit utilitaire de la barre des menus qui affiche tes quotas d'utilisation de Codex et de Claude.",
            "Small menu bar utility that shows your Codex and Claude usage limits."
        ),
        "cursor": editor,
        "visual studio code": editor,
        "chatgpt": chatGPT,
        "docker": docker,
    ]

    static let appCategories: [String: L] = [
        "public.app-category.developer-tools": L("Outil de développement", "Developer tool"),
        "public.app-category.productivity": L("Productivité", "Productivity"),
        "public.app-category.utilities": L("Utilitaire", "Utility"),
        "public.app-category.social-networking": L("Communication", "Communication"),
        "public.app-category.business": L("Outil professionnel", "Business"),
        "public.app-category.music": L("Musique", "Music"),
        "public.app-category.video": L("Vidéo", "Video"),
        "public.app-category.graphics-design": L("Graphisme", "Graphics & design"),
        "public.app-category.photography": L("Photo", "Photography"),
        "public.app-category.entertainment": L("Divertissement", "Entertainment"),
        "public.app-category.education": L("Éducation", "Education"),
        "public.app-category.finance": L("Finance", "Finance"),
        "public.app-category.news": L("Actualités", "News"),
        "public.app-category.reference": L("Référence", "Reference"),
        "public.app-category.games": L("Jeu", "Game"),
        "public.app-category.lifestyle": L("Vie pratique", "Lifestyle"),
    ]

    public static func forApp(bundleID: String?, name: String, isBackground: Bool, info: BundleInfo?) -> Explanation {
        if let bundleID {
            if let text = appsByID[bundleID] { return Explanation(text.text) }
            if bundleID.hasPrefix("com.jetbrains.") { return Explanation(jetbrains.text) }
        }
        if let text = appsByName[name.lowercased()] { return Explanation(text.text) }

        var parts: [String] = []
        if let category = info?.category.flatMap({ appCategories[$0] }) {
            parts.append(category.text + ".")
        }
        if isBackground {
            parts.append(tr("Tourne en arrière-plan (barre des menus ou service), sans fenêtre dans le Dock.",
                            "Runs in the background (menu bar or service), with no window in the Dock."))
        } else {
            parts.append(tr("App ouverte. La quitter revient à faire ⌘Q.", "Open app. Quitting it is the same as pressing ⌘Q."))
        }
        return Explanation(parts.joined(separator: " "), isGeneric: true)
    }

    // MARK: - Dev

    static let languageServer = L(
        "Serveur de langage : autocomplétion et erreurs dans l'éditeur.",
        "Language server: autocomplete and errors in your editor."
    )
    static let terminalMultiplexer = L(
        "garde des sessions de terminal ouvertes en arrière-plan.",
        "keeps terminal sessions open in the background."
    )
    static let compiling = L("Compilation en cours.", "Build in progress.")

    static let devTools: [String: L] = [
        "claude": L("Claude Code : une session de l'agent en ligne de commande.", "Claude Code: a command-line agent session."),
        "codex": L("Codex (OpenAI) : une session de l'agent en ligne de commande.", "Codex (OpenAI): a command-line agent session."),
        "cursor-agent": L("Agent de Cursor en ligne de commande.", "Cursor's command-line agent."),
        "gemini": L("Gemini CLI : l'agent de Google en ligne de commande.", "Gemini CLI: Google's command-line agent."),
        "railway": L("CLI Railway : commande en cours (déploiement, logs…).", "Railway CLI: a command in progress (deploy, logs…)."),
        "caffeinate": L(
            "Empêche le Mac de se mettre en veille pendant une tâche (souvent lancé par Claude Code).",
            "Keeps the Mac awake during a task (often started by Claude Code)."
        ),
        "esbuild": L(
            "esbuild : compilateur JavaScript lancé par un serveur de dev (Vite, Astro…).",
            "esbuild: JavaScript bundler started by a dev server (Vite, Astro…)."
        ),
        "postgres": L("Base de données PostgreSQL locale.", "Local PostgreSQL database."),
        "redis-server": L("Base de données Redis locale.", "Local Redis database."),
        "mongod": L("Base de données MongoDB locale.", "Local MongoDB database."),
        "mysqld": L("Base de données MySQL locale.", "Local MySQL database."),
        "ollama": L(
            "Ollama : fait tourner des modèles d'IA en local (peut prendre beaucoup de mémoire).",
            "Ollama: runs AI models locally (can use a lot of memory)."
        ),
        "ssh": L("Connexion SSH vers une autre machine.", "SSH connection to another machine."),
        "git": L("Git : opération en cours sur un dépôt.", "Git: an operation in progress on a repository."),
        "gopls": languageServer,
        "rust-analyzer": languageServer,
        "sourcekit-lsp": L(
            "Serveur de langage Swift : autocomplétion et erreurs dans l'éditeur.",
            "Swift language server: autocomplete and errors in your editor."
        ),
        "clangd": L(
            "Serveur de langage C/C++ : autocomplétion et erreurs dans l'éditeur.",
            "C/C++ language server: autocomplete and errors in your editor."
        ),
        "ngrok": L("Tunnel : rend un serveur local accessible depuis Internet.", "Tunnel: makes a local server reachable from the internet."),
        "cloudflared": L(
            "Tunnel Cloudflare : rend un serveur local accessible depuis Internet.",
            "Cloudflare tunnel: makes a local server reachable from the internet."
        ),
        "docker": L("Commande Docker en cours.", "Docker command in progress."),
        "supabase": L("CLI Supabase.", "Supabase CLI."),
        "stripe": L("CLI Stripe (souvent l'écoute des webhooks en local).", "Stripe CLI (often listening for webhooks locally)."),
        "uv": L("uv : lance un outil Python (souvent un serveur MCP).", "uv: runs a Python tool (often an MCP server)."),
        "uvx": L("uvx : lance un outil Python (souvent un serveur MCP).", "uvx: runs a Python tool (often an MCP server)."),
        "tmux": L("tmux : " + terminalMultiplexer.fr, "tmux: " + terminalMultiplexer.en),
        "screen": L("screen : " + terminalMultiplexer.fr, "screen: " + terminalMultiplexer.en),
        "vim": L("Éditeur de texte dans le terminal.", "Text editor in the terminal."),
        "nvim": L("Éditeur de texte dans le terminal.", "Text editor in the terminal."),
        "gh": L("CLI GitHub.", "GitHub CLI."),
        "watchman": L(
            "Surveille les fichiers d'un projet pour relancer la compilation.",
            "Watches a project's files to trigger rebuilds."
        ),
        "swift-frontend": L("Compilation Swift en cours.", "Swift build in progress."),
        "swift-build": L("Compilation Swift en cours.", "Swift build in progress."),
        "xcodebuild": L("Compilation Xcode en cours.", "Xcode build in progress."),
        "clang": compiling,
        "make": compiling,
        "rsync": L("Copie de fichiers en cours.", "File copy in progress."),
        "curl": L("Téléchargement en cours.", "Download in progress."),
        "sqlite3": L("Base de données SQLite ouverte dans un terminal.", "SQLite database open in a terminal."),
        "java": L(
            "Java : souvent un serveur ou un outil (Gradle, serveur de langage…).",
            "Java: usually a server or a tool (Gradle, language server…)."
        ),
        "ruby": L("Ruby : un script ou un serveur.", "Ruby: a script or a server."),
        "php": L("PHP : un script ou un serveur.", "PHP: a script or a server."),
        "perl": L("Perl : un script.", "Perl: a script."),
        "com.apple.coresimulator.coresimulatorservice": simulatorService,
        "simulatortrampoline": L("Service des simulateurs iPhone de Xcode.", "Xcode's iPhone simulator service."),
    ]

    static let jsRuntimes: Set<String> = ["node", "bun", "deno", "tsx", "ts-node"]

    /// Nom d'outil de dev connu (utilisé pour reconnaître un outil empaqueté dans un .app).
    public static func isKnownDevTool(_ name: String) -> Bool {
        let lowered = name.lowercased()
        return devTools[lowered] != nil || jsRuntimes.contains(lowered) || lowered.hasPrefix("python")
    }

    /// Ce qu'est un processus de dev : sert à résumer un groupe sans dépendre de la langue.
    public enum DevKind: Equatable, Sendable {
        case mcpServer
        case claudeSession(fromApp: Bool)
        case other
    }

    public struct DevDescription: Equatable, Sendable {
        public var text: String
        public var isGeneric: Bool
        public var kind: DevKind
    }

    static let mcpServer = L(
        "Serveur MCP : donne des outils à un agent IA (Claude, Cursor…).",
        "MCP server: gives tools to an AI agent (Claude, Cursor…)."
    )

    private static func describe(_ text: L, generic: Bool = false, kind: DevKind = .other) -> DevDescription {
        DevDescription(text: text.text, isGeneric: generic, kind: kind)
    }

    /// Description d'un processus de dev, à partir de son nom et de ses arguments.
    public static func describeDevProcess(_ process: RawProcess) -> DevDescription {
        let name = process.name.lowercased()
        let arguments = process.arguments.dropFirst().joined(separator: " ").lowercased()

        if jsRuntimes.contains(name) {
            return describeJavaScript(arguments, runtime: name, process: process)
        }
        if name.hasPrefix("python") {
            return describePython(arguments, process: process)
        }
        if let text = devTools[name] {
            // Pour les agents, seule la sous-commande compte (`claude mcp serve`), pas une option comme --mcp-config.
            // Pour les autres outils (`railway mcp`, `uvx postgres-mcp`), toute mention de MCP suffit.
            let agents: Set<String> = ["claude", "codex", "cursor-agent", "gemini"]
            let subcommand = process.arguments.dropFirst().first { !$0.hasPrefix("-") }?.lowercased()
            if subcommand == "mcp" || (!agents.contains(name) && mentionsMCP(arguments)) {
                return describe(mcpServer, kind: .mcpServer)
            }
            if name == "claude" {
                let fromApp = arguments.contains("stream-json")
                let session = fromApp
                    ? L("Claude Code : une session ouverte dans l'app Claude.", "Claude Code: a session opened in the Claude app.")
                    : text
                return describe(session, kind: .claudeSession(fromApp: fromApp))
            }
            return describe(text)
        }
        if mentionsMCP(arguments) || mentionsMCP(name) {
            return describe(mcpServer, kind: .mcpServer)
        }
        if !process.listeningPorts.isEmpty {
            return describe(L("Serveur local.", "Local server."), generic: true)
        }
        return describe(L("Programme lancé depuis un terminal ou un outil de dev.", "Program started from a terminal or a dev tool."), generic: true)
    }

    static func mentionsMCP(_ text: String) -> Bool {
        if text.contains("modelcontextprotocol") { return true }
        let separators = CharacterSet(charactersIn: " /@._-:=")
        return text.components(separatedBy: separators).contains("mcp")
    }

    static let webDevServer = (fr: "site ou app web en local", en: "local website or web app")

    static func describeJavaScript(_ arguments: String, runtime: String, process: RawProcess) -> DevDescription {
        func has(_ needle: String) -> Bool { arguments.contains(needle) }
        func devServer(_ framework: String) -> DevDescription {
            describe(L("Serveur de dev \(framework) (\(webDevServer.fr)).", "\(framework) dev server (\(webDevServer.en))."))
        }
        let runtimeName: String
        switch runtime {
        case "bun": runtimeName = "Bun"
        case "deno": runtimeName = "Deno"
        default: runtimeName = "Node.js"
        }

        if has("@anthropic-ai/claude-code") || has("claude-code/cli") {
            return describe(devTools["claude"]!, kind: .claudeSession(fromApp: false))
        }
        if mentionsMCP(arguments) { return describe(mcpServer, kind: .mcpServer) }
        if has("astro") {
            return has(" dev") || has("preview")
                ? describe(L("Serveur de dev Astro (site web en local).", "Astro dev server (local website)."))
                : describe(L("Astro (outil de site web).", "Astro (website tool)."))
        }
        if has("vite") { return devServer("Vite") }
        if has("next dev") || has("next-server") || has("next/dist") || has("/next ") { return devServer("Next.js") }
        if has("nuxt") { return devServer("Nuxt") }
        if has("wrangler") { return describe(L("Wrangler : un Worker Cloudflare qui tourne en local.", "Wrangler: a Cloudflare Worker running locally.")) }
        if has("webpack") { return describe(L("Serveur webpack (\(webDevServer.fr)).", "webpack server (\(webDevServer.en)).")) }
        if has("storybook") { return describe(L("Storybook : catalogue de composants en local.", "Storybook: local component catalog.")) }
        if has("expo") || has("metro") { return describe(L("Expo / Metro : serveur de dev d'une app mobile.", "Expo / Metro: mobile app dev server.")) }
        if has("tsserver") || has("language-server") || has("languageserver") || has("langserver") || has("eslintserver") {
            return describe(languageServer)
        }
        if has("vitest") || has("jest") { return describe(L("Tests en cours.", "Tests running.")) }
        if has("nodemon") || has(" watch") || has("--watch") {
            return describe(L("Script relancé à chaque modification de fichier.", "Script that restarts on every file change."))
        }
        if has("playwright") || has("puppeteer") || has("chrome-devtools") {
            return describe(L("Pilote un navigateur (automatisation).", "Drives a browser (automation)."))
        }
        if has("tailwind") { return describe(L("Tailwind : compile le CSS en continu.", "Tailwind: rebuilds CSS continuously.")) }
        if has("prisma") { return describe(L("Prisma : outil de base de données.", "Prisma: database tool.")) }
        if has("npm-cli") || has("npm run") || has("npm exec") { return describe(L("npm : commande en cours.", "npm: command in progress.")) }
        if has("pnpm") { return describe(L("pnpm : commande en cours.", "pnpm: command in progress.")) }
        if has("yarn") { return describe(L("Yarn : commande en cours.", "Yarn: command in progress.")) }
        if !process.listeningPorts.isEmpty { return describe(L("Serveur \(runtimeName) local.", "Local \(runtimeName) server.")) }
        if let script = scriptName(process.arguments) {
            return describe(L("Script \(runtimeName) « \(script) ».", "\(runtimeName) script “\(script)”."), generic: true)
        }
        return describe(L(
            "\(runtimeName) : exécute du JavaScript (serveur, outil ou script).",
            "\(runtimeName): runs JavaScript (server, tool or script)."
        ), generic: true)
    }

    static func describePython(_ arguments: String, process: RawProcess) -> DevDescription {
        func has(_ needle: String) -> Bool { arguments.contains(needle) }
        if mentionsMCP(arguments) { return describe(mcpServer, kind: .mcpServer) }
        if has("http.server") {
            return describe(L("Petit serveur web Python (partage d'un dossier en local).", "Small Python web server (shares a folder locally)."))
        }
        if has("uvicorn") || has("gunicorn") || has("hypercorn") || has("fastapi") { return describe(L("Serveur web Python.", "Python web server.")) }
        if has("runserver") { return describe(L("Serveur de dev Django.", "Django dev server.")) }
        if has("flask") { return describe(L("Serveur de dev Flask.", "Flask dev server.")) }
        if has("streamlit") { return describe(L("App Streamlit en local.", "Local Streamlit app.")) }
        if has("jupyter") { return describe(L("Jupyter : carnets de code Python.", "Jupyter: Python notebooks.")) }
        if !process.listeningPorts.isEmpty { return describe(L("Serveur Python local.", "Local Python server.")) }
        if let script = scriptName(process.arguments) {
            return describe(L("Script Python « \(script) ».", "Python script “\(script)”."), generic: true)
        }
        return describe(L("Python : un script ou un outil.", "Python: a script or a tool."), generic: true)
    }

    /// Premier argument qui n'est pas une option : en général le script exécuté.
    static func scriptName(_ arguments: [String]) -> String? {
        guard let script = arguments.dropFirst().first(where: { !$0.hasPrefix("-") && !$0.isEmpty }) else { return nil }
        let name = PathRules.lastComponent(script)
        return name.isEmpty ? nil : name
    }

    public static func forDev(_ processes: [RawProcess]) -> Explanation {
        // Les serveurs (avec un port) d'abord : c'est ce qu'on cherche en général.
        let sorted = processes.sorted {
            if $0.listeningPorts.isEmpty != $1.listeningPorts.isEmpty { return !$0.listeningPorts.isEmpty }
            return ($0.memory ?? 0) > ($1.memory ?? 0)
        }
        var seen = Set<String>()
        var specific: [String] = []
        var generic: [String] = []
        var mcpPIDs = Set<Int32>()
        var mcpParents: [Int32: Int32] = [:]
        var sessions: [Bool] = []
        for process in sorted where !["zsh", "bash", "sh", "fish", "login"].contains(process.name) {
            let description = describeDevProcess(process)
            // Les serveurs MCP et les sessions Claude Code sont comptés plutôt que répétés.
            switch description.kind {
            case .mcpServer:
                mcpPIDs.insert(process.pid)
                mcpParents[process.pid] = process.ppid
                continue
            case .claudeSession(let fromApp):
                sessions.append(fromApp)
                continue
            case .other:
                break
            }
            guard seen.insert(description.text).inserted else { continue }
            if description.isGeneric {
                generic.append(description.text)
            } else {
                specific.append(description.text)
            }
        }
        // `node railway mcp` lance `railway mcp` : un seul serveur.
        let mcpServers = mcpPIDs.filter { !mcpPIDs.contains(mcpParents[$0] ?? 0) }.count

        var parts = (specific.isEmpty ? generic : specific).prefix(2).map { $0.hasSuffix(".") ? String($0.dropLast()) : $0 }
        if sessions.count > 1 {
            parts.append(tr("\(sessions.count) sessions Claude Code", "\(sessions.count) Claude Code sessions"))
        } else if let fromApp = sessions.first {
            parts.append(fromApp
                ? tr("Session Claude Code (app Claude)", "Claude Code session (Claude app)")
                : tr("Session Claude Code", "Claude Code session"))
        }
        if mcpServers > 0 {
            parts.append(mcpServers == 1
                ? tr("1 serveur MCP (outils de l'agent)", "1 MCP server (agent tools)")
                : tr("\(mcpServers) serveurs MCP (outils de l'agent)", "\(mcpServers) MCP servers (agent tools)"))
        }
        if parts.isEmpty {
            return Explanation(tr("Terminal ouvert dans ce dossier.", "Terminal open in this folder."), isGeneric: true)
        }
        if let first = parts.first, let initial = first.first {
            parts[0] = initial.uppercased() + first.dropFirst()
        }
        let isGeneric = specific.isEmpty && sessions.isEmpty && mcpServers == 0
        return Explanation(parts.joined(separator: " · ") + ".", isGeneric: isGeneric)
    }

    /// Une ligne courte pour un sous-processus : script et options principales, secrets masqués.
    public static func commandSummary(_ process: RawProcess) -> String? {
        guard process.arguments.count > 1 else { return nil }
        let parts = maskSecrets(Array(process.arguments.dropFirst())).map { argument -> String in
            argument.hasPrefix("/") ? PathRules.lastComponent(argument) : argument
        }
        let line = parts.joined(separator: " ")
        return line.count > 120 ? String(line.prefix(120)) + "…" : line
    }

    static let secretWords = ["key", "token", "secret", "password", "passwd", "auth", "credential", "bearer"]

    /// Masque les valeurs qui ressemblent à des secrets (`--api-key xxx`, `TOKEN=xxx`, `sk-…`),
    /// pour qu'un partage d'écran n'expose rien.
    public static func maskSecrets(_ arguments: [String]) -> [String] {
        var result: [String] = []
        var maskNext = false
        for argument in arguments {
            if maskNext && !argument.hasPrefix("-") {
                result.append("••••")
                maskNext = false
                continue
            }
            maskNext = false
            let lowered = argument.lowercased()
            if argument.hasPrefix("-") {
                if let equals = argument.firstIndex(of: "=") {
                    let name = lowered[..<equals]
                    if secretWords.contains(where: name.contains) {
                        result.append(String(argument[...equals]) + "••••")
                        continue
                    }
                } else if secretWords.contains(where: lowered.contains) {
                    maskNext = true
                }
                result.append(argument)
            } else if let equals = argument.firstIndex(of: "="), secretWords.contains(where: lowered[..<equals].contains) {
                result.append(String(argument[...equals]) + "••••")
            } else if looksLikeToken(argument) {
                result.append("••••")
            } else {
                result.append(argument)
            }
        }
        return result
    }

    static func looksLikeToken(_ value: String) -> Bool {
        let prefixes = ["sk-", "sk_", "pk_", "rk_", "ghp_", "gho_", "github_pat_", "xox", "crsr_", "AKIA", "eyJ"]
        if prefixes.contains(where: value.hasPrefix) && value.count >= 16 { return true }
        guard value.count >= 32, !value.contains("/"), !value.contains(".") else { return false }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let hasDigit = value.contains { $0.isNumber }
        let hasLetter = value.contains { $0.isLetter }
        return value.unicodeScalars.allSatisfy(allowed.contains) && hasDigit && hasLetter
    }

    // MARK: - Système

    static let spotlightIndex = L("Spotlight : indexe tes fichiers pour la recherche.", "Spotlight: indexes your files for search.")
    static let spotlightWorker = L(
        "Spotlight : lit tes fichiers pour la recherche. Normal d'en voir plusieurs.",
        "Spotlight: reads your files for search. Seeing several is normal."
    )
    static let quickLook = L("Aperçus de fichiers (barre d'espace).", "File previews (space bar).")
    static let wifi = L("Gère le Wi-Fi.", "Manages Wi-Fi.")
    static let shell = L("Shell : une fenêtre ou un onglet de terminal.", "Shell: a terminal window or tab.")

    static let system: [String: L] = [
        "kernel_task": L(
            "Le cœur de macOS. Il occupe aussi le processeur pour faire baisser la température quand le Mac chauffe.",
            "The core of macOS. It also occupies the CPU to bring the temperature down when the Mac heats up."
        ),
        "launchd": L(
            "Le tout premier processus de macOS : il démarre et surveille tous les autres.",
            "The very first macOS process: it starts and watches over all the others."
        ),
        "WindowServer": L("Dessine tout ce qui s'affiche à l'écran.", "Draws everything on your screen."),
        "loginwindow": L("Gère ta session ouverte.", "Manages your logged-in session."),
        "mds": spotlightIndex,
        "mds_stores": spotlightIndex,
        "mdworker": spotlightWorker,
        "mdworker_shared": spotlightWorker,
        "mdbulkimport": spotlightIndex,
        "corespotlightd": L("Spotlight : indexe le contenu des apps pour la recherche.", "Spotlight: indexes app content for search."),
        "Spotlight": L("La recherche Spotlight (⌘ Espace).", "Spotlight search (⌘ Space)."),
        "photoanalysisd": L(
            "Photos : analyse ta photothèque (visages, objets) quand le Mac est au repos.",
            "Photos: analyzes your library (faces, objects) while the Mac is idle."
        ),
        "mediaanalysisd": L(
            "Analyse photos et vidéos (texte, objets) quand le Mac est au repos.",
            "Analyzes photos and videos (text, objects) while the Mac is idle."
        ),
        "photolibraryd": L("Gère ta photothèque.", "Manages your photo library."),
        "cloudphotod": L("Synchronise Photos iCloud.", "Syncs iCloud Photos."),
        "bird": L("iCloud Drive : synchronise tes fichiers iCloud.", "iCloud Drive: syncs your iCloud files."),
        "cloudd": L("iCloud : synchronise les données des apps.", "iCloud: syncs app data."),
        "fileproviderd": L(
            "Gère les dossiers synchronisés (iCloud Drive, Dropbox, Google Drive…).",
            "Manages synced folders (iCloud Drive, Dropbox, Google Drive…)."
        ),
        "nsurlsessiond": L("Téléchargements en arrière-plan pour les apps et le système.", "Background downloads for apps and the system."),
        "trustd": L("Sécurité : vérifie les certificats (sites, apps).", "Security: checks certificates (websites, apps)."),
        "secd": L("Sécurité : gère le trousseau.", "Security: manages the keychain."),
        "securityd": L("Sécurité : gère le trousseau et les certificats.", "Security: manages the keychain and certificates."),
        "syspolicyd": L(
            "Sécurité : vérifie que les apps sont autorisées à s'ouvrir (Gatekeeper).",
            "Security: checks that apps are allowed to open (Gatekeeper)."
        ),
        "XprotectService": L("L'antivirus intégré de macOS.", "macOS's built-in antivirus."),
        "softwareupdated": L("Mises à jour de macOS.", "macOS updates."),
        "coreaudiod": L("Gère le son.", "Manages sound."),
        "bluetoothd": L("Gère le Bluetooth.", "Manages Bluetooth."),
        "airportd": wifi,
        "wifid": wifi,
        "wifip2pd": L("Wi-Fi direct (AirDrop, partage d'écran).", "Wi-Fi Direct (AirDrop, screen sharing)."),
        "locationd": L("Gère la localisation.", "Manages Location Services."),
        "sharingd": L("AirDrop, Handoff et partage entre tes appareils.", "AirDrop, Handoff and sharing between your devices."),
        "rapportd": L(
            "Communication avec tes autres appareils Apple à proximité (Continuité, Handoff).",
            "Talks to your other nearby Apple devices (Continuity, Handoff)."
        ),
        "ControlCenter": L(
            "Centre de contrôle et icônes de la barre des menus. Il reçoit aussi AirPlay (ports 5000 et 7000).",
            "Control Center and menu bar icons. It also receives AirPlay (ports 5000 and 7000)."
        ),
        "NotificationCenter": L("Notifications et widgets.", "Notifications and widgets."),
        "usernoted": L("Gère les notifications.", "Manages notifications."),
        "Dock": L("Le Dock et Mission Control.", "The Dock and Mission Control."),
        "SystemUIServer": L("Icônes système de la barre des menus.", "System icons in the menu bar."),
        "WindowManager": L("Organisation des fenêtres et Stage Manager.", "Window management and Stage Manager."),
        "chronod": L("Met à jour les widgets.", "Updates widgets."),
        "MTLCompilerService": L(
            "Prépare le code graphique (GPU) des apps. Normal d'en voir plusieurs.",
            "Prepares apps' graphics (GPU) code. Seeing several is normal."
        ),
        "VTDecoderXPCService": L("Décode la vidéo avec la puce graphique.", "Decodes video on the graphics chip."),
        "VTEncoderXPCService": L("Encode la vidéo avec la puce graphique.", "Encodes video on the graphics chip."),
        "QuickLookUIService": quickLook,
        "QuickLookSatellite": quickLook,
        "com.apple.WebKit.WebContent": L(
            "Contenu web affiché par Safari, Mail ou une autre app. Le fermer ferait planter l'onglet correspondant.",
            "Web content shown by Safari, Mail or another app. Closing it would crash that tab."
        ),
        "com.apple.WebKit.Networking": L("Accès réseau du moteur web (Safari, Mail…).", "Network access for the web engine (Safari, Mail…)."),
        "com.apple.WebKit.GPU": L("Affichage graphique du moteur web (Safari, Mail…).", "Graphics for the web engine (Safari, Mail…)."),
        "com.apple.appkit.xpc.openAndSavePanelService": L("Fenêtre « Ouvrir / Enregistrer » d'une app.", "An app's Open / Save dialog."),
        "ShareSheetUI": L("Fenêtre de partage d'une app.", "An app's Share sheet."),
        "distnoted": L("Relaye les notifications internes entre processus.", "Relays internal notifications between processes."),
        "cfprefsd": L("Lit et enregistre les préférences des apps.", "Reads and saves app preferences."),
        "powerd": L("Gestion de l'énergie et de la veille.", "Power and sleep management."),
        "backupd": L("Time Machine.", "Time Machine."),
        "hidd": L("Clavier, souris et trackpad.", "Keyboard, mouse and trackpad."),
        "logd": L("Journal du système.", "System log."),
        "mDNSResponder": L("Résolution des noms de domaine (DNS) et Bonjour.", "Domain name resolution (DNS) and Bonjour."),
        "configd": L("Configuration réseau.", "Network configuration."),
        "fseventsd": L(
            "Note les changements de fichiers (pour Spotlight, Time Machine…).",
            "Records file changes (for Spotlight, Time Machine…)."
        ),
        "ReportCrash": L("Prépare un rapport après le plantage d'une app.", "Prepares a report after an app crashes."),
        "tccd": L(
            "Gère les autorisations de confidentialité (caméra, micro, fichiers…).",
            "Manages privacy permissions (camera, microphone, files…)."
        ),
        "lsd": L("Tient la liste des apps installées (LaunchServices).", "Keeps the list of installed apps (LaunchServices)."),
        "coreservicesd": L("Services de base de macOS (ouverture des apps et des fichiers).", "Core macOS services (opening apps and files)."),
        "pboard": L("Presse-papiers.", "Clipboard."),
        "WallpaperAgent": L("Fond d'écran.", "Wallpaper."),
        "runningboardd": L("Surveille l'état des apps pour économiser l'énergie.", "Tracks app state to save energy."),
        "symptomsd": L("Analyse la qualité du réseau.", "Analyzes network quality."),
        "apsd": L("Reçoit les notifications push d'Apple.", "Receives Apple push notifications."),
        "identityservicesd": L("Comptes iMessage et FaceTime, Continuité.", "iMessage and FaceTime accounts, Continuity."),
        "imagent": L("Messages (iMessage) en arrière-plan.", "Messages (iMessage) in the background."),
        "akd": L("Authentification de ton identifiant Apple.", "Apple Account authentication."),
        "accountsd": L("Gère tes comptes (iCloud, mail…).", "Manages your accounts (iCloud, mail…)."),
        "suggestd": L(
            "Suggestions tirées de tes mails et messages (contacts, événements).",
            "Suggestions found in your mail and messages (contacts, events)."
        ),
        "routined": L("Apprend tes lieux fréquents (localisation).", "Learns your frequent places (location)."),
        "mobileassetd": L(
            "Télécharge des ressources système (voix, polices, modèles).",
            "Downloads system assets (voices, fonts, models)."
        ),
        "deleted": L("Libère de l'espace disque en vidant des caches.", "Frees disk space by clearing caches."),
        "contactsd": L("Contacts.", "Contacts."),
        "remindd": L("Rappels.", "Reminders."),
        "calaccessd": L("Calendrier.", "Calendar."),
        "AirPlayXPCHelper": L("AirPlay.", "AirPlay."),
        "TextInputMenuAgent": L("Menu de saisie (clavier) dans la barre des menus.", "Input (keyboard) menu in the menu bar."),
        "iconservicesagent": L("Prépare les icônes affichées.", "Prepares the icons on screen."),
        "containermanagerd": L("Gère les dossiers privés des apps.", "Manages apps' private folders."),
        "universalaccessd": L("Accessibilité.", "Accessibility."),
        "UserEventAgent": L(
            "Réagit aux événements du système (branchements, réseau…).",
            "Reacts to system events (devices plugged in, network…)."
        ),
        "opendirectoryd": L("Gère les comptes utilisateurs.", "Manages user accounts."),
        "diskarbitrationd": L("Gère le branchement des disques.", "Handles disks being connected."),
        "zsh": shell,
        "bash": shell,
        "login": L("Ouverture d'une session de terminal.", "Opens a terminal session."),
    ]

    public static func forSystem(name: String, path: String, isOtherUser: Bool) -> Explanation {
        if let text = system[name] { return Explanation(text.text) }
        if isOtherUser && !path.isEmpty && !PathRules.isSystem(path) {
            return Explanation(tr(
                "Service installé par une app tierce, lancé avec les droits administrateur.",
                "Service installed by a third-party app, running with administrator rights."
            ), isGeneric: true)
        }
        let text: L
        if path.contains(".xpc/") {
            text = L(
                "Service d'aide de macOS (XPC) : une app ou le système l'appelle pour une tâche précise.",
                "macOS helper service (XPC): an app or the system calls it for a specific task."
            )
        } else if path.contains(".appex/") {
            text = L("Extension d'app (widget, partage, aperçu…).", "App extension (widget, sharing, preview…).")
        } else if path.hasPrefix("/usr/libexec/") || path.hasPrefix("/usr/sbin/") {
            text = L("Service de fond de macOS.", "macOS background service.")
        } else if path.hasPrefix("/System/Library/CoreServices/") {
            text = L("Composant de macOS.", "macOS component.")
        } else if path.hasPrefix("/System/Library/PrivateFrameworks/") {
            text = L("Composant interne de macOS.", "Internal macOS component.")
        } else {
            text = L("Processus de macOS.", "macOS process.")
        }
        return Explanation(text.text, isGeneric: true)
    }

    public static func forThirdParty(name: String, path: String) -> Explanation {
        Explanation(tr(
            "Programme tiers qui tourne en arrière-plan, sans fenêtre.",
            "Third-party program running in the background, with no window."
        ), isGeneric: true)
    }

    /// Toutes les traductions intégrées, pour les tests.
    static var allTranslations: [L] {
        Array(appsByID.values) + Array(appsByName.values) + Array(appCategories.values)
            + Array(devTools.values) + Array(system.values) + [mcpServer, browser, editor, terminal, cloudSync, messaging]
    }
}
