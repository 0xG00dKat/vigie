import AppKit
import SwiftUI
import VigieCore

/// Ouvre la fenêtre de Vigie (une app sans icône dans le Dock doit se mettre au premier plan elle-même).
struct OpenWindowButton: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button(tr("Ouvrir dans une fenêtre", "Open in a window")) {
            openWindow(id: VigieWindow.id)
            NSApp.activate()
        }
    }
}

/// Icône de l'en-tête du panneau : ouvre la fenêtre (⌘O).
struct OpenWindowIconButton: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button {
            openWindow(id: VigieWindow.id)
            NSApp.activate()
        } label: {
            Image(systemName: "macwindow")
        }
        .buttonStyle(.borderless)
        .keyboardShortcut("o")
        .help(tr("Ouvrir dans une fenêtre (⌘O)", "Open in a window (⌘O)"))
    }
}

/// Dans la fenêtre, une page montre toujours son contenu : pas de section repliée.
private struct InVigieWindowKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var inVigieWindow: Bool {
        get { self[InVigieWindowKey.self] }
        set { self[InVigieWindowKey.self] = newValue }
    }
}

enum WindowPage: Hashable {
    /// Bilan : toutes les analyses et comment alléger le Mac (l'œil en haut de la colonne d'icônes).
    case checkup
    /// Une explication de « Comprendre mon Mac ».
    case lesson(String)
    /// Une question de « Par où commencer » (« Mon Mac est lent ») : ses explications, dans l'ordre.
    case learnQuestion(String)
    /// Les explications d'un thème (Les bases, Vitesse et mémoire…).
    case learnTopic(LessonTopic)
    /// « Mon Mac en fiche » : le modèle, la puce, la mémoire, le disque, la batterie.
    case macProfile
    /// Les Réglages : une seule page, centrée.
    case settings
    /// Le glossaire : les mots de Vigie et de macOS.
    case glossary
    case overview
    case history
    case rules
    case learn
    case speed
    case running
    case explorer
    case processes(ProcessCategory)
    case docker
    case ports
    case toolchains
    case storage(StorageKind)
}

/// Fenêtre de Vigie : barre latérale native à gauche, contenu à droite, une seule couleur d'accent,
/// des cartes sobres.
struct VigieWindow: View {
    static let id = "fenetre"
    @Environment(AppModel.self) private var model
    @State private var page: WindowPage?
    /// Sous-menu replié : il ne reste que la colonne d'icônes (clé `barreCompacte`).
    @AppStorage(SidebarCompact.key) private var compactSidebar = false
    /// Dernière page vue dans chaque famille : revenir à une famille y ramène.
    @State private var lastPages: [SidebarFamily: WindowPage] = [:]
    /// Animation d'ouverture : seulement à la première ouverture de la fenêtre après le lancement de Vigie.
    @State private var introStart: Date? = LogoIntroGate.claim()

    init(page: WindowPage = .overview) {
        _page = State(initialValue: page)
    }

    var body: some View {
        // Une mise en page à nous plutôt que la colonne de macOS : la largeur de la barre s'anime en douceur
        // quand on la réduit aux icônes, et se règle toujours en tirant son bord.
        // Comme un tableau de bord : une colonne d'icônes (les trois familles), le sous-menu de la famille, la page.
        // Fond uni partout, des traits fins entre les colonnes.
        // Comme une app de tableau de bord en verre : une barre latérale flottante (toutes les pages, en sections),
        // puis la page, sur le fond flouté de la fenêtre.
        let family = SidebarFamily(page ?? .overview)
        HStack(spacing: 0) {
            // Le menu de Vigie : la colonne d'icônes (l'œil du bilan en haut) et le sous-menu, dans une carte de verre.
            HStack(spacing: 0) {
                WindowRail(selected: family, page: $page) { chosen in
                    withAnimation(VigieMotion.standard) {
                        page = lastPages[chosen] ?? chosen.firstPage(model: model)
                    }
                }
                // Réglages et Comprendre tiennent sur leur propre page d'accueil : pas de sous-menu.
                if !compactSidebar && family != .settings && family != .learn {
                    Rectangle().fill(DS.separator).frame(width: 1).padding(.vertical, 14)
                    WindowSidebar(page: $page, family: family)
                        .frame(width: WindowGrid.submenuWidth)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }
            }
            .glassSidebar()
            .padding(WindowGrid.sidebarInset)
            content
                .environment(\.pageSymbol, page?.symbol)
        }
        .background(WindowGlass().ignoresSafeArea())
        .animation(VigieMotion.standard, value: compactSidebar)
        .animation(VigieMotion.standard, value: compactSidebar)
        .onChange(of: page) {
            if let page { lastPages[SidebarFamily(page)] = page }
            // « Bilan de mon Mac » lance les analyses (au plus une fois par minute).
            if page == .checkup, (model.checkupStarted.map { Date().timeIntervalSince($0) > 60 } ?? true) {
                model.runCheckup()
            }
            // Le parcours d'une question ne vaut que tant qu'on y lit.
            switch page {
            case .lesson, .learnQuestion: break
            default: model.learnPath = nil
            }
        }
        .onAppear {
            // Fenêtre ouverte depuis le panneau sur une page précise.
            if let request = model.windowPageRequest {
                page = request
                model.windowPageRequest = nil
            }
        }
        .onChange(of: model.windowPageRequest) {
            // Une carte d'état demande une page (« Voir ce qui prend de la mémoire »).
            if let request = model.windowPageRequest {
                page = request
                model.windowPageRequest = nil
            }
        }
        .onChange(of: model.introReplay) {
            // Réglages → Ouverture → « Voir ».
            introStart = LogoIntroGate.start()
        }
        .onChange(of: model.query) {
            // Une recherche porte sur les processus : on y va si on était ailleurs.
            guard !model.query.isEmpty else { return }
            if case .processes = page ?? .overview { return }
            // Un numéro cherché depuis la page Ports y reste : « 3000 » montre qui tient le port.
            if page == .ports || page == .running || page == .glossary { return }
            page = .running
        }
        .overlay {
            if let introStart {
                LogoIntroPlayer(start: introStart) { self.introStart = nil }
            }
        }
        .toolbar(.hidden, for: .windowToolbar)
        .tint(VigieTheme.accent)
        .frame(minWidth: 900, minHeight: 600)
        .background(WindowVisibilityObserver { model.setSurface("fenetre", visible: $0) })
        .background(DockPresenceObserver())
        .id(model.viewIdentity)
    }

    private var content: some View {
        Group {
            switch page ?? .overview {
            case .checkup: CheckupPage(page: $page)
            case .lesson(let id): LearnPage(lesson: id, page: $page).id(id)
            case .learnQuestion(let id): LearnQuestionPage(questionID: id, page: $page).id(id)
            case .learnTopic(let topic): LearnTopicPage(topic: topic, page: $page).id(topic)
            case .macProfile: MacProfilePage(page: $page)
            case .settings: SettingsPage(page: $page)
            case .glossary: GlossaryPage(page: $page)
            case .overview:
                if model.redesign { RedesignOverviewPage(page: $page) } else { OverviewBento(page: $page) }
            case .history: HistoryPage()
            case .rules: RulesPage()
            case .learn: LearnPage(page: $page)
            case .speed: SpeedPage()
            case .explorer: ExplorerPage()
            case .running: RunningPage()
            case .processes(let category): ProcessPage(category: category)
            case .docker: DockerPage()
            case .ports: PortsPage()
            case .toolchains: ToolchainsPage()
            case .storage(.largeFile): LargeFilesPage()
            case .storage(let kind): StoragePage(kind: kind)
            }
        }
        .environment(\.inVigieWindow, true)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(DS.canvas.ignoresSafeArea())
    }

    private var columnLine: some View {
        Rectangle().fill(DS.separator).frame(width: 1).ignoresSafeArea()
    }

}

struct SidebarMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .sidebar
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

/// Champ de recherche en haut de la barre latérale.
struct SidebarSearchField: View {
    @Environment(AppModel.self) private var model
    @FocusState private var focused: Bool

    var body: some View {
        @Bindable var model = model
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").font(.system(size: 12)).foregroundStyle(.secondary)
            TextField(tr("Rechercher…", "Search…"), text: $model.query)
                .help(model.isDeveloper ? tr("Une app, un projet ou un port (« 3000 »)", "An app, a project or a port (“3000”)") : tr("Une app", "An app"))
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($focused)
            if !model.query.isEmpty {
                Button { model.query = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
            .strokeBorder(focused ? VigieTheme.accent.opacity(0.6) : Color.clear, lineWidth: 1.5))
    }
}

// MARK: - Thème

enum VigieTheme {
    /// Vert d'eau : la seule couleur d'accent de la fenêtre.
    static let accent = DS.accent
    static let pagePadding: CGFloat = WindowGrid.pagePadding
}

/// Carte : fond des contrôles, bord fin, coins de 10 pt.
struct VigieCard<Content: View>: View {
    var padding: CGFloat = WindowGrid.cardPadding
    @ViewBuilder var content: Content
    /// Dans une case de grille, une carte intérieure perd son cadre (pas de bordures empilées).
    @Environment(\.flatCards) private var flat

