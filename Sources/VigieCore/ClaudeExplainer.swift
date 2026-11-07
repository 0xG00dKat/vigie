import Foundation

/// Demande une explication à Claude via la commande `claude` déjà installée (ton compte Claude Code).
/// Seuls le nom, l'identifiant et le chemin de l'exécutable sont envoyés : jamais les arguments,
/// qui peuvent contenir des jetons.
public enum ClaudeExplainer {
    public enum Failure: LocalizedError {
        case cliNotFound
        case failed(status: Int32, output: String)
        case timedOut
        case unusable

        public var errorDescription: String? {
            switch self {
            case .unusable:
                return tr("La réponse de Claude n'était pas exploitable. Réessaie.",
                          "Claude's answer wasn't usable. Try again.")
            case .cliNotFound:
                return tr("La commande claude (Claude Code) est introuvable sur ce Mac.",
                          "The claude command (Claude Code) wasn't found on this Mac.")
            case .failed(let status, let output):
                if output.localizedCaseInsensitiveContains("login") || output.localizedCaseInsensitiveContains("auth") {
                    return tr("Claude Code n'est pas connecté : lance « claude auth login » dans un terminal.",
                              "Claude Code isn't signed in: run “claude auth login” in a terminal.")
                }
                return tr("Claude n'a pas répondu (code \(status)).", "Claude didn't answer (code \(status)).")
            case .timedOut:
                return tr("Claude met trop de temps à répondre. Réessaie plus tard.",
                          "Claude is taking too long to answer. Try again later.")
            }
        }
    }

    public struct Subject: Sendable, Hashable {
        public var key: String
        public var prompt: String
        public var systemPrompt: String
    }

    public static func subject(for group: ProcessGroup, home: String = NSHomeDirectory(), language: Language = Localization.current) -> Subject {
        let french = language == .fr
        let unknown = french ? "inconnu" : "unknown"
        let executable = group.executablePath.map { PathRules.abbreviate($0, home: home) } ?? unknown
        let what: String
        var key: String
        if let bundlePath = group.bundlePath, group.category != .system {
            let location = PathRules.abbreviate(bundlePath, home: home)
            what = french
                ? "l'application « \(group.title) » (identifiant \(group.bundleID ?? unknown), emplacement \(location))"
                : "the app “\(group.title)” (identifier \(group.bundleID ?? unknown), location \(location))"
            key = "app|\(group.bundleID ?? location)"
        } else if group.category == .dev {
            let names = Array(Set(group.processes.map(\.name))).sorted().prefix(6).joined(separator: ", ")
            let origin = french
                ? (group.launchedBy.map { "lancé depuis \($0)" } ?? "qui tourne en arrière-plan")
                : (group.launchedBy.map { "started from \($0)" } ?? "running in the background")
            what = french
                ? "un groupe de processus de développement « \(names) » \(origin) (exécutable principal \(executable))"
                : "a group of development processes “\(names)” \(origin) (main executable \(executable))"
            key = "dev|\(names)|\(executable)"
        } else {
            what = french
                ? "le processus « \(group.title) » (exécutable \(executable))"
                : "the process “\(group.title)” (executable \(executable))"
            key = "proc|\(group.title)|\(executable)"
        }
        // Les réponses françaises gardent leurs anciennes clés de cache ; les anglaises sont préfixées.
        if !french { key = "en|" + key }
        let prompt = french
            ? "Qu'est-ce que \(what) ? Est-il sans risque de le fermer ?"
            : "What is \(what)? Is it safe to close it?"
        return Subject(key: key, prompt: prompt, systemPrompt: french ? systemPromptFrench : systemPromptEnglish)
    }

    /// Remplace les consignes d'agent de Claude Code : sans outils, le modèle tenterait sinon d'en appeler.
    static let systemPromptFrench = """
    Tu expliques en français simple, à quelqu'un qui n'est pas développeur, ce que sont les applications et \
    processus qui tournent sur son Mac. Tutoie-le. Tu n'as accès à aucun outil et tu ne peux rien vérifier : \
    réponds directement, de mémoire, en trois phrases courtes au maximum, sans titre, sans liste et sans mise en forme. \
    Termine en disant s'il est sans risque de le fermer. Si tu ne connais pas le programme, dis-le simplement \
    et déduis prudemment ce que tu peux de son nom et de son emplacement.
    """

    static let systemPromptEnglish = """
    You explain in plain English, to someone who isn't a developer, what the apps and processes running on \
    their Mac are. You have no tools and cannot check anything: answer directly, from memory, in three short \
    sentences at most, with no title, no list and no formatting. End by saying whether it is safe to close it. \
    If you don't know the program, just say so and carefully infer what you can from its name and location.
    """

    /// Écarte une réponse qui ressemble à une tentative d'appel d'outil plutôt qu'à une explication.
    static func isUsable(_ answer: String) -> Bool {
        let markers = ["<invoke", "<parameter", "<function_calls", "antml:"]
        return !answer.isEmpty && answer.count < 1500 && !markers.contains { answer.contains($0) }
    }

    public static func findCLI(home: String = NSHomeDirectory()) -> URL? {
        let candidates = [
            home + "/.local/bin/claude",
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude",
            home + "/.claude/local/claude",
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }.map { URL(fileURLWithPath: $0) }
    }

    public static func explain(_ subject: Subject, timeout: TimeInterval = 90) async throws -> String {
        guard let cli = findCLI() else { throw Failure.cliNotFound }
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = cli
                // Pas d'outils, pas de serveurs MCP, pas de session enregistrée : une simple question.
                process.arguments = [
                    "-p", "--model", "sonnet",
                    "--system-prompt", subject.systemPrompt,
                    "--tools", "",
                    "--strict-mcp-config",
                    "--no-session-persistence",
                    "--disable-slash-commands",
                    subject.prompt,
                ]
                process.currentDirectoryURL = FileManager.default.temporaryDirectory
                let home = NSHomeDirectory()
                var environment = ProcessInfo.processInfo.environment.filter {
                    $0.key != "CLAUDECODE" && !$0.key.hasPrefix("CLAUDE_CODE_")
                }
                environment["PATH"] = "\(home)/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
                process.environment = environment

                let output = Pipe()
                process.standardOutput = output
                process.standardError = FileHandle.nullDevice
                process.standardInput = FileHandle.nullDevice

                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: error)
                    return
                }

                var timedOut = false
                let watchdog = DispatchWorkItem {
                    if process.isRunning {
                        timedOut = true
                        process.terminate()
                    }
                }
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: watchdog)

                let data = output.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                watchdog.cancel()

                let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                if timedOut {
                    continuation.resume(throwing: Failure.timedOut)
                } else if process.terminationStatus == 0, isUsable(text) {
                    continuation.resume(returning: text)
                } else if process.terminationStatus == 0 {
                    continuation.resume(throwing: Failure.unusable)
                } else {
                    continuation.resume(throwing: Failure.failed(status: process.terminationStatus, output: text))
                }
            }
        }
    }
}

/// Réponses de Claude gardées sur le disque, pour ne pas reposer la même question.
public final class ExplanationCache: @unchecked Sendable {
    public static let shared = ExplanationCache()
    private let lock = NSLock()
    private var store: [String: String] = [:]
    private let fileURL: URL

    public init(directory: URL? = nil) {
        let base = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Vigie", isDirectory: true)
        fileURL = base.appendingPathComponent("explications-claude.json")
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
            store = decoded
        }
    }

    public func value(for key: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return store[key]
    }

    public func set(_ value: String, for key: String) {
        lock.lock()
        store[key] = value
        let snapshot = store
        lock.unlock()
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(snapshot) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}
