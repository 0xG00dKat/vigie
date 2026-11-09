import AppKit
import Observation
import SwiftUI
import VigieCore

enum CloseState: Equatable {
    /// Premier clic : le bouton devient « Quitter ? ». Rien n'est fermé.
    case confirming
    case closing(since: Date, pids: [Int32])
    /// Toujours là après quelques secondes : on propose de forcer.
    case stuck(pids: [Int32])
}

enum ClaudeState: Equatable {
    case loading
    case answer(String)
    case failed(String)
}

/// Réglage de langue choisi dans le panneau, gardé dans les préférences de Vigie.
enum LanguageSetting: String, CaseIterable, Identifiable {
    case automatic, fr, en

    var id: String { rawValue }

    var resolved: Language {
        switch self {
        case .automatic: return Localization.systemLanguage()
        case .fr: return .fr
        case .en: return .en
        }
    }

    var label: String {
        switch self {
        case .automatic: return tr("Automatique", "Automatic") + " (\(Localization.systemLanguage().nativeName))"
        case .fr: return Language.fr.nativeName
        case .en: return Language.en.nativeName
        }
    }

    static let defaultsKey = "langue"

    static var stored: LanguageSetting {
        UserDefaults.standard.string(forKey: defaultsKey).flatMap(LanguageSetting.init(rawValue:)) ?? .automatic
    }
}

/// État de la recherche de mise à jour, tel que l'affiche le panneau.
enum UpdateState: Equatable {
    case idle
    case checking
    case upToDate(latest: Version?)
    case available(ReleaseInfo)
    case failed(String)
}

enum PanelMode: String {
    case processes, speed, storage
}

enum RunningApps {
    @MainActor
    static func current() -> [RunningApp] {
        NSWorkspace.shared.runningApplications.compactMap { app in
            guard let url = app.bundleURL else { return nil }
            let policy: ActivationPolicy
            switch app.activationPolicy {
            case .regular: policy = .regular
            case .accessory: policy = .accessory
            default: policy = .prohibited
            }
            return RunningApp(
                pid: app.processIdentifier,
                bundlePath: realPath(url.path),
                bundleID: app.bundleIdentifier,
                name: app.localizedName ?? url.deletingPathExtension().lastPathComponent,
                policy: policy
            )
        }
    }

    /// Même forme que les chemins renvoyés par le noyau (`/private/var/…` et non `/var/…`).
    static func realPath(_ path: String) -> String {
        guard let resolved = realpath(path, nil) else { return path }
        defer { free(resolved) }
        return String(cString: resolved)
    }
}

@MainActor
enum Closer {
    /// Fermeture normale. Renvoie les pids à surveiller.
    static func perform(_ method: CloseMethod) -> [Int32] {
        switch method {
        case .quitApps(let pids):
            for pid in pids {
                NSRunningApplication(processIdentifier: pid)?.terminate()
            }
            return pids
        case .signal(let pids):
            return ProcessSignals.send(SIGTERM, to: pids)
        case .notAllowed:
            return []
        }
    }

    /// Fermeture forcée (l'équivalent de « Forcer à quitter »).
    static func force(_ pids: [Int32]) {
        for pid in pids where pid > 1 && pid != getpid() {
            if let app = NSRunningApplication(processIdentifier: pid), app.forceTerminate() {
                continue
            }
            kill(pid, SIGKILL)
        }
    }
}

/// Désinstallation d'une app : choix des éléments, en cours, échec.
enum UninstallState: Equatable {
    case choosing(Set<String>)
    case running
    case failed(String)
}

/// « Nettoyer ce qui est sûr » : récapitulatif, en cours, terminé.
enum SafeCleanState: Equatable {
    case reviewing
    case running(done: Int, total: Int)
    case finished(freed: UInt64, failures: Int)
}

/// Mode de Vigie. Au premier lancement : Développeur si le Mac a des outils de développement, Simple sinon.
enum ExperienceMode: String, CaseIterable, Identifiable {
    case simple, developer

    static let defaultsKey = "modeUtilisation"
    var id: String { rawValue }

    var label: String {
        switch self {
        case .simple: return tr("Simple", "Simple")
        case .developer: return tr("Développeur", "Developer")
        }
    }

    static var stored: ExperienceMode {
        if let raw = UserDefaults.standard.string(forKey: defaultsKey), let mode = ExperienceMode(rawValue: raw) { return mode }
        return looksLikeDeveloperMac ? .developer : .simple
    }

    /// Xcode, Node, Homebrew, Docker ou un dossier de cache npm : quelqu'un qui programme.
    static var looksLikeDeveloperMac: Bool {
        let home = NSHomeDirectory()
        return ["/Applications/Xcode.app", "/opt/homebrew/bin/brew", "/usr/local/bin/brew", "/opt/homebrew/bin/node", "/usr/local/bin/node",
                "/Applications/Docker.app", home + "/.npm", home + "/.cargo", home + "/.local/bin/claude"]
            .contains { FileManager.default.fileExists(atPath: $0) }
    }
}

/// Nettoyage d'une ligne du Stockage.
enum CleanState: Equatable {
    case confirming
    case running
    case done(freed: UInt64, inTrash: Bool)
    case failed(String)
}

@Observable
@MainActor
final class AppModel {
    private(set) var snapshot: Snapshot?
    private(set) var groupsByCategory: [ProcessCategory: [ProcessGroup]] = [:]
    var query = ""
    var expandedGroups: Set<String> = []
    /// Sections repliées. Dans l'app, toutes le sont au premier lancement, puis Vigie retient ton choix
    /// (clé « sectionsOuvertes ») ; les captures gardent les sections ouvertes, sauf Système.
    var collapsedSections: Set<ProcessCategory> = [.system] {
        didSet { saveOpenSections() }
    }
    private(set) var closeStates: [String: CloseState] = [:]
    private(set) var claude: [String: ClaudeState] = [:]
    private(set) var languageSetting: LanguageSetting = .automatic
    private(set) var disk: DiskStatus?
    private(set) var docker: DockerStatus?
    var dockerCollapsed = false {
        didSet { saveOpenSections() }
    }
    /// Vrai dans l'app (pas dans les captures) : l'état des sections est lu et enregistré.
    @ObservationIgnored private var remembersSections = false
    private(set) var dockerError: String?
    private(set) var copiedCommand: String?
    private(set) var update: UpdateState = .idle
    var mode: PanelMode = .processes
    private(set) var storage: StorageReport?
    /// Avancement de l'analyse du stockage (nil quand aucune analyse ne tourne).
    private(set) var storageProgress: Double?
    var expandedStorage: Set<String> = []
    /// Sections du stockage dépliées en entier (projets, apps).
    var showAll: Set<StorageKind> = []
    /// Ligne à amener à l'écran à l'ouverture (captures).
    var storageScrollTarget: String?
    /// Analyse de référence pour dire « ce qui a grossi » (au moins 6 h avant la dernière, quand c'est possible).
    private(set) var storageReference: StorageReport?
    /// Analyse lancée par l'alerte disque : la notification part quand elle se termine.
    @ObservationIgnored private var notifyWhenStorageReady = false
    /// Nettoyages de la vue Stockage, par chemin : confirmation, en cours, fait, échec.
    private(set) var cleanStates: [String: CleanState] = [:]
    /// Désinstallations, par chemin de l'app.
    private(set) var uninstallStates: [String: UninstallState] = [:]
    private(set) var safeClean: SafeCleanState?
    /// Dernière action terminée (désinstallation…), affichée dans la vue d'ensemble.
    private(set) var lastStorageAction: String?
    /// Place mise à la corbeille par Vigie et pas encore récupérée (la corbeille n'est pas vidée).
    private(set) var trashedByVigie: UInt64 = UInt64(UserDefaults.standard.integer(forKey: "corbeilleVigie"))
    /// Famille affichée seule (nil : toutes).
    var storageFilter: StorageKind?
    /// Sections du stockage repliées.
    /// Sections du stockage repliées : toutes au premier lancement, puis selon ton dernier choix (clé « sectionsStockageOuvertes »).
    var collapsedStorage: Set<StorageKind> = [] {
        didSet { saveOpenSections() }
    }
    /// Vrai quand l'utilisateur a cliqué « Rechercher » : on montre alors aussi « à jour » et les erreurs.
    private(set) var updateCheckWasManual = false
    var autoCheckUpdates: Bool = UserDefaults.standard.object(forKey: UpdateKeys.automatic) as? Bool ?? true {
        didSet { UserDefaults.standard.set(autoCheckUpdates, forKey: UpdateKeys.automatic) }
    }
    private(set) var ignoredUpdateVersion: String? = UserDefaults.standard.string(forKey: UpdateKeys.ignored)
    private(set) var language: Language = .en

    @ObservationIgnored private let sampler = ProcessSampler()
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var isRefreshing = false
    @ObservationIgnored private var refreshQueued = false
    @ObservationIgnored private var isVisible = false
    /// Ordre des lignes figé tant que le panneau est ouvert, pour que rien ne bouge sous le curseur.
    @ObservationIgnored private var frozenOrder: [ProcessCategory: [String]] = [:]
    @ObservationIgnored private var expiryTasks: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private let cache = ExplanationCache.shared
    @ObservationIgnored private let ownBundleID = Bundle.main.bundleIdentifier
    @ObservationIgnored private var diskTimer: Timer?
    @ObservationIgnored private var dockerTimer: Timer?
    @ObservationIgnored private var isReadingDocker = false
    @ObservationIgnored private var diskAlert = DiskAlertState()
    @ObservationIgnored private var updateTimer: Timer?
    @ObservationIgnored let currentVersion: Version? = (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String).flatMap(Version.init)
    @ObservationIgnored let updateRepository = Bundle.main.object(forInfoDictionaryKey: "VigieUpdateRepository") as? String ?? UpdateChecker.defaultRepository