    var body: some View {
        if flat {
            VStack(alignment: .leading, spacing: 0) { content }
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VStack(alignment: .leading, spacing: 0) { content }
                .padding(padding)
                .frame(maxWidth: .infinity, alignment: .leading)
                .panelSurface()
        }
    }
}

private struct FlatCardsKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var flatCards: Bool {
        get { self[FlatCardsKey.self] }
        set { self[FlatCardsKey.self] = newValue }
    }
}

/// Case d'une grille (« bento ») : une carte qui contient une section entière ; ses cartes intérieures s'aplatissent.
struct BentoCell<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        // Même hauteur que les autres cases de la rangée : le fond s'étire, le contenu reste en haut.
        VStack(alignment: .leading, spacing: 0) { content.environment(\.flatCards, true) }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .panelSurface()
    }
}

/// Tuile d'icône : fond teinté léger, symbole de la même couleur.
struct VigieTile: View {
    let symbol: String
    var tint: Color = VigieTheme.accent
    var size: CGFloat = 30

    var body: some View {
        // Les icônes de Vigie, sur leur tuile gris foncé : une seule teinte pour toute l'app (la couleur dit le risque, pas la famille).
        // Style verre : un creux translucide et un pictogramme simple, comme les lignes de la référence.
        VigieSymbolTile(symbol: symbol, size: size)
    }
}

/// Petite étiquette d'état : « sûr », « à vérifier », « Analysé il y a 3 h ».
struct Chip: View {
    let text: String
    var symbol: String? = nil
    var tint: Color = VigieTheme.accent

    var body: some View {
        HStack(spacing: 4) {
            if let symbol { Image(systemName: symbol).font(.system(size: 9, weight: .semibold)) }
            Text(text).font(.system(size: 10.5, weight: .semibold))
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .foregroundStyle(tint)
        .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(tint.opacity(0.11)))
    }
}

/// En-tête de page : grand titre, une phrase, et à droite l'état ou les actions.
struct PageHeader<Trailing: View>: View {
    let title: String
    let subtitle: String?
    /// Explication de « Comprendre mon Mac » liée à la page (« En savoir plus » sous la phrase).
    var lesson: String? = nil
    @ViewBuilder var trailing: Trailing

    @Environment(\.pageSymbol) private var symbol

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            if let symbol { PageIconTile(symbol: symbol) }
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 22, weight: .semibold)).foregroundStyle(DS.primaryText)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 12.5))
                        .foregroundStyle(DS.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let lesson { LearnMoreLink(lesson: lesson) }
            }
            Spacer(minLength: 16)
            trailing
        }
        .padding(.horizontal, VigieTheme.pagePadding)
        // Ligne de base du titre sur celle du sous-menu.
        .padding(.top, WindowGrid.top(forTitle: 22))
        .padding(.bottom, WindowGrid.gap)
    }
}

/// Bouton principal de la fenêtre : plein, vert d'eau.
struct AccentButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Capsule().fill(VigieTheme.accent.opacity(configuration.isPressed ? 0.8 : 1)))
    }
}

// MARK: - Barre latérale

/// Les trois familles de la colonne d'icônes, et les pages de chacune.
enum SidebarFamily: String, CaseIterable, Identifiable {
    case vigie, processes, storage, learn, settings
    var id: String { rawValue }

    /// Les familles de la colonne d'icônes (les Réglages s'ouvrent par l'engrenage, en bas).
    static let rail: [SidebarFamily] = [.vigie, .processes, .storage, .learn]

    init(_ page: WindowPage) {
        switch page {
        case .checkup, .overview, .history, .rules: self = .vigie
        case .learn, .lesson, .learnQuestion, .learnTopic, .macProfile, .glossary: self = .learn
        case .settings: self = .settings
        case .speed, .running, .processes, .docker, .ports: self = .processes
        case .explorer, .toolchains, .storage: self = .storage
        }
    }

    /// La page qui s'ouvre quand on choisit la famille : la première ligne de son sous-menu, dans l'ordre choisi.
    @MainActor
    func firstPage(model: AppModel) -> WindowPage {
        let defaults = UserDefaults.standard
        let first: String?
        switch self {
        case .vigie: first = SidebarOrder.apply(defaults.string(forKey: "ordreBarre.vigie") ?? "", to: WindowSidebar.vigieItems).first
        case .processes: first = SidebarOrder.apply(defaults.string(forKey: "ordreBarre.processus") ?? "", to: WindowSidebar.processItems(model)).first
        case .storage: first = SidebarOrder.apply(defaults.string(forKey: "ordreBarre.stockage") ?? "", to: WindowSidebar.storageItems(model)).first
        case .learn: return .learn
        case .settings: return .settings
        }
        return first.flatMap(SidebarOrder.page) ?? .overview
    }

    var symbol: String {
        switch self {
        // L'œil est le bilan, tout en haut : l'accueil a sa maison.
        case .vigie: return "house"
        case .processes: return "square.grid.2x2"
        case .storage: return "internaldrive"
        case .learn: return "lightbulb"
        case .settings: return "gearshape"
        }
    }

    /// Nom court, sous l'icône.
    func railTitle(developer: Bool) -> String {
        switch self {
        case .vigie: return tr("Accueil", "Home")
        case .learn: return tr("Comprendre", "Learn")
        case .settings: return tr("Réglages", "Settings")
        case .processes: return developer ? tr("Processus", "Processes") : tr("Mon Mac", "My Mac")
        case .storage: return developer ? tr("Stockage", "Storage") : tr("Disque", "Disk")
        }
    }

    func title(developer: Bool) -> String {
        switch self {
        case .vigie: return tr("Accueil", "Home")
        case .learn: return tr("Comprendre mon Mac", "Understand my Mac")
        case .settings: return tr("Réglages", "Settings")
        case .processes: return developer ? tr("Processus", "Processes") : tr("Mon Mac", "My Mac")
        case .storage: return developer ? tr("Stockage", "Storage") : tr("Espace disque", "Disk space")
        }
    }

    var subtitle: String {
        switch self {
        case .vigie: return tr("L'essentiel de ton Mac, son histoire et tes règles.", "Your Mac at a glance, its history and your rules.")
        case .learn: return tr("Pars de ce qui t'arrive : on t'explique, avec tes vrais chiffres.", "Start from what's happening: we explain, with your real numbers.")
        case .settings: return tr("Comment Vigie se comporte sur ton Mac.", "How Vigie behaves on your Mac.")
        case .processes: return tr("Ce qui tourne, et ce qui le ralentit.", "What's running, and what slows it down.")
        case .storage: return tr("Ce qui prend de la place, et ce qui se vide.", "What takes up space, and what can go.")
        }
    }
}

/// Colonne d'icônes, avec le nom dessous : la pastille d'état en haut, les trois familles, puis les réglages en bas.
struct WindowRail: View {
    @Environment(AppModel.self) private var model
    let selected: SidebarFamily
    @Binding var page: WindowPage?
    let choose: (SidebarFamily) -> Void
    @AppStorage(SidebarCompact.key) private var compact = false
    @State private var eyeHover = false
    @State private var eyeClicks = 0

    var body: some View {
        VStack(spacing: 6) {
            // La place des trois boutons de la fenêtre.
            Color.clear.frame(height: 30)
            checkupButton
                .padding(.bottom, 10)
            ForEach(SidebarFamily.rail) { family in
                RailItem(family: family, selected: family == selected) { choose(family) }
            }
            Spacer(minLength: 12)
            PanelRoundButton(symbol: "arrow.clockwise", help: tr("Actualiser et retrier", "Refresh and re-sort")) {
                model.refreshNow()
            }
            // Les Réglages : une famille à part, dans la fenêtre.
            PanelRoundButton(symbol: selected == .settings ? "gearshape.fill" : "gearshape",
                             help: tr("Réglages", "Settings")) { choose(.settings) }
            PanelRoundButton(symbol: compact ? "sidebar.right" : "sidebar.left",
                             help: compact ? tr("Afficher le menu", "Show the menu") : tr("Masquer le menu", "Hide the menu")) {
                withAnimation(VigieMotion.standard) { compact.toggle() }
            }
            .padding(.bottom, 14)
        }
        .frame(width: 76)
    }

    /// En haut : l'œil de Vigie. Un clic fait le bilan (toutes les analyses) et dit comment alléger le Mac.
    private var checkupButton: some View {
        let selected = page == .checkup
        return Button {
            eyeClicks += 1
            withAnimation(VigieMotion.standard) { page = .checkup }
            model.runCheckup()
        } label: {
            ZStack(alignment: .topTrailing) {
                AnimatedEyeTile(size: 34, hovering: eyeHover, clicks: eyeClicks, scanning: model.checkupRunning)
                    .frame(width: 56, height: 50)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(selected ? DS.well : DS.surface))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(DS.stroke, lineWidth: 0.5))
                // Le point dit l'état du Mac, sans chiffre.
                Circle().fill(stateColor).frame(width: 8, height: 8)
                    .overlay(Circle().strokeBorder(DS.canvas, lineWidth: 1.5))
                    .offset(x: -5, y: 5)
            }
        }
        .buttonStyle(.plain)
        .onHover { eyeHover = $0 }
        .help(tr("Faire le bilan : Vigie analyse tout et dit comment alléger ton Mac", "Run a checkup: Vigie analyzes everything and tells you how to lighten your Mac"))
    }

    private var stateColor: Color {
        switch model.health?.level {
        case .critical?: return DS.urgent
        case .attention?: return DS.review
        default: return DS.safe
        }
    }
}

