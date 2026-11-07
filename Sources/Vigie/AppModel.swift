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

@Observable
@MainActor
final class AppModel {
    private(set) var snapshot: Snapshot?
    private(set) var groupsByCategory: [ProcessCategory: [ProcessGroup]] = [:]
    var query = ""
    var expandedGroups: Set<String> = []
    var collapsedSections: Set<ProcessCategory> = [.system]
    private(set) var closeStates: [String: CloseState] = [:]
    private(set) var claude: [String: ClaudeState] = [:]
    private(set) var languageSetting: LanguageSetting = .automatic
    private(set) var disk: DiskStatus?
    private(set) var docker: DockerStatus?
    var dockerCollapsed = false
    private(set) var dockerError: String?
    private(set) var copiedCommand: String?
    private(set) var update: UpdateState = .idle
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
            refresh()
            refreshDisk()
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

    func setVisible(_ visible: Bool) {
        guard visible != isVisible else { return }
        isVisible = visible
        if visible {
            frozenOrder = [:]
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
        Task.detached(priority: .userInitiated) { [weak self] in
            let snapshot = SnapshotBuilder.capture(sampler: sampler, runningApps: apps, ownBundleID: ownBundleID)
            await self?.apply(snapshot)
        }
    }

    /// Mac fictif pour les captures d'écran : plus aucune lecture du vrai système.
    @ObservationIgnored private(set) var isDemo = false

    func loadDemo(diskLow: Bool = false) {
        isDemo = true
        apply(DemoData.snapshot())
        docker = DemoData.docker()
        disk = DemoData.disk(low: diskLow)
    }

    /// Version synchrone pour les modes de débogage.
    func refreshNow() {
        let snapshot = SnapshotBuilder.capture(sampler: sampler, runningApps: RunningApps.current(), ownBundleID: ownBundleID)
        apply(snapshot)
        disk = DiskReader.read()
        docker = DockerReader.read()
    }

    private func apply(_ snapshot: Snapshot) {
        self.snapshot = snapshot
        var byCategory: [ProcessCategory: [ProcessGroup]] = [:]
        for category in ProcessCategory.allCases {
            let fresh = snapshot.groups(in: category)
            byCategory[category] = stableOrder(fresh, category: category)
        }
        groupsByCategory = byCategory
        isRefreshing = false
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
        return group.processes.contains { $0.name.localizedStandardContains(needle) || String($0.pid) == needle }
    }

    func isSectionOpen(_ category: ProcessCategory) -> Bool {
        isSearching || !collapsedSections.contains(category)
    }

    func toggleSection(_ category: ProcessCategory) {
        if collapsedSections.contains(category) {
            collapsedSections.remove(category)
        } else {
            collapsedSections.insert(category)
        }
    }

    func toggleExpanded(_ id: String) {
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
        if diskAlert.update(with: status) {
            Notifier.diskLow(status, dockerDisk: docker?.virtualDisk ?? DockerReader.findVirtualDisk(home: NSHomeDirectory()))
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