    init(startImmediately: Bool = true) {
        languageSetting = LanguageSetting.stored
        language = languageSetting.resolved
        Localization.current = language
        experience = ExperienceMode.stored
        Wording.simple = experience == .simple
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didTerminateApplicationNotification, NSWorkspace.didLaunchApplicationNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, self.isVisible else { return }
                    self.refresh()
                }
            })
        }
        if startImmediately {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                OnboardingWindow.showIfNeeded(model: self)
            }
            restoreOpenSections()
            storage = StorageReportStore.load()
            storageReference = StorageReportStore.loadPrevious()
            history = HistoryStore.load()
            rules = RuleStore.load()
            refresh()
            refreshDisk()
            Notifier.configure { [weak self] id in self?.quitFromNotification(id) }
            updateBackgroundMonitoring()
            // Le disque est surveillé même panneau fermé : c'est une seule lecture, toutes les 2 minutes.
            diskTimer = Timer.scheduledTimer(withTimeInterval: 120, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshDisk() }
            }
            // Mises à jour : au plus une vérification par jour, la première 30 s après le lancement.
            updateTimer = Timer.scheduledTimer(withTimeInterval: 6 * 3600, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.checkForUpdatesIfDue() }
            }
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(30))
                self?.checkForUpdatesIfDue()
            }
        }
    }

    // MARK: - Actualisation

    /// « 702 processus en tout, rangés en 9 apps… » : en tête du panneau et dans la vue d'ensemble de la fenêtre.
    func processSummary(_ snapshot: Snapshot) -> String {
        let apps = count(in: .apps)
        let dev = count(in: .dev)
        let background = count(in: .background)
        let systemProcesses = snapshot.groups(in: .system).reduce(0) { $0 + $1.processes.count }
        let total = Format.processes(snapshot.processCount)
        let others = Format.count(systemProcesses)
        if !isDeveloper {
            return tr("\(apps) apps ouvertes et \(background) programmes discrets. Les \(others) autres programmes font tourner macOS : rien à faire de ce côté.",
                      "\(apps) open apps and \(background) quiet helpers. The other \(others) programs keep macOS running: nothing to do there.")
        }
        return tr(
            "\(total) en tout, rangés en \(apps) apps, \(dev) groupes de dev et \(background) utilitaires. Les \(others) autres appartiennent à macOS.",
            "\(total) in total, sorted into \(apps) apps, \(dev) dev groups and \(background) utilities. The other \(others) belong to macOS."
        )
    }

    /// Surfaces visibles (le panneau de la barre des menus, la fenêtre) : Vigie ne travaille que si l'une l'est.
    @ObservationIgnored private var visibleSurfaces = Set<String>()

    func setSurface(_ name: String, visible: Bool) {
        if visible { visibleSurfaces.insert(name) } else { visibleSurfaces.remove(name) }
        setVisible(!visibleSurfaces.isEmpty)
    }

    func setVisible(_ visible: Bool) {
        guard visible != isVisible else { return }
        isVisible = visible
        if visible {
            frozenOrder = [:]
            forgetExpiredStorage()
            refresh()
            timer?.invalidate()
            timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
            refreshDisk()
            refreshDocker()
            dockerTimer?.invalidate()
            // Docker est plus lent à interroger (quelques secondes) : toutes les 15 s suffisent.
            dockerTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshDocker() }
            }
        } else {
            timer?.invalidate()
            timer = nil
            dockerTimer?.invalidate()
            dockerTimer = nil
            frozenOrder = [:]
            // Une confirmation en attente ne doit pas survivre à la fermeture du panneau.
            closeStates = closeStates.filter { $0.value != .confirming }
        }
    }

    /// Change la langue tout de suite. `persist: false` et `reload: false` servent aux captures d'écran.
    // MARK: - Mode Simple ou Développeur

    /// Simple : des mots de tous les jours, sans ce qui ne parle qu'aux développeurs. Développeur : tout.
    private(set) var experience: ExperienceMode = .simple

    func setExperience(_ mode: ExperienceMode, persist: Bool = true) {
        experience = mode
        Wording.simple = mode == .simple
        if persist { UserDefaults.standard.set(mode.rawValue, forKey: ExperienceMode.defaultsKey) }
        if mode == .simple, case .project? = storageFilter { storageFilter = nil }
        if mode == .simple, storageFilter == .appData { storageFilter = nil }
        if isDemo { apply(DemoData.snapshot()) } else { refreshAndReorder() }
    }

    var isDeveloper: Bool { experience == .developer }

    /// Catégories de processus montrées : en Simple, pas les outils de développement.
    var visibleCategories: [ProcessCategory] {
        isDeveloper ? ProcessCategory.allCases : ProcessCategory.allCases.filter { $0 != .dev }
    }

    /// Familles du stockage montrées : en Simple, pas les projets de dev ni les outils.
    var visibleKinds: [StorageKind] {
        isDeveloper ? StorageKind.allCases : StorageKind.allCases.filter { $0 != .project && $0 != .appData }
    }

    /// Le rapport limité à ce qui est montré (en Simple, sans les projets de dev ni les outils).
    var visibleReport: StorageReport? {
        guard var report = storage else { return nil }
        let kinds = Set(visibleKinds)
        report.entries = report.entries.filter { kinds.contains($0.kind) }
        return report
    }

    /// Lignes d'une famille telles qu'affichées : en Simple, les caches des outils de dev réunis en une ligne.
    func displayedEntries(of kind: StorageKind, in report: StorageReport) -> [StorageEntry] {
        !isDeveloper && kind == .cache ? report.cacheEntriesGroupingDeveloperTools() : report.entries(of: kind)
    }

    /// Ce qu'on peut récupérer sans risque, parmi ce qui est montré.
    func reclaimable(_ report: StorageReport) -> UInt64 {
        isDeveloper ? report.cacheTotal : report.entries(of: .cache).reduce(0) { $0 + $1.size }
    }

    /// Les vues se reconstruisent quand la langue ou le mode change (leurs textes en dépendent).
    var viewIdentity: String { "\(language.rawValue)-\(experience.rawValue)" }

    func setLanguage(_ setting: LanguageSetting, persist: Bool = true, reload: Bool = true) {
        languageSetting = setting
        if persist { UserDefaults.standard.set(setting.rawValue, forKey: LanguageSetting.defaultsKey) }
        Localization.current = setting.resolved
        language = setting.resolved
        // Les réponses de Claude affichées étaient dans l'ancienne langue ; le cache garde les deux.
        claude = [:]
        guard reload else { return }
        if isDemo {
            apply(DemoData.snapshot())
            docker = DemoData.docker()
        } else {
            refreshAndReorder()
        }
    }

    /// Bouton « Actualiser » : relit tout et retrie.
    func refreshAndReorder() {
        frozenOrder = [:]
        refresh()
    }

    func refresh() {
        guard !isDemo else { return }
        guard !isRefreshing else {
            refreshQueued = true
            return
        }
        isRefreshing = true
        let apps = RunningApps.current()
        let sampler = self.sampler
        let ownBundleID = self.ownBundleID
        let containers = docker?.containers ?? []
        // Services qui se relancent tout seuls : relus au plus toutes les 10 s, et juste après une fermeture.
        let readJobs = Date().timeIntervalSince(keepAliveReadAt) > 10 || !recentCloses.isEmpty
        if readJobs { keepAliveReadAt = Date() }
        Task.detached(priority: .userInitiated) { [weak self] in
            let snapshot = SnapshotBuilder.capture(sampler: sampler, runningApps: apps, ownBundleID: ownBundleID)
            // Qui occupe quel port : une dizaine de millisecondes pour tous les processus de l'utilisateur.
            let ports = PortMap.scan(groups: snapshot.groups, containers: containers)
            let jobs = readJobs ? KeepAliveJob.read() : nil
            await self?.apply(snapshot, ports: ports, jobs: jobs)
        }
    }

    /// Mac fictif pour les captures d'écran : plus aucune lecture du vrai système.
    @ObservationIgnored private(set) var isDemo = false

    func loadDemo(diskLow: Bool = false) {
        isDemo = true
        // Deux explications déjà lues : les captures montrent les coches.
        readLessons = ["memoire", "bases-mac"]
        docker = DemoData.docker()
        let demoSnapshot = DemoData.snapshot()
        apply(demoSnapshot, ports: DemoData.ports(groups: demoSnapshot.groups, containers: docker?.containers ?? []))
        disk = DemoData.disk(low: diskLow)
        storage = DemoData.storage()
        storageReference = DemoData.storagePrevious()
        performance = DemoData.performance()
        energyRates = DemoData.energyRates()
        demoBusiest = DemoData.busiest()
        history = DemoData.history()
        // Mesures récentes fictives : les mini-graphiques des tuiles ont de quoi se dessiner.
        liveSamples = (0..<16).map { index in
            let wave = sin(Double(index) * 0.8)
            return LiveSample(date: Date().addingTimeInterval(Double(index - 16) * 3),
                              memory: UInt64((19.5 + 1.5 * wave + Double(index) * 0.08) * 1_073_741_824),
                              cpu: 6 + 5 * abs(sin(Double(index) * 1.3)) + (index == 15 ? 4 : 0))
        }
        rules = DemoData.rules()
        // `brew services` lance PostgreSQL avec KeepAlive : le cas typique du serveur qui revient.
        keepAliveJobs = [KeepAliveJob(label: "homebrew.mxcl.postgresql@16",
                                      plistPath: NSHomeDirectory() + "/Library/LaunchAgents/homebrew.mxcl.postgresql@16.plist",
                                      pid: 2041, isUser: true)]
    }

    /// Rendu du bandeau « relancé par macOS » (`--relaunch`).
    func showDemoRelaunch() {
        relaunchNotice = RelaunchNotice(title: "postgresql@16", job: keepAliveJobs.first)
    }

    /// Version synchrone pour les modes de débogage.
    func refreshNow() {
        let snapshot = SnapshotBuilder.capture(sampler: sampler, runningApps: RunningApps.current(), ownBundleID: ownBundleID)
        docker = DockerReader.read()
        apply(snapshot, ports: PortMap.scan(groups: snapshot.groups, containers: docker?.containers ?? []))
        disk = DiskReader.read()
    }

    /// Tous les ports en écoute des processus de l'utilisateur (page Ports, recherche par numéro de port).
    private(set) var portEntries: [PortEntry] = []

    /// Ports en écoute, filtrés par la recherche (numéro de port, projet ou programme).
    var visiblePorts: [PortEntry] {
        let needle = query.trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return portEntries }
        return portEntries.filter { entry in
            String(entry.port).hasPrefix(needle) || [entry.groupTitle, entry.processName, entry.location, entry.container]
                .contains { $0?.localizedStandardContains(needle) == true }
        }
    }

    func group(withID id: String) -> ProcessGroup? {
        snapshot?.groups.first { $0.id == id }
    }

    private func apply(_ snapshot: Snapshot, ports: [PortEntry]? = nil, jobs: [KeepAliveJob]? = nil) {
        self.snapshot = snapshot
        recordLiveSample(snapshot)
        if let ports { portEntries = ports }
        if let jobs { keepAliveJobs = jobs }
        detectRelaunches(snapshot)
        var byCategory: [ProcessCategory: [ProcessGroup]] = [:]
        for category in ProcessCategory.allCases {
            let fresh = snapshot.groups(in: category)
            byCategory[category] = stableOrder(fresh, category: category)
        }
        groupsByCategory = byCategory
        isRefreshing = false
        if !isDemo {
            updatePerformance(snapshot)
            checkSpeedAlerts()
            checkRules(snapshot)
        }
        updateCloseStates()
        if refreshQueued {
            refreshQueued = false
            refresh()
        }
    }

    private func stableOrder(_ groups: [ProcessGroup], category: ProcessCategory) -> [ProcessGroup] {
        guard isVisible, let previous = frozenOrder[category] else {
            frozenOrder[category] = groups.map(\.id)
            return groups
        }
        let rank = Dictionary(previous.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        let known = groups.filter { rank[$0.id] != nil }.sorted { rank[$0.id]! < rank[$1.id]! }
        let newcomers = groups.filter { rank[$0.id] == nil }
        let ordered = known + newcomers
        frozenOrder[category] = ordered.map(\.id)
        return ordered
    }

    // MARK: - Affichage

    var isSearching: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }

    func visibleGroups(in category: ProcessCategory) -> [ProcessGroup] {
        let groups = groupsByCategory[category] ?? []
        let needle = query.trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return groups }
        return groups.filter { matches($0, needle) }
    }

    private func matches(_ group: ProcessGroup, _ needle: String) -> Bool {
        let fields = [group.title, group.location, group.bundleID, group.launchedBy, explanationText(for: group).text]
        if fields.contains(where: { $0?.localizedStandardContains(needle) == true }) { return true }
        if group.ports.contains(where: { String($0).hasPrefix(needle) }) { return true }
        // « 3000 » trouve aussi une app qui n'est pas un outil de dev (ports lus pour tous les processus).
        if Int(needle) != nil, portEntries.contains(where: { $0.groupID == group.id && String($0.port).hasPrefix(needle) }) { return true }
        return group.processes.contains { $0.name.localizedStandardContains(needle) || String($0.pid) == needle }
    }

    func isSectionOpen(_ category: ProcessCategory) -> Bool {
        isSearching || !collapsedSections.contains(category)
    }

    private static let openSectionsKey = "sectionsOuvertes"
    private static let openStorageSectionsKey = "sectionsStockageOuvertes"

    /// Sections ouvertes la dernière fois ; aucune au premier lancement, pour un panneau court.
    /// `remember: false` (captures, `--app-sections`) : lit le réglage sans jamais l'écrire.
    func restoreOpenSections(remember: Bool = true) {
        let open = Set(UserDefaults.standard.stringArray(forKey: Self.openSectionsKey) ?? [])
        collapsedSections = Set(ProcessCategory.allCases.filter { !open.contains($0.rawValue) })
        dockerCollapsed = !open.contains("docker")
        let openStorage = Set(UserDefaults.standard.stringArray(forKey: Self.openStorageSectionsKey) ?? [])
        collapsedStorage = Set(StorageKind.allCases.filter { !openStorage.contains($0.rawValue) })
        remembersSections = remember
    }

    private func saveOpenSections() {
        guard remembersSections else { return }
        var open = ProcessCategory.allCases.filter { !collapsedSections.contains($0) }.map(\.rawValue)
        if !dockerCollapsed { open.append("docker") }
        UserDefaults.standard.set(open, forKey: Self.openSectionsKey)
        UserDefaults.standard.set(StorageKind.allCases.filter { !collapsedStorage.contains($0) }.map(\.rawValue),
                                  forKey: Self.openStorageSectionsKey)
    }

    func toggleSection(_ category: ProcessCategory) {
        if collapsedSections.contains(category) {
            collapsedSections.remove(category)
        } else {
            collapsedSections.insert(category)
        }
    }

    func toggleExpanded(_ id: String) {
        withAnimation(VigieMotion.standard) { toggleExpandedNow(id) }
    }

    private func toggleExpandedNow(_ id: String) {
        if expandedGroups.contains(id) {
            expandedGroups.remove(id)
        } else {
            expandedGroups.insert(id)
        }
    }

    func explanationText(for group: ProcessGroup) -> (text: String, fromClaude: Bool) {
        if case .answer(let text)? = claude[group.id] { return (text, true) }
        if let cached = cache.value(for: ClaudeExplainer.subject(for: group).key) { return (cached, true) }
        return (group.explanation.text, false)
    }

    func count(in category: ProcessCategory) -> Int {
        groupsByCategory[category]?.count ?? 0
    }

    // MARK: - Fermeture

    func closeState(_ key: String) -> CloseState? { closeStates[key] }

    func requestConfirmation(_ key: String) {
        closeStates[key] = .confirming
        expiryTasks[key]?.cancel()
        expiryTasks[key] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled, let self, self.closeStates[key] == .confirming else { return }
            self.closeStates[key] = nil
        }
    }

    func cancelConfirmation(_ key: String) {
        expiryTasks[key]?.cancel()
        if closeStates[key] == .confirming { closeStates[key] = nil }
    }

    func confirmClose(_ key: String, methods: [CloseMethod]) {
        expiryTasks[key]?.cancel()
        let pids = methods.flatMap { Closer.perform($0) }
        guard !pids.isEmpty else {
            closeStates[key] = nil
            return
        }
        rememberClose(key, pids: pids)
        closeStates[key] = .closing(since: Date(), pids: pids)
        scheduleFollowUpRefreshes()
    }

    func force(_ key: String) {
        guard case .stuck(let pids)? = closeStates[key] else { return }
        Closer.force(pids)
        closeStates[key] = .closing(since: Date(), pids: pids)
        scheduleFollowUpRefreshes()
    }

    /// Ferme un seul processus (et ses enfants du même groupe).
    func closeProcess(_ process: RawProcess, in group: ProcessGroup) {
        let inGroup = Set(group.processes.map(\.pid))
        let children = snapshot?.descendants(of: process.pid).filter { inGroup.contains($0) } ?? []
        confirmClose("pid:\(process.pid)", methods: [.signal([process.pid] + children)])
    }

    private func scheduleFollowUpRefreshes() {
        for delay in [0.8, 2.5, 5.5] {
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(delay))
                self?.refresh()
            }
        }
    }

    private func updateCloseStates() {
        for (key, state) in closeStates where !key.hasPrefix("docker") {
            guard case .closing(let since, let pids) = state else { continue }
            let alive = pids.filter(ProcessSignals.isAlive)
            if alive.isEmpty {
                closeStates[key] = nil
            } else if Date().timeIntervalSince(since) > 5 {
                closeStates[key] = .stuck(pids: alive)
            }
        }
    }

    // MARK: - Bilan

    /// Bilan lancé par l'œil de la colonne d'icônes (toutes les analyses d'un coup).
    private(set) var checkupStarted: Date?

    struct CheckupStep {
        var title: String
        var done: Bool
    }

    /// Les analyses du bilan et leur état.
    var checkupSteps: [CheckupStep] {
        var steps = [
            CheckupStep(title: tr("ce qui tourne", "what runs"), done: snapshot != nil && performance != nil),
            CheckupStep(title: tr("le disque", "the disk"), done: storage != nil && storageProgress == nil),
            CheckupStep(title: tr("ce qui démarre", "startup"), done: !startupItems.isEmpty || isDemo),
        ]
        if case .done = duplicateSearch {
            steps.append(CheckupStep(title: tr("les doublons", "duplicates"), done: true))
        } else {
            steps.append(CheckupStep(title: tr("les doublons", "duplicates"), done: false))
        }
        if isDeveloper {
            steps.append(CheckupStep(title: tr("tes outils", "your tools"), done: toolchainsLoaded))
        }
        return steps
    }

    var checkupRunning: Bool { checkupStarted != nil && checkupSteps.contains { !$0.done } }

    /// Tout analyser : processus, disque, projets endormis, outils, ce qui démarre, doublons, Docker.
    func runCheckup() {
        checkupStarted = Date()
        refreshAndReorder()
        refreshDocker()
        scanStorage()
        refreshDormantProjects()
        if isDeveloper { refreshToolchains() }
        refreshStartupItems(force: true)
        if case .running = duplicateSearch {} else { findDuplicates() }
    }

    // MARK: - Services relancés par macOS

    /// Services de lancement réglés pour revenir dès qu'ils s'arrêtent (`KeepAlive`), avec leur PID actuel.
    private(set) var keepAliveJobs: [KeepAliveJob] = []
    @ObservationIgnored private var keepAliveReadAt = Date.distantPast
    /// « Mon serveur a été relancé par macOS » : affiché après une fermeture qui n'a pas tenu.
    private(set) var relaunchNotice: RelaunchNotice?

    struct RelaunchNotice: Equatable {
        var title: String
        var job: KeepAliveJob?
    }

    private struct ClosedRecord {
        var title: String
        var pids: Set<Int32>
        var ports: Set<Int>
        var date: Date
    }
    @ObservationIgnored private var recentCloses: [ClosedRecord] = []

    /// Le service qui relance ce groupe : un de ses processus est le service, ou a été lancé par lui.
    func relauncher(for group: ProcessGroup) -> KeepAliveJob? {
        guard !keepAliveJobs.isEmpty, let snapshot else { return nil }
        let pids = Set(group.processes.map(\.pid))
        return keepAliveJobs.first { job in
            pids.contains(job.pid) || !pids.isDisjoint(with: snapshot.descendants(of: job.pid))
        }
    }

    func relauncher(forPID pid: Int32) -> KeepAliveJob? {
        guard let group = snapshot?.groups.first(where: { $0.processes.contains { $0.pid == pid } }) else {
            return keepAliveJobs.first { $0.pid == pid }
        }
        return relauncher(for: group)
    }

    private func rememberClose(_ key: String, pids: [Int32]) {
        let closed = Set(pids)
        guard let group = snapshot?.groups.first(where: { $0.id == key || !closed.isDisjoint(with: $0.processes.map(\.pid)) }) else { return }
        let ports = Set(portEntries.filter { closed.contains($0.pid) }.map(\.port))
        recentCloses.append(ClosedRecord(title: group.title, pids: closed, ports: ports, date: Date()))
        // Le service revient après son délai (10 s par défaut) : on relit encore un peu après.
        for delay in [8.0, 13.0, 20.0] {
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(delay))
                self?.refresh()
            }
        }
    }

    /// Une fermeture « réussie » suivie, quelques secondes après, du même programme (même nom ou même port) :
    /// c'est macOS qui l'a relancé. On le dit au lieu de laisser croire que la fermeture a raté.
    private func detectRelaunches(_ snapshot: Snapshot) {
        recentCloses.removeAll { Date().timeIntervalSince($0.date) > 30 }
        guard !recentCloses.isEmpty else { return }
        var remaining: [ClosedRecord] = []
        for record in recentCloses {
            let back = snapshot.groups.first { group in
                let pids = Set(group.processes.map(\.pid))
                guard pids.isDisjoint(with: record.pids) else { return false }
                let ports = Set(portEntries.filter { pids.contains($0.pid) }.map(\.port))
                return group.title == record.title || !ports.isDisjoint(with: record.ports)
            }
            if let back {
                withAnimation(VigieMotion.standard) {
                    relaunchNotice = RelaunchNotice(title: record.title, job: relauncher(for: back))
                }
            } else {
                remaining.append(record)
            }
        }
        recentCloses = remaining
    }

    func dismissRelaunchNotice() {
        withAnimation(VigieMotion.standard) { relaunchNotice = nil }
    }

    /// Arrête le service pour de bon (ou jusqu'au prochain démarrage). Clé de fermeture « launchd:étiquette ».
    func stopKeepAlive(_ job: KeepAliveJob, forGood: Bool) {
        let key = "launchd:" + job.label
        closeStates[key] = .closing(since: Date(), pids: [])
        Task.detached(priority: .userInitiated) { [weak self] in
            let error = StartupControl.stop(job, forGood: forGood)
            await self?.finishKeepAliveStop(key, job: job, error: error)
        }
    }

    private func finishKeepAliveStop(_ key: String, job: KeepAliveJob, error: String?) {
        closeStates[key] = nil
        if error == nil {
            keepAliveJobs.removeAll { $0.label == job.label }
            if relaunchNotice?.job?.label == job.label { dismissRelaunchNotice() }
        } else {
            startupError = tr("macOS n'a pas accepté l'arrêt du service.", "macOS didn't accept stopping the service.")
        }
        refreshStartupItems(force: true)
        scheduleFollowUpRefreshes()
    }

    // MARK: - Claude

    func askClaude(_ group: ProcessGroup) {
        let subject = ClaudeExplainer.subject(for: group)
        let id = group.id
        claude[id] = .loading
        Task { [weak self] in
            do {
                let answer = try await ClaudeExplainer.explain(subject)
                self?.cache.set(answer, for: subject.key)
                self?.claude[id] = .answer(answer)
            } catch {
                self?.claude[id] = .failed(error.localizedDescription)
            }
        }
    }

    // MARK: - Divers

    // MARK: - Stockage

    func scanStorage() {
        guard storageProgress == nil else { return }
        if isDemo {
            storage = DemoData.storage()
            return
        }
        storageProgress = 0
        showAll = []
        Task.detached(priority: .userInitiated) { [weak self] in
            let report = StorageScanner.scan(progress: { value in
                DispatchQueue.main.async { self?.updateStorageProgress(value) }
            }, partial: { report in
                // La liste se remplit pendant l'analyse : les petits dossiers d'abord, le Bureau et les gros caches ensuite.
                DispatchQueue.main.async { self?.showPartialStorage(report) }
            })
            await self?.finishStorageScan(report)
        }
    }

    private func updateStorageProgress(_ value: Double) {
        if storageProgress != nil { storageProgress = max(storageProgress ?? 0, value) }
    }

    /// Une analyse de plus de 24 h ne dit plus la vérité : on l'oublie, le bouton « Analyser » revient.
    private func forgetExpiredStorage() {
        guard !isDemo, storageProgress == nil, let report = storage, !StorageReportStore.isFresh(report) else { return }
        storage = nil
        expandedStorage = []
        showAll = []
    }

    private func showPartialStorage(_ report: StorageReport) {
        guard storageProgress != nil else { return }
        storage = report
    }

    private func finishStorageScan(_ report: StorageReport) {
        storage = report
        storageProgress = nil
        storageReference = StorageReportStore.save(report)
        if let status = DiskReader.read() { appendHistory(.scan(disk: status, report: report)) }
        if notifyWhenStorageReady, let disk {
            notifyWhenStorageReady = false
            Notifier.diskLow(disk, dockerDisk: docker?.virtualDisk, diagnosis: diskDiagnosis)
        }
        refreshDisk()
    }

    /// Version synchrone pour les captures d'écran du vrai Mac.
    func scanStorageNow() {
        storage = StorageScanner.scan()
    }

    func toggleStorage(_ id: String) {
        withAnimation(VigieMotion.standard) {
            if expandedStorage.contains(id) { expandedStorage.remove(id) } else { expandedStorage.insert(id) }
        }
    }

    // MARK: - Nettoyage

    /// Ce que Vigie peut faire de cette ligne (rien pour tes fichiers, les données d'apps, les dossiers protégés).
    func cleanup(for entry: StorageEntry) -> StorageCleanup? {
        StorageCleaner.cleanup(for: entry, home: entry.path.hasPrefix(DemoData.home) ? DemoData.home : NSHomeDirectory())
    }

    /// Premier clic : demande de confirmation, annulée au bout de 4 s comme pour la fermeture d'une app.
    func requestClean(_ entry: StorageEntry) {
        cleanStates[entry.path] = .confirming
        let path = entry.path
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            if self?.cleanStates[path] == .confirming { self?.cleanStates[path] = nil }
        }
    }

    func cancelClean(_ entry: StorageEntry) {
        if cleanStates[entry.path] == .confirming { cleanStates[entry.path] = nil }
    }

    func clean(_ entry: StorageEntry) {
        guard let cleanup = cleanup(for: entry), cleanStates[entry.path] != .running else { return }
        let path = entry.path
        cleanStates[path] = .running
        if isDemo {
            // Mac fictif : rien n'est touché, on fait comme si.
            finishClean(path: path, cleanup: cleanup, result: .success(entry.size))
            return
        }
        Task.detached(priority: .userInitiated) { [weak self] in
            let result = StorageCleaner.run(cleanup, path: path)
            await self?.finishClean(path: path, cleanup: cleanup, result: result)
        }
    }

    private func finishClean(path: String, cleanup: StorageCleanup, result: Result<UInt64, StorageCleaner.Failure>) {
        switch result {
        case .success(let freed):
            cleanStates[path] = .done(freed: freed, inTrash: cleanup.goesToTrash)
            if cleanup.goesToTrash { noteTrashed(freed) }
            if cleanup == .emptyTrash {
                // Corbeille vidée : ce que Vigie y avait mis est parti aussi.
                trashedByVigie = 0
                UserDefaults.standard.set(0, forKey: "corbeilleVigie")
            }
            // Une commande garde le dossier (plus léger) ; une suppression ou la corbeille le fait disparaître de la liste.
            let removed = !cleanup.isCommand && (isDemo || !FileManager.default.fileExists(atPath: path))
            explorerDidClean(path: path, freed: freed, removed: removed)
            toolchainDidClean(path: path)
            if didCleanDormant(path: path) {
                refreshDisk()
                return
            }
            // Un seul dossier d'un projet endormi : le projet maigrit, et disparaît s'il ne reste rien.
            if let index = dormantProjects.firstIndex(where: { $0.children.contains { $0.path == path } }) {
                dormantProjects[index].children.removeAll { $0.path == path }
                dormantProjects[index].size = dormantProjects[index].children.reduce(0) { $0 + $1.size }
                if dormantProjects[index].children.isEmpty { dormantProjects.remove(at: index) }
            }
            if let report = storage {
                storage = report.afterCleaning(path: path, freed: freed, removed: removed)
                if !isDemo, let storage { StorageReportStore.save(storage) }
            }
            refreshDisk()
        case .failure(.command(let message)), .failure(.file(let message)):
            cleanStates[path] = .failed(message)
        }
    }

    // MARK: - Règles

    /// « Préviens-moi si Slack dépasse 4 Go », « quitte Slack à 19 h » : gardées sur le Mac (clé `reglesVigie`).
    private(set) var rules: [VigieRule] = []
    @ObservationIgnored private var rulesAlerted = Set<UUID>()
    @ObservationIgnored private var lastRuleCheck = Date()

    func addRule(_ rule: VigieRule) {
        rules.append(rule)
        saveRules()
        Notifier.checkPermission { _ in }
    }

    func setRule(_ id: UUID, enabled: Bool) {
        guard let index = rules.firstIndex(where: { $0.id == id }) else { return }
        rules[index].isEnabled = enabled
        saveRules()
    }

    func deleteRule(_ id: UUID) {
        rules.removeAll { $0.id == id }
        rulesAlerted.remove(id)
        saveRules()
    }

    private func saveRules() {
        if !isDemo { RuleStore.save(rules) }
        updateBackgroundMonitoring()
    }

    /// Apps qu'on peut choisir dans une règle : celles ouvertes en ce moment (apps et utilitaires), par nom.
    var ruleCandidates: [(name: String, bundleID: String?)] {
        let groups = (groupsByCategory[.apps] ?? []) + (groupsByCategory[.background] ?? [])
        var seen = Set<String>()
        return groups.filter { RuleEngine.canQuit($0) }
            .map { ($0.title, $0.bundleID) }
            .filter { seen.insert($0.0).inserted }
            .sorted { $0.0.localizedCaseInsensitiveCompare($1.0) == .orderedAscending }
    }

    /// À chaque instantané (toutes les 3 s panneau ouvert, toutes les minutes sinon si une règle existe).
    private func checkRules(_ snapshot: Snapshot) {
        guard !rules.isEmpty else { return }
        let now = Date()
        for alert in RuleEngine.memoryAlerts(rules: rules, groups: snapshot.groups, alerted: &rulesAlerted) {
            Notifier.message(id: "vigie.regle." + alert.rule.id.uuidString, title: alert.title, body: alert.body, quitGroupID: alert.group)
        }
        for rule in rules where RuleEngine.quitIsDue(rule, lastCheck: lastRuleCheck, now: now) {
            quitForRule(rule, in: snapshot)
        }
        lastRuleCheck = now
    }

    /// Fermeture normale (comme ⌘Q), jamais forcée ; si l'app est toujours là 20 s après, on le dit.
    private func quitForRule(_ rule: VigieRule, in snapshot: Snapshot) {
        guard let group = rule.match(in: snapshot.groups), RuleEngine.canQuit(group) else { return }
        let pids = Closer.perform(group.close)
        guard !pids.isEmpty else { return }
        let id = "vigie.regle." + rule.id.uuidString
        Notifier.message(id: id, title: tr("Vigie a quitté \(rule.appName)", "Vigie quit \(rule.appName)"),
                         body: rule.summary.text + ".", quitGroupID: nil)
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(20))
            guard let self, pids.contains(where: { ProcessSignals.isAlive($0) }) else { return }
            Notifier.message(id: id, title: tr("\(rule.appName) ne s'est pas fermée", "\(rule.appName) didn't quit"),
                             body: tr("Elle attend peut-être que tu enregistres un document. Vigie ne force jamais la fermeture.",
                                      "It may be waiting for you to save a document. Vigie never force quits."),
                             quitGroupID: nil)
        }
    }

    // MARK: - Historique

    /// Mesures gardées sur le Mac : une toutes les 3 heures (place, mémoire, apps), plus chaque analyse du stockage.
    private(set) var history: [HistoryPoint] = []
    @ObservationIgnored private var recordingHistory = false

    var historyInsights: [HistoryInsight] { HistoryInsights.make(history) }

    /// Appelé avec la lecture du disque (toutes les 2 minutes, même panneau fermé) : au plus une mesure par 3 heures.
    /// L'instantané des processus est réutilisé s'il a moins de 10 minutes, sinon pris une fois, en arrière-plan.
    private func recordHistoryIfDue(_ disk: DiskStatus) {
        guard !isDemo, !recordingHistory, HistoryStore.isDue(history) else { return }
        if let snapshot, Date().timeIntervalSince(snapshot.date) < 600 {
            appendHistory(.regular(disk: disk, snapshot: snapshot))
            return
        }
        recordingHistory = true
        let sampler = self.sampler
        let ownBundleID = self.ownBundleID
        let apps = RunningApps.current()
        let model = self
        Task.detached(priority: .utility) {
            let snapshot = SnapshotBuilder.capture(sampler: sampler, runningApps: apps, ownBundleID: ownBundleID)
            await MainActor.run {
                model.recordingHistory = false
                model.appendHistory(.regular(disk: disk, snapshot: snapshot))
            }
        }
    }

    private func appendHistory(_ point: HistoryPoint) {
        guard !isDemo else { return }
        history = HistoryStore.appending(point, to: history)
        let points = history
        Task.detached(priority: .utility) { HistoryStore.save(points) }
    }

    // MARK: - Versions et outils de dev

    /// Versions de Node, Python et Ruby, paquets npm globaux et volumes Docker orphelins : lus à l'ouverture de la
    /// page « Versions et outils » (moins d'une seconde), en arrière-plan.
    private(set) var runtimeVersions: [RuntimeVersion] = []
    private(set) var trashableRuntimePaths: Set<String> = []
    private(set) var globalPackages: [GlobalPackage] = []
    private(set) var orphanVolumes: [DockerVolume] = []
    private(set) var toolchainsLoaded = false

    var runtimeEntries: [StorageEntry] {
        runtimeVersions.map { $0.entry(trashable: trashableRuntimePaths.contains($0.path)) }
    }

    func refreshToolchains() {
        if isDemo {
            let demo = DemoData.toolchains()
            runtimeVersions = debugHideVersions ? [] : demo.versions
            trashableRuntimePaths = Set(Toolchains.trashable(demo.versions).map(\.path))
            globalPackages = demo.packages
            orphanVolumes = demo.volumes
            toolchainsLoaded = true
            return
        }
        let running = snapshot?.groups.flatMap { $0.processes.map(\.path) } ?? []
        let projects = (storage?.entries(of: .project) ?? []).map { ($0.path as NSString).deletingLastPathComponent }
        let dockerRunning = docker?.state == .running
        let model = self
        Task.detached(priority: .utility) {
            let versions = Toolchains.measure(Toolchains.find(runningPaths: running, projects: projects))
            let packages = Toolchains.globalPackages(versions: versions)
            let volumes = dockerRunning ? DockerReader.orphanVolumes() : []
            await MainActor.run {
                model.runtimeVersions = versions
                model.trashableRuntimePaths = Set(Toolchains.trashable(versions).map(\.path))
                model.globalPackages = packages
                model.orphanVolumes = volumes
                model.toolchainsLoaded = true
            }
        }
    }

    /// Captures : ne garder que les paquets et les volumes (le bas de la page tient alors dans l'image).
    @ObservationIgnored private var debugHideVersions = false

    func debugOnlyToolchainExtras() {
        debugHideVersions = true
        refreshToolchains()
    }

    /// Après un nettoyage : la version ou le paquet parti disparaît de la page.
    private func toolchainDidClean(path: String) {
        guard isDemo || !FileManager.default.fileExists(atPath: path) else { return }
        runtimeVersions.removeAll { $0.path == path }
        globalPackages.removeAll { $0.path == path }
        trashableRuntimePaths = Set(Toolchains.trashable(runtimeVersions).map(\.path))
    }

    // MARK: - Projets endormis

    /// Projets pas touchés depuis six mois (dépendances et compilations à la corbeille), calculés à l'ouverture
    /// de la page Projets : une ou deux secondes, en arrière-plan.
    private(set) var dormantProjects: [StorageEntry] = []
    @ObservationIgnored private var dormantReportDate: Date?

    func refreshDormantProjects() {
        guard let report = storage, dormantReportDate != report.date else { return }
        dormantReportDate = report.date
        if isDemo {
            dormantProjects = DemoData.dormantProjects()
            return
        }
        let model = self
        Task.detached(priority: .utility) {
            let found = DormantProjects.find(in: report)
            await MainActor.run { model.dormantProjects = found }
        }
    }

    /// Après la mise à la corbeille d'un projet endormi : ses dossiers disparaissent de l'analyse, une par une.
    private func didCleanDormant(path: String) -> Bool {
        guard let project = dormantProjects.first(where: { $0.path == path }) else { return false }
        if var report = storage {
            for child in project.children where !FileManager.default.fileExists(atPath: child.path) || isDemo {
                report = report.afterCleaning(path: child.path, freed: child.size, removed: true)
            }
            storage = report
            dormantReportDate = report.date
            if !isDemo { StorageReportStore.save(report) }
        }
        dormantProjects.removeAll { $0.path == path }
        return true
    }

    // MARK: - Sélection de plusieurs lignes

    /// Lignes cochées (identifiants) : restes d'apps, gros fichiers, `node_modules`… tout ce qui va à la corbeille.
    var storageSelection: Set<String> = []

    enum SelectionState: Equatable {
        case confirming
        case running(done: Int, total: Int)
        case finished(freed: UInt64, failures: Int)
    }

    private(set) var selectionState: SelectionState?

    /// Seul ce qui va à la corbeille se coche : on peut toujours revenir en arrière.
    func isSelectable(_ entry: StorageEntry) -> Bool {
        cleanup(for: entry)?.goesToTrash == true
    }

    func toggleSelection(_ entry: StorageEntry) {
        if storageSelection.contains(entry.id) { storageSelection.remove(entry.id) } else { storageSelection.insert(entry.id) }
        if case .finished? = selectionState { selectionState = nil }
    }

    func setSelection(_ entries: [StorageEntry], selected: Bool) {
        for entry in entries where isSelectable(entry) {
            if selected { storageSelection.insert(entry.id) } else { storageSelection.remove(entry.id) }
        }
        if case .finished? = selectionState { selectionState = nil }
    }

    func clearSelection() {
        storageSelection = []
        if selectionState == .confirming { selectionState = nil }
    }

    var selectedEntries: [StorageEntry] {
        guard !storageSelection.isEmpty, let report = storage else { return [] }
        return (report.entries + dormantProjects + runtimeEntries).filter { storageSelection.contains($0.id) && isSelectable($0) }
    }

    func requestTrashSelection() {
        guard !selectedEntries.isEmpty else { return }
        selectionState = .confirming
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            if self?.selectionState == .confirming { self?.selectionState = nil }
        }
    }

    func cancelTrashSelection() {
        if selectionState == .confirming { selectionState = nil }
    }

    /// Toutes les lignes cochées vont à la corbeille, une par une ; la liste se corrige au fur et à mesure.
    func trashSelection() {
        let items = selectedEntries.compactMap { entry in cleanup(for: entry).map { (entry, $0) } }
        guard !items.isEmpty else { return }
        if case .running? = selectionState { return }
        selectionState = .running(done: 0, total: items.count)
        if isDemo {
            for (entry, _) in items { toolchainDidClean(path: entry.path) }
            for (entry, _) in items where !didCleanDormant(path: entry.path) {
                storage = storage?.afterCleaning(path: entry.path, freed: entry.size, removed: true)
            }
            storageSelection = []
            selectionState = .finished(freed: items.reduce(0) { $0 + $1.0.size }, failures: 0)
            return
        }
        let model = self
        Task.detached(priority: .userInitiated) {
            var freed: UInt64 = 0
            var failures = 0
            for (index, (entry, cleanup)) in items.enumerated() {
                let result = StorageCleaner.run(cleanup, path: entry.path)
                let amount = (try? result.get()) ?? 0
                if case .success = result { freed += amount } else { failures += 1 }
                let removed = !FileManager.default.fileExists(atPath: entry.path)
                await MainActor.run {
                    model.selectionStep(entry: entry, freed: amount, removed: removed, done: index + 1, total: items.count)
                }
            }
            let (total, failed) = (freed, failures)
            await MainActor.run { model.finishSelection(freed: total, failures: failed) }
        }
    }

    private func selectionStep(entry: StorageEntry, freed: UInt64, removed: Bool, done: Int, total: Int) {
        selectionState = .running(done: done, total: total)
        if entry.id.hasPrefix("dormant:") {
            if didCleanDormant(path: entry.path) { storageSelection.remove(entry.id) }
            return
        }
        toolchainDidClean(path: entry.path)
        if removed { storageSelection.remove(entry.id) }
        if let report = storage { storage = report.afterCleaning(path: entry.path, freed: freed, removed: removed) }
    }

    private func finishSelection(freed: UInt64, failures: Int) {
        selectionState = .finished(freed: freed, failures: failures)
        noteTrashed(freed)
        if let storage { StorageReportStore.save(storage) }
        refreshDisk()
    }

    // MARK: - Gros fichiers et doublons

    /// Filtres de la page Gros fichiers (type, « pas ouverts depuis 6 mois »).
    var largeFileFilter = LargeFileFilter()

    enum LargeFilesTab: Hashable { case files, duplicates }
    var largeFilesTab: LargeFilesTab = .files

    enum DuplicateSearch: Equatable {
        case idle
        case running(Double)
        case done([DuplicateGroup], Date)
    }

    private(set) var duplicateSearch: DuplicateSearch = .idle
    /// Copie choisie pour être gardée, par groupe (sinon la copie conseillée, la première).
    var duplicateKeep: [String: String] = [:]
    /// Confirmation et résultat du bouton « Mettre les autres à la corbeille », par groupe.
    private(set) var duplicateStates: [String: CleanState] = [:]

    var duplicateGroups: [DuplicateGroup] {
        if case .done(let groups, _) = duplicateSearch { return groups }
        return []
    }

    /// Doublons dans Bureau, Documents, Téléchargements, Vidéos, Images et Musique. Lit le contenu des fichiers
    /// en double possible : jamais lancé tout seul, seulement par le bouton.
    func findDuplicates() {
        if case .running = duplicateSearch { return }
        duplicateKeep = [:]
        duplicateStates = [:]
        if isDemo {
            duplicateSearch = .done(DemoData.duplicates(), Date())
            return
        }
        duplicateSearch = .running(0)
        // Le modèle vit autant que l'app : le garder pendant la recherche ne retient rien de trop.
        let model = self
        Task.detached(priority: .userInitiated) {
            let groups = DuplicateFinder.find(roots: DuplicateFinder.roots()) { value in
                Task { @MainActor in model.noteDuplicateProgress(value) }
            }
            await MainActor.run { model.duplicateSearch = .done(groups, Date()) }
        }
    }

    private func noteDuplicateProgress(_ value: Double) {
        guard case .running(let current) = duplicateSearch, value > current + 0.01 else { return }
        duplicateSearch = .running(value)
    }

    func kept(in group: DuplicateGroup) -> String {
        duplicateKeep[group.id] ?? group.files.first?.path ?? ""
    }

    func requestTrashDuplicates(_ group: DuplicateGroup) {
        duplicateStates[group.id] = .confirming
        let id = group.id
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            if self?.duplicateStates[id] == .confirming { self?.duplicateStates[id] = nil }
        }
    }

    func cancelTrashDuplicates(_ group: DuplicateGroup) {
        if duplicateStates[group.id] == .confirming { duplicateStates[group.id] = nil }
    }

    /// Les copies non gardées partent à la corbeille (réversible) ; celle choisie ne bouge pas.
    func trashDuplicates(_ group: DuplicateGroup) {
        guard duplicateStates[group.id] != .running else { return }
        let keep = kept(in: group)
        let paths = group.others(keeping: keep)
        let freed = group.freed(keeping: keep)
        let home = isDemo ? DemoData.home : NSHomeDirectory()
        // Garde-fou : jamais hors du dossier personnel, et jamais la copie gardée.
        guard !paths.isEmpty, paths.allSatisfy({ StorageCleaner.isInsideHome($0, home: home) && $0 != keep }) else { return }
        duplicateStates[group.id] = .running
        if isDemo {
            finishTrashDuplicates(group, paths: paths, result: .success(freed))
            return
        }
        Task.detached(priority: .userInitiated) { [weak self] in
            var result: Result<UInt64, StorageCleaner.Failure> = .success(freed)
            for path in paths {
                do { try FileManager.default.trashItem(at: URL(fileURLWithPath: path), resultingItemURL: nil) } catch {
                    result = .failure(.file(error.localizedDescription))
                    break
                }
            }
            await self?.finishTrashDuplicates(group, paths: paths, result: result)
        }
    }

    private func finishTrashDuplicates(_ group: DuplicateGroup, paths: [String], result: Result<UInt64, StorageCleaner.Failure>) {
        switch result {
        case .success(let freed):
            duplicateStates[group.id] = .done(freed: freed, inTrash: true)
            noteTrashed(freed)
            if var report = storage {
                // Le dossier qui contenait chaque copie maigrit d'autant.
                for file in group.files where paths.contains(file.path) {
                    report = report.afterCleaning(path: file.path, freed: file.freed, removed: true)
                }
                storage = report
                if !isDemo { StorageReportStore.save(report) }
            }
            refreshDisk()
        case .failure(.command(let message)), .failure(.file(let message)):
            duplicateStates[group.id] = .failed(message)
        }
    }

    // MARK: - Explorateur

    /// Dossier affiché dans l'explorateur (le dossier personnel au départ).
    private(set) var explorerPath = NSHomeDirectory()
    private(set) var explorerListing: FolderListing?
    private(set) var explorerLoading = false
    /// Mesures déjà faites (chacune couvre 3 niveaux sous son dossier) : descendre ne relance rien.
    @ObservationIgnored private var explorerMeasures: [(root: String, result: DiskUsage.Result)] = []
    /// Dossiers mesurés enfant par enfant : chaque sous-dossier arrive dès qu'il est mesuré.
    @ObservationIgnored private var explorerComposites: [String: ExplorerComposite] = [:]

    struct ExplorerComposite {
        var files: [(name: String, size: UInt64)]
        var sizes: [String: UInt64] = [:]
        var pending: Set<String>

        func listing(path: String, fileMinimum: UInt64) -> FolderListing {
            var items = sizes.map { FolderListing.Item(name: ($0.key as NSString).lastPathComponent, path: $0.key, size: $0.value, isDirectory: true) }
            var other: UInt64 = 0
            for file in files {
                if file.size >= fileMinimum {
                    items.append(FolderListing.Item(name: file.name, path: path + "/" + file.name, size: file.size, isDirectory: false))
                } else {
                    other += file.size
                }
            }
            items.sort { $0.size > $1.size }
            return FolderListing(path: path, size: items.reduce(other) { $0 + $1.size }, items: items, other: other, pending: pending.count)
        }
    }

    var explorerRoot: String { isDemo ? DemoData.home : NSHomeDirectory() }

    /// Bloc choisi dans l'explorateur (un clic) : son détail et son action s'affichent sous la carte.
    var explorerSelection: String?

    /// Ce que Vigie sait d'un bloc : sûr, à vérifier, à garder, et ce qu'il contient de récupérable.
    func explorerAdvice(_ path: String) -> ExplorerAdvice {
        if path.hasSuffix("/" + FolderListing.hiddenGroupName) {
            return ExplorerAdvice.adviseHiddenGroup(members: explorerDisplay?.members ?? [], home: explorerRoot, report: storage)
        }
        return ExplorerAdvice.advise(path: path, home: explorerRoot, report: storage)
    }

    /// Le dossier affiché : en Simple, les dossiers cachés (« .npm », « .cache »…) réunis en un bloc.
    var explorerDisplay: (listing: FolderListing, members: [FolderListing.Item])? {
        guard let listing = explorerListing else { return nil }
        return isDeveloper ? (listing, []) : listing.groupingHiddenItems(title: tr("Dossiers cachés", "Hidden folders"))
    }

    func explore(_ path: String) {
        explorerPath = path
        explorerSelection = nil
        if isDemo {
            explorerListing = DemoData.explorer(path)
            return
        }
        if let composite = explorerComposites[path] {
            explorerListing = composite.listing(path: path, fileMinimum: Self.explorerFileMinimum)
            explorerLoading = composite.sizes.isEmpty && !composite.pending.isEmpty
            return
        }
        for measure in explorerMeasures where path == measure.root || path.hasPrefix(measure.root + "/") {
            if let listing = FolderListing.make(path: path, from: measure.result, root: measure.root) {
                explorerListing = listing
                explorerLoading = false
                return
            }
        }
        measureFolder(path)
    }

    static let explorerFileMinimum: UInt64 = 20_000_000

    /// Chaque sous-dossier est mesuré à part, en parallèle, sur deux niveaux de plus : les petits arrivent tout de
    /// suite, les gros (la bibliothèque, dont macOS protège une partie) ensuite. La carte se remplit en direct.
    private func measureFolder(_ path: String) {
        var directories: [String] = []
        var files: [(name: String, size: UInt64)] = []
        for name in (try? FileManager.default.contentsOfDirectory(atPath: path)) ?? [] {
            var info = stat()
            guard lstat(path + "/" + name, &info) == 0 else { continue }
            if (info.st_mode & S_IFMT) == S_IFDIR {
                directories.append(path + "/" + name)
            } else {
                files.append((name, UInt64(info.st_blocks) * 512))
            }
        }
        explorerComposites[path] = ExplorerComposite(files: files, pending: Set(directories))
        explorerListing = explorerComposites[path]?.listing(path: path, fileMinimum: Self.explorerFileMinimum)
        explorerLoading = !directories.isEmpty
        guard !directories.isEmpty else { return }
        let requests = directories.map { directory -> DiskUsage.Request in
            var request = DiskUsage.Request(path: directory)
            request.recordDepth = 2
            request.explorerFileMinimum = Self.explorerFileMinimum
            return request
        }
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let model = self else { return }
            _ = DiskUsage.measure(requests, completed: { index, result in
                Task { @MainActor in model.childMeasured(parent: path, child: directories[index], result: result) }
            })
        }
    }

    private func childMeasured(parent: String, child: String, result: DiskUsage.Result) {
        explorerMeasures.append((child, result))
        guard var composite = explorerComposites[parent] else { return }
        composite.pending.remove(child)
        if result.exists { composite.sizes[child] = result.total }
        explorerComposites[parent] = composite
        if explorerPath == parent {
            explorerListing = composite.listing(path: parent, fileMinimum: Self.explorerFileMinimum)
            explorerLoading = false
        }
    }

    /// Après un nettoyage lancé depuis l'explorateur : le bloc disparaît ou maigrit, sans tout remesurer.
    private func explorerDidClean(path: String, freed: UInt64, removed: Bool) {
        let parent = (path as NSString).deletingLastPathComponent
        if var composite = explorerComposites[parent], let size = composite.sizes[path] {
            if removed { composite.sizes[path] = nil } else { composite.sizes[path] = size - min(size, freed) }
            explorerComposites[parent] = composite
        }
        explorerMeasures.removeAll { path == $0.root || path.hasPrefix($0.root + "/") || $0.root.hasPrefix(path + "/") }
        guard var listing = explorerListing, let index = listing.items.firstIndex(where: { $0.path == path }) else { return }
        let size = listing.items[index].size
        if removed {
            listing.items.remove(at: index)
            listing.size -= min(listing.size, size)
            if explorerSelection == path { explorerSelection = nil }
        } else {
            listing.items[index].size = size - min(size, freed)
            listing.size -= min(listing.size, freed)
            listing.items.sort { $0.size > $1.size }
        }
        explorerListing = listing
    }

    func remeasureExplorer() {
        explorerMeasures.removeAll()
        explorerComposites.removeAll()
        explore(explorerPath)
    }

    /// Premier affichage : le dossier personnel, mesuré une fois.
    func openExplorer() {
        if explorerListing == nil && !explorerLoading { explore(explorerRoot) }
    }

    // MARK: - Corbeille

    /// Vigie retient ce qu'elle a mis à la corbeille ; le rappel s'efface quand l'espace libre remonte d'autant
    /// (la corbeille a été vidée). Vigie ne lit pas la corbeille : macOS la protège.
    private func noteTrashed(_ bytes: UInt64) {
        guard bytes > 0, !isDemo else { return }
        trashedByVigie += bytes
        UserDefaults.standard.set(Int(trashedByVigie), forKey: "corbeilleVigie")
        UserDefaults.standard.set(Int(disk?.available ?? 0), forKey: "libreApresCorbeille")
    }

    private func checkTrashEmptied(_ status: DiskStatus) {
        guard trashedByVigie > 0 else { return }
        let freeAfter = UInt64(UserDefaults.standard.integer(forKey: "libreApresCorbeille"))
        if status.available >= freeAfter + trashedByVigie / 10 * 8 {
            trashedByVigie = 0
            UserDefaults.standard.set(0, forKey: "corbeilleVigie")
        }
    }

    func openTrash() {
        NSWorkspace.shared.open(URL(fileURLWithPath: NSHomeDirectory() + "/.Trash"))
    }

    // MARK: - Désinstallation

    func canUninstall(_ entry: StorageEntry) -> Bool {
        isDemo ? entry.kind == .application : AppUninstaller.canUninstall(entry)
    }

    func beginUninstall(_ entry: StorageEntry) {
        let selected = AppUninstaller.items(for: entry).filter(\.selected).map(\.path)
        uninstallStates[entry.path] = .choosing(Set(selected))
        expandedStorage.insert(entry.id)
    }

    func toggleUninstallItem(_ path: String, of entry: StorageEntry) {
        guard case .choosing(var selected) = uninstallStates[entry.path] else { return }
        if selected.contains(path) { selected.remove(path) } else { selected.insert(path) }
        uninstallStates[entry.path] = .choosing(selected)
    }

    func cancelUninstall(_ entry: StorageEntry) {
        uninstallStates[entry.path] = nil
    }

    func isRunning(_ appPath: String) -> Bool {
        NSWorkspace.shared.runningApplications.contains { $0.bundleURL?.path == appPath }
    }

    /// L'app est quittée d'abord (comme ⌘Q), puis tout ce qui est coché va à la corbeille.
    func uninstall(_ entry: StorageEntry) {
        guard case .choosing(let selected) = uninstallStates[entry.path], !selected.isEmpty else { return }
        let items = AppUninstaller.items(for: entry).filter { selected.contains($0.path) && $0.blocked == nil }
        uninstallStates[entry.path] = .running
        if isDemo {
            finishUninstall(entry, trashed: items.map(\.path), sizes: items)
            return
        }
        Task { [weak self] in
            guard let self else { return }
            if selected.contains(entry.path) {
                let running = NSWorkspace.shared.runningApplications.filter { $0.bundleURL?.path == entry.path }
                running.forEach { $0.terminate() }
                for _ in 0..<20 where running.contains(where: { !$0.isTerminated }) {
                    try? await Task.sleep(for: .milliseconds(500))
                }
                if running.contains(where: { !$0.isTerminated }) {
                    self.uninstallStates[entry.path] = .failed(tr("\(entry.title.text) ne s'est pas fermée : quitte-la puis réessaie.",
                                                                 "\(entry.title.text) didn't quit: quit it and try again."))
                    return
                }
            }
            // NSWorkspace demande le mot de passe si l'app a été installée par un installeur (dossier de l'administrateur).
            let urls = items.map { URL(fileURLWithPath: $0.path) }
            NSWorkspace.shared.recycle(urls) { trashed, error in
                let paths = trashed.keys.map(\.path)
                Task { @MainActor in
                    if paths.isEmpty, let error {
                        self.uninstallStates[entry.path] = .failed(error.localizedDescription)
                    } else {
                        self.finishUninstall(entry, trashed: paths, sizes: items)
                    }
                }
            }
        }
    }

    private func finishUninstall(_ entry: StorageEntry, trashed: [String], sizes: [AppUninstaller.Item]) {
        let freed = sizes.filter { trashed.contains($0.path) }.reduce(UInt64(0)) { $0 + $1.size }
        uninstallStates[entry.path] = nil
        if var report = storage {
            if trashed.contains(entry.path) {
                report = report.afterCleaning(path: entry.path, freed: entry.size, removed: true)
            } else {
                for item in sizes where trashed.contains(item.path) {
                    report = report.afterCleaning(path: item.path, freed: item.size, removed: true)
                }
            }
            storage = report
            if !isDemo { StorageReportStore.save(report) }
        }
        noteTrashed(freed)
        lastStorageAction = trashed.contains(entry.path)
            ? tr("✓ \(entry.title.text) désinstallée : \(Format.bytes(freed, decimal: true)) dans la corbeille.",
                 "✓ \(entry.title.text) uninstalled: \(Format.bytes(freed, decimal: true)) in the Trash.")
            : tr("✓ \(Format.bytes(freed, decimal: true)) de restes de \(entry.title.text) dans la corbeille.",
                 "✓ \(Format.bytes(freed, decimal: true)) of \(entry.title.text) leftovers in the Trash.")
        refreshDisk()
    }

    // MARK: - État du Mac

    /// L'état en une phrase et une seule action. Sans analyse de moins de 24 h, l'action est d'en lancer une.
    /// L'état à montrer d'abord : le plus urgent entre le disque et la vitesse.
    var health: MacHealth? { MacHealth.worst(diskHealth, speedHealth) }

    var diskHealth: MacHealth? {
        guard let disk else { return nil }
        let fresh = storage.map { isDemo || StorageReportStore.isFresh($0) } ?? false
        let reclaimable = fresh ? safeCleanItems.reduce(UInt64(0)) { $0 + $1.size } : nil
        return MacHealth.evaluate(disk: disk, reclaimable: storageProgress == nil ? reclaimable : nil)
    }

    /// Le bouton de la carte d'état : le récapitulatif du nettoyage sûr, ou l'analyse. Depuis le panneau, on passe
    /// à l'espace disque, où le récapitulatif s'affiche.
    func performHealthAction(fromPanel: Bool, health chosen: MacHealth? = nil) {
        guard let action = (chosen ?? health)?.action else { return }
        switch action {
        case .freeSpace:
            if fromPanel { mode = .storage }
            reviewSafeClean()
        case .scan:
            if fromPanel { mode = .storage }
            scanStorage()
        case .quit(let id, _):
            // Deux clics, comme le × d'une ligne : le premier demande confirmation, le second quitte.
            if closeState(id) == .confirming, let group = snapshot?.groups.first(where: { $0.id == id }) {
                confirmClose(id, methods: [group.close])
            } else {
                requestConfirmation(id)
            }
        case .showMemory:
            if fromPanel { mode = .speed } else { windowPageRequest = .speed }
        }
    }

    // MARK: - Vitesse et batterie

    /// Mémoire, batterie, chaleur et ce qui empêche la veille (lu à chaque actualisation, la veille toutes les 15 s).
    private(set) var performance: PerformanceStatus?
    /// Page que la fenêtre doit afficher (demandée depuis une carte d'état).
    var windowPageRequest: WindowPage?
    /// Question de « Par où commencer » en cours de lecture : l'explication ouverte montre l'étape et « Suivant ».
    /// Nil quand l'explication est ouverte d'ailleurs (thème, lien « En savoir plus »).
    /// Les dernières mesures (une par actualisation, 3 s quand Vigie est ouverte) : mini-graphiques des tuiles.
    private(set) var liveSamples: [LiveSample] = []

    private func recordLiveSample(_ snapshot: Snapshot) {
        let cores = Double(max(ProcessInfo.processInfo.activeProcessorCount, 1))
        let cpu = min(100, snapshot.groups.reduce(0.0) { $0 + $1.cpuPercent } / cores)
        liveSamples.append(LiveSample(date: snapshot.date, memory: snapshot.memoryUsed, cpu: cpu))
        if liveSamples.count > 24 { liveSamples.removeFirst(liveSamples.count - 24) }
    }

    var learnPath: String?

    /// Explications déjà ouvertes (« Comprendre mon Mac » les coche). Gardées entre les lancements, jamais sur le Mac de démo.
    private(set) var readLessons: Set<String> = Set(UserDefaults.standard.stringArray(forKey: "explicationsLues") ?? [])

    /// « Tout décocher » dans les Réglages.
    func resetReadLessons() {
        readLessons = []
        if !isDemo { UserDefaults.standard.removeObject(forKey: "explicationsLues") }
    }

    /// Réglages → Ouverture → « Voir » : la fenêtre rejoue l'animation.
    var introReplay: Date?

    func markLessonRead(_ id: String) {
        guard !readLessons.contains(id) else { return }
        readLessons.insert(id)
        if !isDemo { UserDefaults.standard.set(readLessons.sorted(), forKey: "explicationsLues") }
    }

    // MARK: Ce qui tourne (page fusionnée de la fenêtre)

    enum RunningSort: Hashable { case memory, name }
    /// Familles choisies dans le filtre (vide : tout).
    var runningFilter: Set<ProcessCategory> = []
    var runningSort: RunningSort = .memory

    /// Apps, programmes discrets et macOS, filtrés et triés comme la page le demande (la recherche s'applique).
    var runningGroups: [ProcessGroup] {
        let categories = RunningPage.categories.filter { runningFilter.isEmpty || runningFilter.contains($0) }
        let groups = categories.flatMap { visibleGroups(in: $0) }
        switch runningSort {
        case .memory: return groups.sorted { $0.memory > $1.memory }
        case .name: return groups.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        }
    }
    /// Nouveau design en essai (clé `nouveauDesign`) : seule la Vue d'ensemble l'utilise pour l'instant.
    var redesign = UserDefaults.standard.bool(forKey: "nouveauDesign")
    /// Maquette : étape de l'analyse montrée dans la carte « Analyse en cours » (rendus seulement).
    var demoScanStep: Int?
    /// Maquette : n'afficher qu'une partie de la page (rendus de la partie basse).
    var demoSection: String?
    /// Explication à ouvrir dans « Comprendre mon Mac » (lien « En savoir plus »).
    var lessonRequest: String?
    /// Processeur de chaque groupe sur les dernières minutes, pour repérer une app qui s'emballe.
    @ObservationIgnored private var cpuHistory: [String: [(date: Date, cpu: Double)]] = [:]
    /// Énergie cumulée de chaque groupe au relevé précédent, et puissance moyenne qui en découle (watts).
    @ObservationIgnored private var lastEnergy: [String: (date: Date, nanojoules: UInt64)] = [:]
    private(set) var energyRates: [String: Double] = [:]
    @ObservationIgnored private var lastBlockersRead = Date.distantPast
    @ObservationIgnored private var demoBusiest: BusyApp?

    /// Processeur moyen d'un groupe sur les cinq dernières minutes (ou depuis l'ouverture du panneau).
    func averageCPU(_ group: ProcessGroup) -> Double {
        if isDemo, let busy = demoBusiest, busy.id == group.id { return busy.averageCPU }
        let samples = (cpuHistory[group.id] ?? []).filter { Date().timeIntervalSince($0.date) < 300 }
        guard !samples.isEmpty else { return group.cpuPercent }
        return samples.reduce(0) { $0 + $1.cpu } / Double(samples.count)
    }

    /// Depuis quand une app travaille beaucoup sans s'arrêter (relevés au-dessus de 50 %, du plus récent en remontant).
    func busyStreak(_ id: String) -> (minutes: Int, average: Double)? {
        let streak = (cpuHistory[id] ?? []).reversed().prefix { $0.cpu >= 50 }
        guard let oldest = streak.last else { return nil }
        let average = streak.reduce(0) { $0 + $1.cpu } / Double(streak.count)
        return (Int(Date().timeIntervalSince(oldest.date) / 60), average)
    }

    /// L'app (hors macOS) qui a le plus travaillé, avec depuis combien de minutes on l'observe.
    var busiest: BusyApp? {
        if isDemo { return demoBusiest }
        let groups = (snapshot?.groups ?? []).filter { $0.category != .system && $0.close.isAllowed }
        guard let top = groups.max(by: { averageCPU($0) < averageCPU($1) }) else { return nil }
        if let streak = busyStreak(top.id) {
            return BusyApp(id: top.id, name: top.title, averageCPU: streak.average, minutes: streak.minutes)
        }
        return BusyApp(id: top.id, name: top.title, averageCPU: averageCPU(top), minutes: 0)
    }

    var speedHealth: MacHealth? {
        guard let performance else { return nil }
        return MacHealth.speed(memory: performance.memory, thermal: performance.thermal, busiest: busiest)
    }

    /// Apps rangées par travail du processeur (moyenne), hors macOS.
    var busyGroups: [ProcessGroup] {
        (snapshot?.groups ?? []).filter { $0.category != .system && (isDeveloper || $0.category != .dev) }
            .sorted { averageCPU($0) > averageCPU($1) }
    }

    var memoryGroups: [ProcessGroup] {
        (snapshot?.groups ?? []).filter { $0.category != .system && (isDeveloper || $0.category != .dev) }
            .sorted { $0.memory > $1.memory }
    }

    var energyGroups: [ProcessGroup] {
        (snapshot?.groups ?? []).filter { (energyRates[$0.id] ?? 0) > 0.05 && $0.category != .system && (isDeveloper || $0.category != .dev) }
            .sorted { (energyRates[$0.id] ?? 0) > (energyRates[$1.id] ?? 0) }
    }

    private func updatePerformance(_ snapshot: Snapshot) {
        let now = Date()
        for group in snapshot.groups where group.category != .system {
            var samples = (cpuHistory[group.id] ?? []).filter { now.timeIntervalSince($0.date) < 1800 }
            samples.append((now, group.cpuPercent))
            cpuHistory[group.id] = samples
        }
        let alive = Set(snapshot.groups.map(\.id))
        cpuHistory = cpuHistory.filter { alive.contains($0.key) }
        // Énergie : la différence entre deux relevés donne la puissance moyenne de chaque groupe.
        var rates: [String: Double] = [:]
        for group in snapshot.groups where group.category != .system {
            let total = group.processes.reduce(UInt64(0)) { $0 + (PerformanceReader.energy($1.pid) ?? 0) }
            if let previous = lastEnergy[group.id], total >= previous.nanojoules {
                let seconds = now.timeIntervalSince(previous.date)
                if seconds > 0.5 { rates[group.id] = Double(total - previous.nanojoules) / seconds / 1e9 }
            }
            lastEnergy[group.id] = (now, total)
        }
        if !rates.isEmpty { energyRates = rates }
        let readBlockers = now.timeIntervalSince(lastBlockersRead) > 15
        let previousBlockers = performance?.blockers ?? []
        var status = PerformanceReader.read(includeBlockers: false)
        status.blockers = previousBlockers
        performance = status
        if readBlockers {
            lastBlockersRead = now
            Task.detached(priority: .utility) { [weak self] in
                let blockers = PerformanceReader.sleepBlockers()
                await self?.applyBlockers(blockers)
            }
        }
    }

    private func applyBlockers(_ blockers: [SleepBlocker]) {
        performance?.blockers = blockers
        checkSpeedAlerts()
    }

    // MARK: - Ce qui démarre avec le Mac

    private(set) var startupItems: [StartupItem] = []
    @ObservationIgnored private var startupReadAt = Date.distantPast
    private(set) var startupError: String?

    /// Lu à l'ouverture de la page Vitesse (au plus toutes les 30 s), et après chaque changement.
    func refreshStartupItems(force: Bool = false) {
        if isDemo {
            startupItems = DemoData.startupItems()
            return
        }
        guard force || Date().timeIntervalSince(startupReadAt) > 30 else { return }
        startupReadAt = Date()
        Task.detached(priority: .utility) { [weak self] in
            let items = StartupReader.read()
            await self?.applyStartupItems(items)
        }
    }

    private func applyStartupItems(_ items: [StartupItem]) {
        startupItems = items
    }

    /// Couper ou relancer un de tes agents (réversible, sans mot de passe).
    func setStartupItem(_ item: StartupItem, enabled: Bool) {
        if isDemo {
            if let index = startupItems.firstIndex(where: { $0.id == item.id }) {
                startupItems[index].isEnabled = enabled
                startupItems[index].pid = enabled ? 4242 : nil
            }
            return
        }
        Task.detached(priority: .userInitiated) { [weak self] in
            let error = StartupControl.setEnabled(item, enabled)
            await self?.finishStartupChange(error)
        }
    }

    private func finishStartupChange(_ error: String?) {
        startupError = error.map { _ in tr("macOS n'a pas accepté le changement.", "macOS didn't accept the change.") }
        refreshStartupItems(force: true)
    }

    func openLoginItemsSettings() {
        LoginItem.openSettings()
    }

    // MARK: - Alertes de vitesse (désactivées par défaut)

    /// Prévenir quand le Mac ralentit : Vigie relève alors l'activité une fois par minute, même panneau fermé.
    var speedAlertsEnabled: Bool = UserDefaults.standard.bool(forKey: "alertesVitesse") {
        didSet {
            UserDefaults.standard.set(speedAlertsEnabled, forKey: "alertesVitesse")
            updateBackgroundMonitoring()
            if speedAlertsEnabled { Notifier.checkPermission { [weak self] allowed in self?.notificationsAllowed = allowed } }
        }
    }
    /// macOS autorise-t-il les notifications de Vigie ? (nil : pas encore demandé)
    private(set) var notificationsAllowed: Bool?
    @ObservationIgnored private var monitorTimer: Timer?
    @ObservationIgnored private var alertsSent: [String: Date] = [:]

    func updateBackgroundMonitoring() {
        monitorTimer?.invalidate()
        monitorTimer = nil
        // Les alertes de vitesse et les règles ont besoin d'une actualisation de fond ; sans elles, Vigie ne fait rien au repos.
        guard speedAlertsEnabled || rules.contains(where: \.isEnabled), !isDemo else { return }
        monitorTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                // Panneau ouvert : il actualise déjà toutes les 3 s.
                guard let self, !self.isVisible else { return }
                self.refresh()
            }
        }
    }

    private func checkSpeedAlerts() {
        guard speedAlertsEnabled, !isDemo, !isVisible, let performance else { return }
        let input = SpeedAlertPolicy.Input(busiest: busiest, memory: performance.memory, memoryHog: memoryGroups.first?.title,
                                           thermal: performance.thermal, blockers: performance.blockers,
                                           onBattery: performance.battery.map { !$0.onPower } ?? false)
        for alert in SpeedAlertPolicy.alerts(for: input, lastSent: alertsSent) {
            alertsSent[alert.key] = Date()
            Notifier.speed(alert)
        }
    }

    /// Bouton « Quitter » d'une notification : la fermeture normale de l'app (comme ⌘Q).
    func quitFromNotification(_ id: String) {
        guard let group = snapshot?.groups.first(where: { $0.id == id }), group.close.isAllowed, !group.isProtected else { return }
        confirmClose(id, methods: [group.close])
    }

    func openNotificationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=" + (Bundle.main.bundleIdentifier ?? "")) {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Nettoyer ce qui est sûr

    var safeCleanItems: [StorageEntry] {
        guard let storage else { return [] }
        return SafeCleanup.items(in: storage, home: isDemo ? DemoData.home : NSHomeDirectory())
    }

    func reviewSafeClean() { safeClean = .reviewing }
    func cancelSafeClean() { if safeClean == .reviewing { safeClean = nil } }

    /// Les caches sûrs, un par un (commande officielle ou suppression), avec la progression.
    func runSafeClean() {
        let items = safeCleanItems
        guard !items.isEmpty else { return }
        safeClean = .running(done: 0, total: items.count)
        if isDemo {
            var report = storage
            for item in items { report = report?.afterCleaning(path: item.path, freed: item.size, removed: true) }
            storage = report
            safeClean = .finished(freed: items.reduce(0) { $0 + $1.size }, failures: 0)
            return
        }
        let home = NSHomeDirectory()
        Task.detached(priority: .userInitiated) { [weak self] in
            var freed: UInt64 = 0
            var failures = 0
            for (index, item) in items.enumerated() {
                guard let cleanup = StorageCleaner.cleanup(for: item, home: home) else { continue }
                let result = StorageCleaner.run(cleanup, path: item.path)
                if case .success(let amount) = result { freed += amount } else { failures += 1 }
                let removed = !cleanup.isCommand && !FileManager.default.fileExists(atPath: item.path)
                let amount = (try? result.get()) ?? 0
                await self?.safeCleanStep(path: item.path, freed: amount, removed: removed, done: index + 1, total: items.count)
            }
            await self?.finishSafeClean(freed: freed, failures: failures)
        }
    }

    private func safeCleanStep(path: String, freed: UInt64, removed: Bool, done: Int, total: Int) {
        storage = storage?.afterCleaning(path: path, freed: freed, removed: removed)
        safeClean = .running(done: done, total: total)
    }

    private func finishSafeClean(freed: UInt64, failures: Int) {
        safeClean = .finished(freed: freed, failures: failures)
        if let storage { StorageReportStore.save(storage) }
        refreshDisk()
    }

    func toggleStorageSection(_ kind: StorageKind) {
        withAnimation(VigieMotion.standard) {
            if collapsedStorage.contains(kind) { collapsedStorage.remove(kind) } else { collapsedStorage.insert(kind) }
        }
    }

    /// Filtre par famille ; la section choisie est rouverte si elle était repliée.
    func filterStorage(_ kind: StorageKind?) {
        storageFilter = kind
        if let kind { collapsedStorage.remove(kind) }
    }

    func reveal(path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    func openFullDiskAccessSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }

    func reveal(_ group: ProcessGroup) {
        let path = group.directory ?? group.bundlePath ?? group.executablePath
        guard let path, !path.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    // MARK: - Ouverture au démarrage

    private(set) var loginItemState: LoginItem.State = LoginItem.state
    private(set) var loginItemError: String?

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try LoginItem.set(enabled)
            loginItemError = nil
        } catch {
            loginItemError = tr("macOS a refusé : ", "macOS refused: ") + error.localizedDescription
        }
        loginItemState = LoginItem.state
        if loginItemState == .needsApproval { LoginItem.openSettings() }
    }

    func refreshLoginItemState() {
        loginItemState = LoginItem.state
    }

    // MARK: - Disque et Docker

    func refreshDisk() {
        guard !isDemo, let status = DiskReader.read() else { return }
        disk = status
        recordHistoryIfDue(status)
        checkTrashEmptied(status)
        if diskAlert.update(with: status) {
            alertLowDisk(status)
        }
    }

    /// Quoi vider et ce qui a grossi, d'après la dernière analyse du stockage.
    var diskDiagnosis: DiskDiagnosis? {
        storage.map { DiskDiagnosis.make(report: $0, previous: storageReference) }
    }

    /// Analyse lancée pour l'alerte disque (le bandeau dit « analyse en cours »).
    var isDiagnosingDisk: Bool { notifyWhenStorageReady && storageProgress != nil }

    /// Disque presque plein : on dit tout de suite quoi vider si l'analyse a moins de 24 h ; sinon on la refait
    /// en arrière-plan et la notification part à la fin. Jamais de première analyse sans toi : elle déclencherait
    /// les demandes d'accès de macOS (Bureau, Documents…) au milieu d'autre chose.
    private func alertLowDisk(_ status: DiskStatus) {
        if let report = storage, StorageReportStore.isFresh(report), storageProgress == nil {
            Notifier.diskLow(status, dockerDisk: docker?.virtualDisk, diagnosis: diskDiagnosis)
        } else if FileManager.default.fileExists(atPath: StorageReportStore.defaultURL.path) {
            notifyWhenStorageReady = true
            if storageProgress == nil { scanStorage() }
        } else {
            Notifier.diskLow(status, dockerDisk: docker?.virtualDisk ?? DockerReader.findVirtualDisk(home: NSHomeDirectory()), diagnosis: nil)
        }
    }

    func refreshDocker() {
        guard !isDemo, !isReadingDocker else { return }
        isReadingDocker = true
        Task.detached(priority: .utility) { [weak self] in
            let status = DockerReader.read()
            await self?.applyDocker(status)
        }
    }

    private func applyDocker(_ status: DockerStatus) {
        docker = status
        isReadingDocker = false
    }

    var isDockerOpen: Bool { isSearching || !dockerCollapsed }

    /// Groupes Docker filtrés par la recherche.
    var visibleDockerGroups: [DockerGroup] {
        let groups = docker?.groups ?? []
        let needle = query.trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return groups }
        if "docker".localizedStandardContains(needle) { return groups }
        return groups.filter { group in
            group.title.localizedStandardContains(needle)
                || group.ports.contains { String($0).hasPrefix(needle) }
                || group.containers.contains { $0.name.localizedStandardContains(needle) || $0.image.localizedStandardContains(needle) }
        }
    }

    /// `docker stop` en arrière-plan ; la ligne affiche une roue jusqu'à la fin.
    func stopDocker(_ key: String, ids: [String]) {
        expiryTasks[key]?.cancel()
        guard !ids.isEmpty else { return }
        closeStates[key] = .closing(since: Date(), pids: [])
        dockerError = nil
        if isDemo { return }
        Task.detached(priority: .userInitiated) { [weak self] in
            let succeeded = DockerReader.stop(ids)
            await self?.finishDockerStop(key, succeeded: succeeded)
        }
    }

    private func finishDockerStop(_ key: String, succeeded: Bool) {
        closeStates[key] = nil
        if !succeeded {
            dockerError = tr("Docker n'a pas pu arrêter ce conteneur.", "Docker couldn't stop this container.")
        }
        isReadingDocker = false
        refreshDocker()
    }

    // MARK: - Mises à jour

    func checkForUpdatesIfDue() {
        let lastCheck = UserDefaults.standard.object(forKey: UpdateKeys.lastCheck) as? Date
        guard UpdateChecker.shouldCheckAutomatically(enabled: autoCheckUpdates, lastCheck: lastCheck) else { return }
        checkForUpdates(manual: false)
    }

    func checkForUpdates(manual: Bool) {
        if update == .checking { return }
        guard let current = currentVersion else {
            if manual { update = .failed(tr("Version inconnue : Vigie a été lancée hors de son paquet .app.", "Unknown version: Vigie was launched outside its .app bundle.")) }
            return
        }
        updateCheckWasManual = manual
        let previous = update
        if manual { update = .checking }
        let repository = updateRepository
        Task { [weak self] in
            do {
                let result = try await UpdateChecker.check(current: current, repository: repository)
                UserDefaults.standard.set(Date(), forKey: UpdateKeys.lastCheck)
                guard let self else { return }
                switch result {
                case .available(let release):
                    self.update = .available(release)
                case .upToDate(let latest):
                    self.update = manual ? .upToDate(latest: latest) : .idle
                    if manual { self.dismissUpdateMessage(after: 5) }
                }
            } catch {
                guard let self else { return }
                // Une vérification automatique qui échoue (pas de réseau) reste silencieuse.
                self.update = manual ? .failed(error.localizedDescription) : previous
            }
        }
    }

    /// Le bandeau de mise à jour à montrer, s'il y en a un.
    var visibleUpdate: UpdateState? {
        switch update {
        case .idle:
            return nil
        case .checking, .upToDate, .failed:
            return updateCheckWasManual ? update : nil
        case .available(let release):
            if !updateCheckWasManual && ignoredUpdateVersion == release.version.description { return nil }
            return update
        }
    }

    /// Version fictive pour les captures d'écran (`--demo-update`).
    func showDemoUpdate() {
        let notes = "**Français**\n- Améliorations et corrections.\n\n**English**\n- Improvements and fixes."
        guard let version = Version("0.3.0"), let page = URL(string: "https://github.com/\(updateRepository)/releases") else { return }
        updateCheckWasManual = false
        update = .available(ReleaseInfo(version: version, tag: "v0.3.0", name: "Vigie 0.3.0", notes: notes,
                                        pageURL: page, downloadURL: nil, publishedAt: Date()))
    }

    func ignore(_ release: ReleaseInfo) {
        ignoredUpdateVersion = release.version.description
        UserDefaults.standard.set(release.version.description, forKey: UpdateKeys.ignored)
        updateCheckWasManual = false
        update = .idle
    }

    func dismissUpdateMessage(after delay: TimeInterval = 0) {
        Task { [weak self] in
            if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
            guard let self else { return }
            switch self.update {
            case .upToDate, .failed: self.update = .idle
            default: break
            }
        }
    }

    func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    /// Copie les infos d'un groupe (PID, ports, dossier…) ; le bouton affiche « Copié ✓ » deux secondes.
    func copyInfo(_ group: ProcessGroup) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(GroupReport.text(for: group), forType: .string)
        let key = "info:" + group.id
        copiedCommand = key
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            if self?.copiedCommand == key { self?.copiedCommand = nil }
        }
    }

    func copyCommand(_ command: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)
        copiedCommand = command
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            if self?.copiedCommand == command { self?.copiedCommand = nil }
        }
    }

    func openActivityMonitor() {
        let url = URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app")
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }
}

enum UpdateKeys {
    static let automatic = "verifierMisesAJour"
    static let lastCheck = "derniereVerificationMisesAJour"
    static let ignored = "versionIgnoree"
}


/// Une mesure récente de la mémoire et du processeur.
struct LiveSample: Sendable, Equatable {
    let date: Date
    let memory: UInt64
    /// Processeur utilisé, en % de toute la machine.
    let cpu: Double
}