struct RailItem: View {
    @Environment(AppModel.self) private var model
    let family: SidebarFamily
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                VigieTile(symbol: family.symbol, size: 26)
                Text(family.railTitle(developer: model.isDeveloper))
                    .font(.system(size: 10.5, weight: selected ? .semibold : .medium))
                    .foregroundStyle(selected ? DS.primaryText : DS.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .frame(width: 62, height: 56)
            .background(RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(selected ? DS.well : hovering ? DS.well.opacity(0.5) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(VigieMotion.quick, value: hovering)
        .animation(VigieMotion.standard, value: selected)
    }
}

/// Le sous-menu d'une famille : son titre, la recherche, ses pages (déplaçables à la souris), puis mémoire et disque.
struct WindowSidebar: View {
    @Environment(AppModel.self) private var model
    @Binding var page: WindowPage?
    let family: SidebarFamily
    /// Toutes les familles à la suite, en sections (la barre flottante de la fenêtre).
    var allFamilies = false
    // L'ordre choisi à la souris, famille par famille (identifiants séparés par des virgules).
    @AppStorage("ordreBarre.vigie") private var vigieOrder = ""
    @AppStorage("ordreBarre.processus") private var processOrder = ""
    @AppStorage("ordreBarre.stockage") private var storageOrder = ""

    /// Dans Comprendre, une explication allume son thème, une question allume « Par où commencer ».
    private var selection: Binding<WindowPage?> {
        Binding {
            switch page {
            case .lesson(let id): return Lessons.lesson(id).map { .learnTopic($0.topic) } ?? page
            case .learnQuestion: return .learn
            default: return page
            }
        } set: { page = $0 }
    }

    var body: some View {
        if allFamilies { allFamiliesList } else { familyList }
    }

    /// La barre flottante : deux raccourcis (bilan, nettoyage), puis chaque famille en section, et les Réglages en bas.
    private var allFamiliesList: some View {
        let safe = model.safeCleanItems.reduce(UInt64(0)) { $0 + $1.size }
        return VStack(spacing: 0) {
        // La place des trois boutons de la fenêtre, puis la recherche.
        VStack(spacing: 0) {
            Color.clear.frame(height: 30)
            SidebarSearchField()
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
        List(selection: allSelection) {
            Section {
                HStack {
                    SideLabel(tr("Bilan de mon Mac", "My Mac's checkup"), symbol: "eye")
                    Spacer()
                    if model.checkupRunning {
                        Text(tr("en cours", "running")).font(.system(size: 11.5, weight: .medium)).foregroundStyle(Glass.amber)
                    }
                }
                .tag(WindowPage.checkup)
                HStack {
                    SideLabel(tr("Nettoyer", "Clean up"), symbol: "checkmark.circle")
                    Spacer()
                    if safe > 0 {
                        Text(Format.bytes(safe, decimal: true)).font(.system(size: 11.5)).foregroundStyle(DS.secondaryText).monospacedDigit()
                    }
                }
                .tag(WindowPage.storage(.cache))
            }
            Section(SidebarFamily.vigie.title(developer: model.isDeveloper)) {
                rows(Self.vigieItems, order: $vigieOrder)
            }
            Section(SidebarFamily.processes.title(developer: model.isDeveloper)) {
                rows(processItems, order: $processOrder)
            }
            Section(SidebarFamily.storage.title(developer: model.isDeveloper)) {
                rows(storageItems, order: $storageOrder)
            }
            Section(SidebarFamily.learn.title(developer: model.isDeveloper)) {
                SideLabel(tr("Par où commencer", "Where to start"), symbol: "lightbulb").tag(WindowPage.learn)
                SideLabel(tr("Mon Mac en fiche", "My Mac at a glance"), symbol: "person.crop.circle").tag(WindowPage.macProfile)
                SideLabel(tr("Glossaire", "Glossary"), symbol: "doc.text").tag(WindowPage.glossary)
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .scrollIndicators(.never)
        // Les Réglages en bas, à leur place (pas par-dessus la liste).
        Divider().padding(.horizontal, 12)
        Button {
            withAnimation(VigieMotion.standard) { page = .settings }
        } label: {
            // Le même libellé que les lignes de la liste, au même retrait : icônes et textes alignés.
            // Hors de la liste, un libellé n'a pas le même écart icône-texte : on le reproduit à la main.
            HStack(spacing: 3) {
                Image(systemName: "gearshape")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(DS.secondaryText)
                    .frame(width: 20)
                Text(tr("Réglages", "Settings")).font(.system(size: 13))
                Spacer()
            }
            .padding(.leading, 9.5)
            .padding(.trailing, 8)
            .padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(page == .settings ? DS.wellSelected : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        }
    }

    /// Une explication, une question ou un thème allument « Par où commencer ».
    private var allSelection: Binding<WindowPage?> {
        Binding {
            switch page {
            case .lesson, .learnQuestion, .learnTopic: return .learn
            case .settings: return nil
            default: return page
            }
        } set: { page = $0 }
    }

    private var familyList: some View {
        List(selection: selection) {
            switch family {
            case .vigie: rows(Self.vigieItems, order: $vigieOrder)
            case .learn:
                // Sans groupe : la première ligne tombe à la même hauteur que dans les autres familles.
                SideLabel(tr("Par où commencer", "Where to start"), symbol: "lightbulb").tag(WindowPage.learn)
                SideLabel(tr("Mon Mac en fiche", "My Mac at a glance"), symbol: "person.crop.circle").tag(WindowPage.macProfile)
                SideLabel(tr("Glossaire", "Glossary"), symbol: "doc.text").tag(WindowPage.glossary)
                // Les thèmes seulement : les explications s'ouvrent depuis les pages.
                Section(tr("Thèmes", "Topics")) {
                    ForEach(LessonTopic.allCases.filter { model.isDeveloper || $0 != .developer }, id: \.self) { topic in
                        SideLabel(topic.title.text, symbol: topic.symbol).tag(WindowPage.learnTopic(topic))
                    }
                }
            case .processes: rows(processItems, order: $processOrder)
            case .storage: rows(storageItems, order: $storageOrder)
            case .settings: EmptyView()   // une seule page, sans sous-menu
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .scrollIndicators(.never)
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text(family.title(developer: model.isDeveloper))
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(DS.primaryText)
                // Toujours deux lignes : la recherche reste à la même hauteur d'une famille à l'autre.
                Text(family.subtitle)
                    .font(.system(size: 11.5))
                    .foregroundStyle(DS.secondaryText)
                    .lineLimit(2)
                    // Toujours la hauteur de deux lignes : la recherche et la liste ne bougent pas d'une famille à l'autre.
                    .frame(height: 30, alignment: .topLeading)
                SidebarSearchField()
                    .padding(.top, 10)
            }
            .padding(.horizontal, 16)
            // Ligne de base du titre sur celle de la page (la carte flottante est déjà décalée du haut).
            .padding(.top, WindowGrid.top(forTitle: 18) - WindowGrid.sidebarInset)
            .padding(.bottom, 8)
            .id(family)
            .transition(.opacity)
        }
        .safeAreaInset(edge: .bottom) { SidebarFooter() }
        .animation(VigieMotion.standard, value: family)
    }

    /// Une section dont les lignes se déplacent à la souris ; l'ordre est gardé.
    /// Les lignes d'une famille, déplaçables à la souris ; l'ordre est gardé.
    private func rows(_ available: [String], order: Binding<String>) -> some View {
        let items = SidebarOrder.apply(order.wrappedValue, to: available)
        return ForEach(items, id: \.self) { id in row(id) }
            .onMove { source, destination in
                var moved = items
                moved.move(fromOffsets: source, toOffset: destination)
                order.wrappedValue = SidebarOrder.store(moved, previous: order.wrappedValue)
            }
    }

    /// Barre réduite : pas de titres, un trait entre les familles. C'est une ligne de la liste (pas un en-tête),
    /// pour être centré exactement sous les icônes.
    private var separator: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.1))
            .frame(width: 26, height: 1)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 3)
            .selectionDisabled()
            .moveDisabled(true)
            .accessibilityHidden(true)
    }

    static let vigieItems = ["overview", "history", "rules"]

    private var processItems: [String] { Self.processItems(model) }
    private var storageItems: [String] { Self.storageItems(model) }

    static func processItems(_ model: AppModel) -> [String] {
        var items = ["speed", "running"]
        if model.isDeveloper { items.append("dev") }
        if model.isDeveloper, let docker = model.docker, docker.state != .notInstalled { items.append("docker") }
        if model.isDeveloper { items.append("ports") }
        return items
    }

    static func storageItems(_ model: AppModel) -> [String] {
        var items = ["explorer"]
        if model.isDeveloper { items.append("toolchains") }
        if let report = model.storage {
            items += model.visibleKinds.filter { !report.entries(of: $0).isEmpty }.map { "storage:" + $0.rawValue }
        } else {
            items.append("scan")
        }
        return items
    }

    @ViewBuilder
    private func row(_ id: String) -> some View {
        switch id {
        case "overview":
            SideLabel(tr("Vue d'ensemble", "Overview"), symbol: "eye").tag(WindowPage.overview)
        case "history":
            SideLabel(tr("Historique", "History"), symbol: "chart.xyaxis.line").tag(WindowPage.history)
        case "learn":
            SideLabel(tr("Comprendre mon Mac", "Understand my Mac"), symbol: "lightbulb").tag(WindowPage.learn)
        case "rules":
            let active = model.rules.filter(\.isEnabled).count
            SideLabel(tr("Alertes et règles", "Alerts and rules"), symbol: "bell.badge")
                .sideBadge("\(active)")
                .tag(WindowPage.rules)
        case "speed":
            SideLabel(tr("Vitesse et batterie", "Speed and battery"), symbol: "gauge.with.needle").tag(WindowPage.speed)
        case "running":
            SideLabel(tr("Ce qui tourne", "Running"), symbol: "square.grid.2x2")
                .sideBadge("\(RunningPage.categories.reduce(0) { $0 + model.visibleGroups(in: $1).count })")
                .tag(WindowPage.running)
        case "dev":
            let groups = model.visibleGroups(in: .dev)
            SideLabel(ProcessCategory.dev.title, symbol: ProcessCategory.dev.outlineSymbol)
                .sideBadge("\(groups.count)")
                .tag(WindowPage.processes(.dev))
        case "docker":
            SideLabel("Docker", symbol: "shippingbox")
                .sideBadge(model.docker?.state == .running ? "\(model.visibleDockerGroups.count)" : nil)
                .tag(WindowPage.docker)
        case "ports":
            let exposed = model.portEntries.filter { $0.isExposed && $0.category == .dev }.count
            SideLabel(tr("Ports", "Ports"), symbol: exposed > 0 ? "wifi.exclamationmark" : "point.3.connected.trianglepath.dotted")
                .sideBadge("\(model.portEntries.count)")
                .tag(WindowPage.ports)
        case "explorer":
            SideLabel(tr("Explorer", "Explore"), symbol: "square.grid.3x3.topleft.filled").tag(WindowPage.explorer)
        case "toolchains":
            SideLabel(tr("Versions et outils", "Versions and tools"), symbol: "hammer").tag(WindowPage.toolchains)
        case "scan":
            SideLabel(tr("Analyser le stockage", "Analyze storage"), symbol: "magnifyingglass").tag(WindowPage.storage(.cache))
        default:
            if id.hasPrefix("storage:"), let kind = StorageKind(rawValue: String(id.dropFirst(8))) {
                let size = model.storage?.entries(of: kind).reduce(UInt64(0)) { $0 + $1.size } ?? 0
                SideLabel(kind.sidebarTitle, symbol: kind.outlineSymbol)
                    .sideBadge(Format.bytes(size, decimal: true))
                    .tag(WindowPage.storage(kind))
            }
        }
    }
}

/// L'ordre des lignes de la barre latérale, choisi à la souris.
enum SidebarOrder {
    /// La page d'une ligne du sous-menu (mêmes identifiants que l'ordre gardé).
    static func page(_ id: String) -> WindowPage? {
        switch id {
        case "overview": return .overview
        case "history": return .history
        case "rules": return .rules
        case "speed": return .speed
        case "running": return .running
        case "dev": return .processes(.dev)
        case "docker": return .docker
        case "ports": return .ports
        case "explorer": return .explorer
        case "toolchains": return .toolchains
        case "scan": return .storage(.cache)
        default:
            guard id.hasPrefix("storage:"), let kind = StorageKind(rawValue: String(id.dropFirst(8))) else { return nil }
            return .storage(kind)
        }
    }

    /// Les lignes disponibles, dans l'ordre gardé ; celles jamais rangées gardent leur place par défaut, à la suite.
    static func apply(_ stored: String, to available: [String]) -> [String] {
        let saved = stored.split(separator: ",").map(String.init)
        let known = saved.filter { available.contains($0) }
        return known + available.filter { !known.contains($0) }
    }

    /// Garde le nouvel ordre, sans oublier les lignes absentes pour l'instant (une page qui n'apparaît qu'après une analyse).
    static func store(_ visible: [String], previous: String) -> String {
        let hidden = previous.split(separator: ",").map(String.init).filter { !visible.contains($0) }
        return (visible + hidden).joined(separator: ",")
    }
}

/// Bas de la barre latérale : mémoire, disque et ce que Vigie a mis à la corbeille.
struct SidebarFooter: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let snapshot = model.snapshot {
                FooterGauge(title: tr("Mémoire", "Memory"),
                            value: "\(Format.bytes(snapshot.memoryUsed)) / \(Format.bytes(snapshot.memoryTotal))",
                            ratio: Double(snapshot.memoryUsed) / Double(max(snapshot.memoryTotal, 1)), color: VigieTheme.accent)
            }
            if let disk = model.disk {
                FooterGauge(title: tr("Disque", "Disk"),
                            value: tr("\(Format.bytes(disk.available, decimal: true)) libres sur \(Format.bytes(disk.total, decimal: true))",
                                      "\(Format.bytes(disk.available, decimal: true)) free of \(Format.bytes(disk.total, decimal: true))"),
                            ratio: 1 - disk.freeRatio, color: disk.isLow ? DS.urgent : disk.isTight ? DS.review : VigieTheme.accent)
            }
            if model.trashedByVigie > 0 {
                Button {
                    model.openTrash()
                } label: {
                    Label(tr("\(Format.bytes(model.trashedByVigie, decimal: true)) dans la corbeille", "\(Format.bytes(model.trashedByVigie, decimal: true)) in the Trash"),
                          systemImage: "trash")
                        .font(.system(size: 11.5))
                }
                .buttonStyle(.borderless)
                .help(tr("Mis à la corbeille par Vigie : vide-la pour récupérer la place.", "Moved to the Trash by Vigie: empty it to get the space back."))
            }
        }
        .padding(12)
        .panelSurface(radius: 12)
        .padding(10)
        // Fond plein autour de la carte : les lignes de la liste ne se voient pas dessous.
        .background(Color.clear)
    }
}

struct FooterGauge: View {
    let title: String
    let value: String
    let ratio: Double
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.system(size: 11, weight: .medium))
                Spacer()
                Text(value).font(.system(size: 11)).monospacedDigit().foregroundStyle(.secondary)
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.09))
                    Capsule().fill(color).frame(width: geometry.size.width * min(max(ratio, 0), 1))
                }
            }
            .frame(height: 4)
        }
    }
}

// MARK: - Vue d'ensemble

struct OverviewPage: View {
    @Environment(AppModel.self) private var model
    @Binding var page: WindowPage?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: WindowGrid.gap) {
                PageHeader(title: tr("Vue d'ensemble", "Overview"),
                           subtitle: tr("Ce qui tourne et ce qui prend de la place, expliqué simplement.",
                                        "What's running and what takes up space, explained simply.")) {
                    VStack(alignment: .trailing, spacing: 6) {
                        if model.storageProgress != nil {
                            Chip(text: tr("Analyse en cours", "Analyzing"), symbol: "hourglass")
                        } else if let report = model.storage {
                            Chip(text: tr("Analysé \(Format.elapsed(since: report.date))", "Analyzed \(Format.elapsed(since: report.date))"), symbol: "checkmark.circle.fill")
                            Button(tr("Analyser à nouveau", "Analyze again")) { model.scanStorage() }
                                .buttonStyle(.borderless)
                                .font(.system(size: 11.5))
                        } else {
                            Chip(text: tr("Pas encore analysé", "Not analyzed yet"), symbol: "circle.dashed", tint: .secondary)
                        }
                    }
                }
                .padding(.horizontal, -VigieTheme.pagePadding)

                // D'abord l'état du Mac, en une phrase, avec une seule action.
                StatusCard(compact: false)
                if let update = model.visibleUpdate { UpdateBanner(state: update).padding(.horizontal, -12) }

                MacStorageCard()
                if model.storage != nil {
                    SpaceUsageCard(page: $page)
                } else if model.health?.action == nil {
                    ScanCard()
                }
                ProcessesCard(page: $page)
            }
            .padding(.horizontal, VigieTheme.pagePadding)
            .padding(.bottom, WindowGrid.pageBottom)
            .frame(maxWidth: 900, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }
}

/// « Stockage du Mac » : l'espace disponible en grand, la barre par famille, la légende.
struct MacStorageCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let disk = model.disk {
            let used = disk.total - disk.available
            VigieCard {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(tr("Stockage du Mac", "Mac storage")).font(.system(size: 14, weight: .semibold))
                        Spacer()
                        Text(tr("\(100 - disk.freePercent) % utilisés", "\(100 - disk.freePercent)% used"))
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(Format.bytes(disk.available, decimal: true))
                            .font(.system(size: 34, weight: .semibold))
                            .monospacedDigit()
                        Text(tr("disponibles", "available")).font(.system(size: 14)).foregroundStyle(.secondary)
                        if !model.isDeveloper {
                            // Une taille parlante : une photo de téléphone fait environ 4 Mo.
                            Text(tr("· environ \(Format.photos(disk.available)) photos", "· about \(Format.photos(disk.available)) photos"))
                                .font(.system(size: 13)).foregroundStyle(.tertiary)
                        }
                    }
                    UsageBar(report: model.storage, disk: disk, kinds: model.visibleKinds)
                    HStack(spacing: 22) {
                        LegendItem(color: .gray, title: tr("Utilisé", "Used"), value: Format.bytes(used, decimal: true))
                        if let report = model.storage {
                            LegendItem(color: .green, title: tr("Récupérable sans risque", "Safe to reclaim"), value: Format.bytes(model.reclaimable(report), decimal: true))
                        }
                        LegendItem(color: VigieTheme.accent, title: tr("Disponible", "Available"), value: Format.bytes(disk.available, decimal: true))
                    }
                    if let report = model.visibleReport, model.storageProgress == nil,
                       let growth = DiskDiagnosis.make(report: report, previous: model.storageReference).growthLine() {
                        Label(growth, systemImage: "arrow.up.right")
                            .font(.system(size: 12))
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }
}

/// Barre du disque : une part par famille mesurée, le reste en gris, la place libre en accent.
struct UsageBar: View {
    let report: StorageReport?
    let disk: DiskStatus
    let kinds: [StorageKind]

    var body: some View {
        let total = Double(max(disk.total, 1))
        let kinds = self.kinds.filter { $0 != .largeFile }
        let sizes = kinds.map { kind in Double(report?.entries(of: kind).reduce(UInt64(0)) { $0 + $1.size } ?? 0) }
        let used = Double(disk.total - disk.available)
        let rest = max(0, used - sizes.reduce(0, +))
        GeometryReader { geometry in
            HStack(spacing: 1.5) {
                ForEach(Array(zip(kinds, sizes)), id: \.0) { kind, size in
                    if size / total > 0.002 {
                        Rectangle().fill(kind.tint.opacity(0.85)).frame(width: geometry.size.width * size / total)
                    }
                }
                Rectangle().fill(Color.gray.opacity(0.45)).frame(width: geometry.size.width * rest / total)
                Rectangle().fill(VigieTheme.accent)
            }
            .clipShape(Capsule())
        }
        .frame(height: 10)
    }
}

struct LegendItem: View {
    let color: Color
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(title).font(.system(size: 12)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 12, weight: .semibold)).monospacedDigit()
        }
    }
}

/// « Ce qui prend de la place » : une ligne par famille (sûr ou à vérifier), puis le reste et la place libre.
struct SpaceUsageCard: View {
    @Environment(AppModel.self) private var model
    @Binding var page: WindowPage?

    var body: some View {
        if let report = model.storage, let disk = model.disk {
            let total = Double(max(disk.total, 1))
            let kinds = model.visibleKinds.filter { !report.entries(of: $0).isEmpty }
            let measured = kinds.filter { $0 != .largeFile }.reduce(UInt64(0)) { sum, kind in
                sum + report.entries(of: kind).reduce(0) { $0 + $1.size }
            }
            let used = disk.total - disk.available
            VStack(alignment: .leading, spacing: 10) {
                Text(tr("Ce qui prend de la place", "What takes up space")).font(.system(size: 15, weight: .semibold))
                VigieCard(padding: 0) {
                    ForEach(Array(kinds.enumerated()), id: \.element) { index, kind in
                        let entries = report.entries(of: kind)
                        if index > 0 { Divider().padding(.leading, 62) }
                        OverviewRow(symbol: kind.outlineSymbol, tint: kind.tint, title: kind.overviewTitle,
                                    chip: kind.reviewBadge, subtitle: kind.summary(entries),
                                    share: Double(entries.reduce(0) { $0 + $1.size }) / total,
                                    size: entries.reduce(0) { $0 + $1.size }) {
                            page = .storage(kind)
                        }
                    }
                }
                VigieCard(padding: 0) {
                    OverviewRow(symbol: "ellipsis", tint: .gray, title: tr("Le reste", "Everything else"), chip: nil,
                                subtitle: tr("macOS, tes documents et ce que Vigie ne trie pas", "macOS, your documents and what Vigie doesn't sort"),
                                share: Double(used > measured ? used - measured : 0) / total, size: used > measured ? used - measured : 0, action: nil)
                    Divider().padding(.leading, 62)
                    OverviewRow(symbol: "circle.dashed", tint: VigieTheme.accent, title: tr("Libre", "Free"), chip: nil,
                                subtitle: tr("Disponible pour de nouveaux fichiers", "Available for new files"),
                                share: Double(disk.available) / total, size: disk.available, action: nil)
                }
            }
        }
    }
}

/// Ligne de la vue d'ensemble : tuile, titre et étiquette, une phrase, part du disque, taille.
struct OverviewRow: View {
    let symbol: String
    let tint: Color
    let title: String
    let chip: (text: String, color: Color)?
    let subtitle: String
    let share: Double
    let size: UInt64
    let action: (() -> Void)?
    @State private var hovering = false

    var body: some View {
        let content = HStack(spacing: 14) {
            VigieTile(symbol: symbol, tint: tint, size: 32)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 7) {
                    Text(title).font(.system(size: 13.5, weight: .semibold))
                    if let chip { Chip(text: chip.text, tint: chip.color) }
                }
                Text(subtitle).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 10)
            Text(percent(share)).font(.system(size: 11.5)).monospacedDigit().foregroundStyle(.tertiary)
                .frame(width: 60, alignment: .trailing)
            Text(Format.bytes(size, decimal: true)).font(.system(size: 14, weight: .semibold)).monospacedDigit()
                .frame(width: 80, alignment: .trailing)
            Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(.tertiary)
                .opacity(action == nil ? 0 : 1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .contentShape(Rectangle())
        .background(hovering && action != nil ? Color.primary.opacity(0.035) : .clear)
        if let action {
            Button(action: action) { content }
                .buttonStyle(.plain)
                .onHover { hovering = $0 }
        } else {
            content
        }
    }
}

/// « Nettoyer ce qui est sûr » : pourquoi c'est sûr, et le bouton (récapitulatif avant de confirmer).
struct CleanupCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VigieCard {
            if model.safeClean == nil {
                HStack(alignment: .center, spacing: 18) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(tr("Nettoyer ce qui est sûr", "Clean what's safe")).font(.system(size: 17, weight: .semibold))
                        Text(tr("Les caches qui se recréent tout seuls, avec la commande officielle de l'outil quand il y en a une. Un récapitulatif s'affiche avant.",
                                "Caches that rebuild themselves, with the tool's official command when there is one. A summary shows first."))
                            .font(.system(size: 12.5)).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 12)
                    let total = model.safeCleanItems.reduce(UInt64(0)) { $0 + $1.size }
                    Button {
                        model.reviewSafeClean()
                    } label: {
                        Text(tr("Voir \(Format.bytes(total, decimal: true))", "Review \(Format.bytes(total, decimal: true))"))
                    }
                    .buttonStyle(AccentButtonStyle())
                    .disabled(total == 0)
                }
            } else {
                SafeCleanArea()
            }
            if let action = model.lastStorageAction {
                Text(action).font(.system(size: 12, weight: .medium)).foregroundStyle(.green).padding(.top, 8)
            }
        }
    }
}

/// L'état du Mac : vert, orange ou rouge, une phrase, et une seule grande action.
/// Dans la fenêtre, le récapitulatif du nettoyage s'affiche dedans.
struct StatusCard: View {
    enum Source { case combined, speed }
    @Environment(AppModel.self) private var model
    let compact: Bool
    var source: Source = .combined
    /// Dans une rangée de cartes : prend la hauteur de la rangée.
    var stretch = false

    var body: some View {
        if let health = source == .speed ? model.speedHealth : model.health {
            let color = Self.color(health.level)
            HStack(alignment: .top, spacing: compact ? 10 : 16) {
                Image(systemName: Self.symbol(health.level))
                    .font(.system(size: compact ? 22 : 34, weight: .semibold))
                    .foregroundStyle(color)
                    .padding(.top, compact ? 1 : 0)
                VStack(alignment: .leading, spacing: compact ? 3 : 6) {
                    Text(health.title).font(.system(size: compact ? 14 : 21, weight: .semibold))
                    Text(health.message)
                        .font(.system(size: compact ? 11.5 : 13.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if !compact, model.safeClean != nil {
                        SafeCleanArea().padding(.top, 6)
                    } else if case .quit(let id, let name)? = health.action, model.closeState(id) == .confirming {
                        // Deuxième clic : confirmer, en rouge, comme partout ailleurs.
                        HStack(spacing: 8) {
                            Button(tr("Quitter \(name) ?", "Quit \(name)?")) { model.performHealthAction(fromPanel: compact, health: health) }
                                .buttonStyle(DangerButtonStyle())
                            Button(tr("Annuler", "Cancel")) { model.cancelConfirmation(id) }
                                .buttonStyle(.borderless)
                        }
                        .padding(.top, compact ? 4 : 8)
                    } else if let title = health.actionTitle(), model.storageProgress == nil {
                        Button {
                            model.performHealthAction(fromPanel: compact, health: health)
                        } label: {
                            Label(title, systemImage: Self.actionSymbol(health.action))
                        }
                        .buttonStyle(AccentButtonStyle())
                        .padding(.top, compact ? 4 : 8)
                    } else if let progress = model.storageProgress {
                        ProgressView(value: progress) {
                            Text(tr("Recherche de ce qui prend de la place…", "Looking for what takes up space…")).font(.system(size: 11))
                        }
                        .padding(.top, 6)
                    }
                    if !compact, let action = model.lastStorageAction {
                        Text(action).font(.system(size: 12, weight: .medium)).foregroundStyle(.green).padding(.top, 4)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(compact ? 12 : 22)
            .frame(maxWidth: .infinity, maxHeight: stretch ? .infinity : nil, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(color.opacity(0.08)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(color.opacity(0.28), lineWidth: 0.8))
        }
    }

    static func actionSymbol(_ action: MacHealth.Action?) -> String {
        switch action {
        case .scan?: return "magnifyingglass"
        case .quit?: return "xmark.circle"
        case .showMemory?: return "memorychip"
        default: return "checkmark.circle"
        }
    }

    static func color(_ level: MacHealth.Level) -> Color {
        switch level {
        case .good: return .green
        case .attention: return .orange
        case .critical: return .red
        }
    }

    static func symbol(_ level: MacHealth.Level) -> String {
        switch level {
        case .good: return "checkmark.circle.fill"
        case .attention: return "exclamationmark.triangle.fill"
        case .critical: return "exclamationmark.octagon.fill"
        }
    }
}

/// Avant la première analyse : ce que Vigie va mesurer, et le bouton.
struct ScanCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VigieCard(padding: 20) {
            HStack(alignment: .center, spacing: 18) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(tr("Qu'est-ce qui prend de la place ?", "What's taking up space?")).font(.system(size: 17, weight: .semibold))
                    Text(tr("Caches, dépendances de projets, apps et leurs restes, gros fichiers, ce que macOS range dans « Données système ». Environ 20 s, rien n'est supprimé.",
                            "Caches, project dependencies, apps and their leftovers, large files, what macOS keeps in “System Data”. About 20 s, nothing is deleted."))
                        .font(.system(size: 12.5)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let progress = model.storageProgress {
                        ProgressView(value: progress).padding(.top, 6)
                    }
                }
                Spacer(minLength: 12)
                Button {
                    model.scanStorage()
                } label: {
                    Label(tr("Analyser ce Mac", "Scan this Mac"), systemImage: "magnifyingglass")
                }
                .buttonStyle(AccentButtonStyle())
                .disabled(model.storageProgress != nil)
            }
        }
    }
}

/// « 9,4 % » en français, « 9.4% » en anglais.
func percent(_ ratio: Double) -> String {
    if ratio < 0.001 { return Localization.current == .fr ? "< 0,1 %" : "< 0.1%" }
    let formatter = NumberFormatter()
    formatter.numberStyle = .percent
    formatter.maximumFractionDigits = 1
    formatter.minimumFractionDigits = 1
    formatter.locale = Locale(identifier: Localization.current == .fr ? "fr_FR" : "en_US")
    return formatter.string(from: NSNumber(value: ratio)) ?? ""
}

/// « Ce qui tourne » : une ligne par catégorie, avec le nombre et la mémoire.
struct ProcessesCard: View {
    @Environment(AppModel.self) private var model
    @Binding var page: WindowPage?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(tr("Ce qui tourne", "What's running")).font(.system(size: 15, weight: .semibold))
            if let snapshot = model.snapshot {
                Text(model.processSummary(snapshot)).font(.system(size: 12)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VigieCard(padding: 0) {
                ForEach(Array(model.visibleCategories.enumerated()), id: \.element) { index, category in
                    let groups = model.visibleGroups(in: category)
                    let memory = groups.reduce(UInt64(0)) { $0 + $1.memory }
                    if index > 0 { Divider().padding(.leading, 62) }
                    ProcessOverviewRow(category: category, count: groups.count, memory: memory) {
                        if category == .dev {
                            page = .processes(.dev)
                        } else {
                            model.runningFilter = [category]
                            page = .running
                        }
                    }
                }
            }
        }
    }
}

struct ProcessOverviewRow: View {
    let category: ProcessCategory
    let count: Int
    let memory: UInt64
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                VigieTile(symbol: category.outlineSymbol, tint: category.tint, size: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(category.title).font(.system(size: 13.5, weight: .semibold))
                    Text(category.help).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 10)
                Text("\(count)").font(.system(size: 11.5)).monospacedDigit().foregroundStyle(.tertiary).frame(width: 60, alignment: .trailing)
                Text(memory > 0 ? Format.bytes(memory) : "—").font(.system(size: 14, weight: .semibold)).monospacedDigit()
                    .frame(width: 80, alignment: .trailing)
                Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
            .background(hovering ? Color.primary.opacity(0.035) : .clear)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

// MARK: - Pages

struct ProcessPage: View {
    @Environment(AppModel.self) private var model
    let category: ProcessCategory

    var body: some View {
        let groups = model.visibleGroups(in: category)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PageHeader(title: category.title, subtitle: category.help, lesson: "processus") {
                    if category != .system, !groups.isEmpty {
                        BulkCloseButton(category: category, groups: groups)
                    }
                }
                .padding(.horizontal, -VigieTheme.pagePadding)
                .padding(.bottom, -16)
                RelaunchBanner()
                if !groups.isEmpty, !model.isSearching {
                    ProcessTopTiles(category: category, groups: groups)
                }
                if groups.isEmpty {
                    EmptyPage(text: model.isSearching
                              ? tr("Rien ne correspond à « \(model.query) ».", "Nothing matches “\(model.query)”.")
                              : tr("Rien dans cette catégorie pour l'instant.", "Nothing in this category right now."))
                } else {
                    BentoCell {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                                if index > 0 { Divider().padding(.leading, 38) }
                                GroupRow(group: group).padding(.horizontal, -12)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, VigieTheme.pagePadding)
            .padding(.bottom, WindowGrid.pageBottom)
        }
    }
}

/// En haut d'une page de processus : combien et ce que ça pèse, le plus lourd, et (dev) les ports ouverts.
struct ProcessTopTiles: View {
    let category: ProcessCategory
    let groups: [ProcessGroup]

    var body: some View {
        let memory = groups.reduce(UInt64(0)) { $0 + $1.memory }
        let cpu = groups.reduce(0.0) { $0 + $1.cpuPercent }
        HStack(alignment: .top, spacing: 16) {
            TopTile(symbol: category.outlineSymbol, tint: DS.safe,
                    title: tr("\(groups.count) en cours", "\(groups.count) running"),
                    text: tr("\(Format.bytes(memory)) de mémoire · \(Int(cpu.rounded())) % de processeur",
                             "\(Format.bytes(memory)) of memory · \(Int(cpu.rounded()))% CPU")) { EmptyView() }
            if let heaviest = groups.max(by: { $0.memory < $1.memory }) {
                TopTile(symbol: "memorychip", tint: heaviest.memory > 2 * 1_073_741_824 ? DS.review : DS.safe,
                        title: heaviest.title,
                        text: tr("Le plus lourd : \(Format.bytes(heaviest.memory)) de mémoire.", "The heaviest: \(Format.bytes(heaviest.memory)) of memory.")) { EmptyView() }
            }
            if category == .dev {
                let ports = groups.flatMap(\.ports)
                let exposed = groups.flatMap(\.exposedPorts)
                TopTile(symbol: exposed.isEmpty ? "lock" : "wifi", tint: exposed.isEmpty ? DS.safe : DS.review,
                        title: ports.isEmpty ? tr("Aucun port ouvert", "No open port")
                                             : tr("\(ports.count) port\(ports.count > 1 ? "s" : "") ouvert\(ports.count > 1 ? "s" : "")", "\(ports.count) open port\(ports.count > 1 ? "s" : "")"),
                        text: exposed.isEmpty ? tr("Tous joignables depuis ce Mac seulement.", "All reachable from this Mac only.")
                                              : tr("\(exposed.count) visible\(exposed.count > 1 ? "s" : "") sur le Wi-Fi : \(exposed.map(String.init).joined(separator: ", ")).",
                                                   "\(exposed.count) visible on the Wi-Fi: \(exposed.map(String.init).joined(separator: ", ")).")) { EmptyView() }
            } else if let busiest = groups.max(by: { $0.cpuPercent < $1.cpuPercent }), busiest.cpuPercent >= 1 {
                TopTile(symbol: "gauge.with.needle", tint: busiest.cpuPercent > 80 ? DS.review : DS.safe,
                        title: busiest.title,
                        text: tr("Le plus actif : \(Int(busiest.cpuPercent.rounded())) % de processeur.", "The busiest: \(Int(busiest.cpuPercent.rounded()))% CPU.")) { EmptyView() }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

struct EmptyPage: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(40)
    }
}

struct DockerPage: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PageHeader(title: "Docker", subtitle: tr("Conteneurs en cours, regroupés par projet Compose, et la place prise par Docker.",
                                                         "Running containers, grouped by Compose project, and the space Docker takes up.")) {
                    if let docker = model.docker, docker.state == .running, !model.visibleDockerGroups.isEmpty {
                        DockerStopAllButton(ids: docker.containers.map(\.id))
                    }
                }
                .padding(.horizontal, -VigieTheme.pagePadding)
                .padding(.bottom, -16)
                if let docker = model.docker, docker.state != .notInstalled {
                    if !model.isSearching { DockerTopTiles(docker: docker) }
                    Grid(horizontalSpacing: 16, verticalSpacing: 16) {
                        GridRow(alignment: .top) {
                            BentoCell { DockerContainersCard(docker: docker) }
                            if !model.isSearching {
                                BentoCell { DockerDiskBlock(docker: docker) }
                            }
                        }
                    }
                } else {
                    EmptyPage(text: tr("Docker n'est pas installé.", "Docker isn't installed."))
                }
            }
            .padding(.horizontal, VigieTheme.pagePadding)
            .padding(.bottom, WindowGrid.pageBottom)
        }
    }
}

/// Docker en trois chiffres : ce qui tourne, la place sur le disque, ce qui se récupère.
struct DockerTopTiles: View {
    let docker: DockerStatus

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            if docker.state == .running {
                TopTile(symbol: "shippingbox", tint: DS.safe,
                        title: tr("\(docker.containers.count) conteneur\(docker.containers.count > 1 ? "s" : "") en cours",
                                  "\(docker.containers.count) running container\(docker.containers.count > 1 ? "s" : "")"),
                        text: tr("\(Format.bytes(docker.memory)) de mémoire · \(docker.stoppedContainers) arrêté\(docker.stoppedContainers > 1 ? "s" : "")",
                                 "\(Format.bytes(docker.memory)) of memory · \(docker.stoppedContainers) stopped")) { EmptyView() }
            } else {
                TopTile(symbol: "shippingbox", tint: DS.keep, title: tr("Docker est arrêté", "Docker is stopped"),
                        text: tr("Aucun conteneur ne tourne. Démarre Docker pour voir le détail.", "No container is running. Start Docker to see the details.")) { EmptyView() }
            }
            if let virtual = docker.virtualDisk {
                TopTile(symbol: "internaldrive", tint: DS.safe,
                        title: tr("\(Format.bytes(virtual.allocated, decimal: true)) sur le disque", "\(Format.bytes(virtual.allocated, decimal: true)) on disk"),
                        text: tr("Le disque virtuel de Docker, qui peut monter jusqu'à \(Format.bytes(virtual.maximum, decimal: true)).",
                                 "Docker's virtual disk, which can grow up to \(Format.bytes(virtual.maximum, decimal: true)).")) { EmptyView() }
            }
            if let usage = docker.disk {
                let reclaimable = usage.buildCache.reclaimable + usage.images.reclaimable + usage.containers.reclaimable
                TopTile(symbol: "checkmark.circle", tint: reclaimable >= 5_000_000_000 ? DS.review : DS.safe,
                        title: tr("\(Format.bytes(reclaimable, decimal: true)) récupérables", "\(Format.bytes(reclaimable, decimal: true)) reclaimable"),
                        text: tr("Cache de construction, images et conteneurs inutilisés. Tes volumes (tes données) ne sont jamais comptés.",
                                 "Build cache, unused images and containers. Your volumes (your data) are never counted.")) { EmptyView() }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// Les conteneurs en cours, par projet Compose.
struct DockerContainersCard: View {
    @Environment(AppModel.self) private var model
    let docker: DockerStatus

    var body: some View {
        let groups = model.visibleDockerGroups
        VStack(alignment: .leading, spacing: 6) {
            Text(tr("Conteneurs", "Containers")).font(.system(size: 14, weight: .semibold))
            switch docker.state {
            case .running:
                ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                    if index > 0 { Divider().padding(.leading, 38) }
                    DockerGroupRow(group: group).padding(.horizontal, -12)
                }
                if groups.isEmpty {
                    Text(tr("Aucun conteneur en cours.", "No running containers."))
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
            case .notRunning:
                DockerStoppedRow(docker: docker).padding(.horizontal, -12)
            case .notInstalled:
                EmptyView()
            }
            if let error = model.dockerError {
                Text(error).font(.system(size: 11)).foregroundStyle(DS.urgent)
            }
        }
    }
}

struct StoragePage: View {
    @Environment(AppModel.self) private var model
    let kind: StorageKind

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let report = model.storage {
                    let entries = model.displayedEntries(of: kind, in: report)
                    PageHeader(title: kind.overviewTitle, subtitle: kind.pageExplanation,
                               lesson: kind == .cache ? "caches" : kind == .systemData ? "donnees-systeme" : nil) { EmptyView() }
                        .padding(.horizontal, -VigieTheme.pagePadding)
                        .padding(.bottom, -16)
                    if !entries.isEmpty {
                        StorageTopTiles(kind: kind, entries: entries)
                    }
                    if kind == .cache, model.storageProgress == nil {
                        CleanupCard()
                    }
                    if kind == .project, !model.dormantProjects.isEmpty {
                        BentoCell { DormantProjectsSection(projects: model.dormantProjects).padding(.horizontal, -VigieTheme.pagePadding + 8) }
                    }
                    BentoCell {
                        VStack(alignment: .leading, spacing: 6) {
                            if kind == .project, !model.dormantProjects.isEmpty {
                                Text(tr("Tous les projets", "All projects")).font(.system(size: 14, weight: .semibold))
                            }
                            StorageSectionRows(kind: kind, entries: entries, largest: max(entries.map(\.size).max() ?? 1, 1))
                                .padding(.horizontal, -12)
                        }
                    }
                } else {
                    PageHeader(title: tr("Stockage", "Storage"), subtitle: nil) { EmptyView() }
                        .padding(.horizontal, -VigieTheme.pagePadding)
                    ScanCard()
                }
            }
            .padding(.horizontal, VigieTheme.pagePadding)
            .padding(.bottom, WindowGrid.pageBottom)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { SelectionBar() }
        .onDisappear { model.clearSelection() }
    }
}

/// Trois cartes en haut d'une page de stockage : combien et quoi en faire, le plus gros, ce qui a changé.
struct StorageTopTiles: View {
    @Environment(AppModel.self) private var model
    let kind: StorageKind
    let entries: [StorageEntry]

    var body: some View {
        let size = entries.reduce(UInt64(0)) { $0 + $1.size }
        let level = DSLevel(kind)
        HStack(alignment: .top, spacing: 16) {
            TopTile(symbol: kind.outlineSymbol, tint: level.color,
                    title: Format.bytes(size, decimal: true),
                    text: tr("\(entries.count) élément\(entries.count > 1 ? "s" : "") · ", "\(entries.count) item\(entries.count > 1 ? "s" : "") · ") + advice(level)) { EmptyView() }
            if let biggest = entries.max(by: { $0.size < $1.size }) {
                let share = Int((Double(biggest.size) / Double(max(size, 1)) * 100).rounded())
                TopTile(symbol: "arrow.up.right", tint: level.color,
                        title: biggest.title.text,
                        text: tr("Le plus gros : \(Format.bytes(biggest.size, decimal: true)), \(share) % de la page.",
                                 "The biggest: \(Format.bytes(biggest.size, decimal: true)), \(share)% of the page.")) { EmptyView() }
            }
            growthTile(size: size)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func advice(_ level: DSLevel) -> String {
        switch level {
        case .safe: return tr("se vide sans risque, ça se recrée tout seul.", "safe to clear, it comes back on its own.")
        case .review: return tr("à regarder un par un avant de jeter.", "look at each one before deleting.")
        default: return tr("à garder : Vigie montre, sans proposer de vider.", "keep: Vigie shows it without offering to clear it.")
        }
    }

    @ViewBuilder
    private func growthTile(size: UInt64) -> some View {
        if let reference = model.storageReference {
            let before = model.displayedEntries(of: kind, in: reference).reduce(UInt64(0)) { $0 + $1.size }
            let delta = Int64(size) - Int64(before)
            let since = tr("depuis l'analyse \(Format.elapsed(since: reference.date))", "since the analysis \(Format.elapsed(since: reference.date))")
            let amount = Format.bytes(UInt64(abs(delta)), decimal: true)
            TopTile(symbol: "clock", tint: delta >= 5_000_000_000 ? DS.review : DS.safe,
                    title: abs(delta) < 500_000_000 ? tr("Stable", "Stable") : delta > 0 ? "+\(amount)" : "−\(amount)",
                    text: since.prefix(1).uppercased() + since.dropFirst() + ".") { EmptyView() }
        } else {
            TopTile(symbol: "clock", tint: DS.keep, title: tr("Première analyse", "First analysis"),
                    text: tr("La prochaine montrera ce qui a grossi ici.", "The next one will show what grew here.")) { EmptyView() }
        }
    }
}

// MARK: - Textes et couleurs des familles

extension StorageKind {
    var symbol: String {
        switch self {
        case .cache: return "arrow.triangle.2.circlepath"
        case .project: return "shippingbox.fill"
        case .appData: return "wrench.and.screwdriver.fill"
        case .application: return "app.fill"
        case .leftover: return "shippingbox.and.arrow.backward"
        case .largeFile: return "doc.fill"
        case .personal: return "person.fill"
        case .systemData: return "gearshape.fill"
        }
    }

    /// Nom dans la barre latérale et la vue d'ensemble (« Apps » est déjà pris par les processus).
    var overviewTitle: String {
        if Wording.simple {
            switch self {
            case .cache: return tr("Fichiers temporaires", "Temporary files")
            case .leftover: return tr("Restes d'apps désinstallées", "Leftovers from uninstalled apps")
            case .systemData: return tr("Fichiers de macOS", "macOS files")
            default: break
            }
        }
        switch self {
        case .cache: return tr("Caches", "Caches")
        case .project: return tr("Projets de dev", "Dev projects")
        case .appData: return tr("Outils et données d'apps", "Tools and app data")
        case .application: return tr("Apps installées", "Installed apps")
        case .leftover: return tr("Restes d'apps supprimées", "Leftovers from deleted apps")
        case .largeFile: return tr("Gros fichiers", "Large files")
        case .personal: return tr("Tes fichiers", "Your files")
        case .systemData: return tr("Données système", "System Data")
        }
    }

    var outlineSymbol: String {
        switch self {
        case .cache: return "arrow.triangle.2.circlepath"
        case .project: return "shippingbox"
        case .appData: return "wrench.and.screwdriver"
        case .application: return "app.dashed"
        case .leftover: return "doc.questionmark"
        case .largeFile: return "doc"
        case .personal: return "person.crop.circle"
        case .systemData: return "internaldrive"
        }
    }

    /// Nom court pour la barre latérale.
    var sidebarTitle: String {
        if Wording.simple {
            switch self {
            case .cache: return tr("Fichiers temporaires", "Temporary files")
            case .leftover: return tr("Restes d'apps", "App leftovers")
            case .systemData: return tr("Fichiers de macOS", "macOS files")
            default: break
            }
        }
        switch self {
        case .appData: return tr("Outils", "Tools")
        case .leftover: return tr("Restes d'apps", "App leftovers")
        case .project: return tr("Projets", "Projects")
        default: return overviewTitle
        }
    }

    /// Une ligne pour la vue d'ensemble.
    func summary(_ entries: [StorageEntry]) -> String {
        let count = entries.count
        switch self {
        case .cache: return Wording.simple
            ? tr("Des copies que les apps gardent pour aller plus vite. Elles se refont toutes seules.", "Copies apps keep to be faster. They rebuild on their own.")
            : tr("Se recréent tout seuls : sûrs à vider", "Rebuild themselves: safe to clear")
        case .project: return tr("node_modules de \(count) projet\(count > 1 ? "s" : ""), réinstallables", "node_modules of \(count) project\(count > 1 ? "s" : ""), reinstallable")
        case .appData: return tr("Outils installés et données d'apps", "Installed tools and app data")
        case .application: return tr("\(count) app\(count > 1 ? "s" : ""), avec les dossiers qu'elles éparpillent", "\(count) app\(count > 1 ? "s" : ""), with the folders they scatter")
        case .leftover: return tr("Laissés par des apps déjà supprimées", "Left by apps you already deleted")
        case .largeFile: return tr("\(count) fichier\(count > 1 ? "s" : "") de plus de 100 Mo, et les doublons", "\(count) file\(count > 1 ? "s" : "") over 100 MB, and duplicates")
        case .personal: return tr("Bureau, Documents, Téléchargements", "Desktop, Documents, Downloads")
        case .systemData: return Wording.simple
            ? tr("Voix, modèles d'IA, mises à jour : macOS s'en occupe", "Voices, AI models, updates: macOS takes care of them")
            : tr("Rangé par macOS dans « Données système »", "Kept by macOS in “System Data”")
        }
    }

    /// Signal à côté du titre : sûr, ou à regarder d'abord.
    var reviewBadge: (text: String, color: Color)? {
        switch self {
        case .cache: return (tr("sans risque", "safe"), .green)
        case .project, .application, .leftover, .largeFile: return (tr("à vérifier", "review first"), .orange)
        case .systemData: return (tr("géré par macOS", "managed by macOS"), .secondary)
        case .appData, .personal: return (tr("à garder", "keep"), .secondary)
        }
    }

    var pageExplanation: String {
        switch self {
        case .cache: return tr("Fichiers temporaires que les apps et les outils recréent quand il le faut. Les vider ne fait rien perdre.",
                               "Temporary files apps and tools recreate when needed. Clearing them loses nothing.")
        case .project: return tr("Dépendances de tes projets JavaScript. « npm install » (ou pnpm) les réinstalle ; à la corbeille, tu peux revenir en arrière.",
                                 "Your JavaScript projects' dependencies. “npm install” (or pnpm) reinstalls them; they go to the Trash, so you can undo.")
        case .appData: return tr("Outils installés dans ton dossier et données d'apps : à garder, ou à nettoyer depuis l'outil lui-même.",
                                 "Tools installed in your folder and app data: keep them, or clean up from the tool itself.")
        case .application: return tr("Chaque app avec les dossiers qu'elle éparpille. « Désinstaller… » met l'app et ses restes à la corbeille.",
                                     "Each app with the folders it scatters. “Uninstall…” moves the app and its leftovers to the Trash.")
        case .leftover: return tr("Dossiers laissés par des apps qui ne sont plus installées. Vérifie avant : ils vont à la corbeille.",
                                  "Folders left by apps that are no longer installed. Check first: they go to the Trash.")
        case .largeFile: return tr("Tes fichiers de plus de 100 Mo. Rien ne part sans toi : ce que tu choisis va à la corbeille.",
                                   "Your files over 100 MB. Nothing goes without you: what you pick goes to the Trash.")
        case .personal: return tr("Tes dossiers. Vigie ne les touche jamais.", "Your folders. Vigie never touches them.")
        case .systemData: return tr("Ce que macOS télécharge et gère lui-même. Vigie montre, sans toucher.",
                                    "What macOS downloads and manages itself. Vigie shows it, without touching.")
        }
    }
}

extension ProcessCategory {
    var outlineSymbol: String {
        switch self {
        case .apps: return "square.grid.2x2"
        case .dev: return "terminal"
        case .background: return "moon"
        case .system: return "gearshape.2"
        }
    }

    var symbol: String {
        switch self {
        case .apps: return "app.fill"
        case .dev: return "terminal.fill"
        case .background: return "moon.fill"
        case .system: return "gearshape.2.fill"
        }
    }

    var tint: Color {
        switch self {
        // Une seule couleur d'accent ; macOS en gris : on n'y touche pas.
        case .apps, .dev, .background: return VigieTheme.accent
        case .system: return .gray
        }
    }
}

/// En haut de la page Projets : les projets pas touchés depuis six mois, et ce qu'on peut leur retirer sans risque.
struct DormantProjectsSection: View {
    @Environment(AppModel.self) private var model
    let projects: [StorageEntry]

    var body: some View {
        let total = projects.reduce(UInt64(0)) { $0 + $1.size }
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "moon.zzz.fill").foregroundStyle(.orange)
                Text(tr("Projets endormis", "Dormant projects")).font(.system(size: 13, weight: .semibold))
                Chip(text: "\(projects.count) · \(Format.bytes(total, decimal: true))", tint: .orange)
            }
            .padding(.horizontal, VigieTheme.pagePadding)
            Text(tr("Pas touchés depuis plus de six mois. Leurs dépendances et compilations vont à la corbeille et se recréent au besoin ; ton code et l'historique Git restent.",
                    "Untouched for more than six months. Their dependencies and builds go to the Trash and come back when needed; your code and Git history stay."))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, VigieTheme.pagePadding)
                .padding(.top, 4)
                .padding(.bottom, 8)
            Divider()
            StorageSectionRows(kind: .project, entries: projects, largest: max(projects.map(\.size).max() ?? 1, 1))
                .padding(.horizontal, VigieTheme.pagePadding - 12)
        }
    }
}


// MARK: - En-tête de page

private struct PageSymbolKey: EnvironmentKey {
    static let defaultValue: String? = nil
}

extension EnvironmentValues {
    /// L'icône de la page affichée (posée par la fenêtre) : l'en-tête la montre à gauche du titre.
    var pageSymbol: String? {
        get { self[PageSymbolKey.self] }
        set { self[PageSymbolKey.self] = newValue }
    }
}

/// L'icône carrée d'une page, à gauche de son titre : sombre, le pictogramme en blanc.
struct PageIconTile: View {
    let symbol: String
    var size: CGFloat = 44

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
            .fill(Color(white: 0.13))
            .overlay(RoundedRectangle(cornerRadius: size * 0.27, style: .continuous).strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5))
            .overlay(Image(systemName: symbol).font(.system(size: size * 0.4, weight: .medium)).foregroundStyle(.white))
            .frame(width: size, height: size)
            .shadow(color: .black.opacity(0.18), radius: 4, y: 2)
    }
}

extension WindowPage {
    /// Le pictogramme de la page (en-tête).
    var symbol: String {
        switch self {
        case .checkup: return "eye"
        case .lesson(let id): return Lessons.lesson(id)?.symbol ?? "lightbulb"
        case .learnQuestion(let id): return LessonQuestions.question(id)?.symbol ?? "lightbulb"
        case .learnTopic(let topic): return topic.symbol
        case .macProfile: return "person.crop.circle"
        case .glossary: return "doc.text"
        case .overview: return "house"
        case .history: return "chart.xyaxis.line"
        case .rules: return "bell"
        case .learn: return "lightbulb"
        case .speed: return "gauge.with.needle"
        case .running: return "square.grid.2x2"
        case .explorer: return "square.grid.3x3.topleft.filled"
        case .processes(let category): return category.outlineSymbol
        case .docker: return "shippingbox"
        case .ports: return "network"
        case .toolchains: return "wrench.and.screwdriver"
        case .storage(let kind): return kind.outlineSymbol
        case .settings: return "gearshape"
        }
    }
}
