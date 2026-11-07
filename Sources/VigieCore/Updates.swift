import Foundation

/// Numéro de version « 0.2.0 » (le « v » des étiquettes Git est ignoré).
public struct Version: Comparable, Sendable, CustomStringConvertible {
    public let components: [Int]

    public init?(_ text: String) {
        var value = text.trimmingCharacters(in: .whitespaces)
        if value.hasPrefix("v") || value.hasPrefix("V") { value.removeFirst() }
        // « 0.3.0-beta.1 » : seule la partie numérique compte.
        let core = value.split(separator: "-").first.map(String.init) ?? value
        let parts = core.split(separator: ".").map { Int($0) }
        guard !parts.isEmpty, parts.allSatisfy({ $0 != nil }) else { return nil }
        components = parts.compactMap { $0 }
    }

    public var description: String { components.map(String.init).joined(separator: ".") }

    public static func < (lhs: Version, rhs: Version) -> Bool {
        let count = max(lhs.components.count, rhs.components.count)
        for index in 0..<count {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right { return left < right }
        }
        return false
    }

    public static func == (lhs: Version, rhs: Version) -> Bool {
        !(lhs < rhs) && !(rhs < lhs)
    }
}

/// Une version publiée sur GitHub (« Releases »).
public struct ReleaseInfo: Sendable, Equatable {
    public var version: Version
    public var tag: String
    public var name: String
    public var notes: String
    public var pageURL: URL
    public var downloadURL: URL?
    public var publishedAt: Date?

    public init(version: Version, tag: String, name: String, notes: String, pageURL: URL, downloadURL: URL?, publishedAt: Date?) {
        self.version = version
        self.tag = tag
        self.name = name
        self.notes = notes
        self.pageURL = pageURL
        self.downloadURL = downloadURL
        self.publishedAt = publishedAt
    }

    public static func == (lhs: ReleaseInfo, rhs: ReleaseInfo) -> Bool { lhs.tag == rhs.tag }

    /// Premières lignes utiles des notes de version, sans la mise en forme Markdown,
    /// dans la langue courante quand les notes ont une partie « Français » et une partie « English ».
    public var summary: String { summary(in: Localization.current) }

    public func summary(in language: Language) -> String {
        let lines = notes.split(whereSeparator: \.isNewline).map { line -> (text: String, isHeading: Bool) in
            let raw = String(line).trimmingCharacters(in: .whitespaces)
            var text = raw
            while let first = text.first, "#*-• ".contains(first) { text.removeFirst() }
            text = text.replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "`", with: "")
            let isHeading = raw.hasPrefix("#") || (raw.hasPrefix("**") && raw.hasSuffix("**"))
            return (text.trimmingCharacters(in: .whitespaces), isHeading)
        }.filter { !$0.text.isEmpty }

        let wanted = language == .fr ? "français" : "english"
        var selected = lines
        if let start = lines.firstIndex(where: { $0.isHeading && $0.text.lowercased() == wanted }) {
            let rest = lines[(start + 1)...]
            let end = rest.firstIndex { $0.isHeading && ["français", "english"].contains($0.text.lowercased()) } ?? rest.endIndex
            selected = Array(rest[..<end])
        }
        return selected.map(\.text).prefix(3).joined(separator: " · ")
    }
}

public enum UpdateCheckResult: Sendable, Equatable {
    case upToDate(latest: Version?)
    case available(ReleaseInfo)
}

/// Vérifie la dernière version publiée sur GitHub. C'est la seule connexion réseau de Vigie :
/// une requête anonyme vers l'API de GitHub, sans aucune donnée envoyée sur le Mac.
public enum UpdateChecker {
    public enum Failure: LocalizedError, Equatable {
        case network(String)
        case unexpectedResponse(Int)

        public var errorDescription: String? {
            switch self {
            case .network(let detail):
                return tr("GitHub ne répond pas (\(detail)).", "GitHub isn't responding (\(detail)).")
            case .unexpectedResponse(let status):
                return tr("Réponse inattendue de GitHub (code \(status)).", "Unexpected answer from GitHub (code \(status)).")
            }
        }
    }

    /// Dépôt par défaut ; un fork peut le changer avec la clé `VigieUpdateRepository` de l'Info.plist.
    public static let defaultRepository = "0xG00dKat/vigie"
    /// Vérification automatique au plus une fois par jour.
    public static let interval: TimeInterval = 24 * 3600

    public static func shouldCheckAutomatically(enabled: Bool, lastCheck: Date?, now: Date = Date()) -> Bool {
        guard enabled else { return false }
        guard let lastCheck else { return true }
        return now.timeIntervalSince(lastCheck) >= interval
    }

    public static func check(current: Version, repository: String = defaultRepository,
                             session: URLSession = .shared) async throws -> UpdateCheckResult {
        guard let url = URL(string: "https://api.github.com/repos/\(repository)/releases/latest") else {
            throw Failure.unexpectedResponse(0)
        }
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        // GitHub exige un User-Agent : le nom et la version de l'app, rien d'autre.
        request.setValue("Vigie/\(current)", forHTTPHeaderField: "User-Agent")
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw Failure.network(error.localizedDescription)
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        // 404 : aucune version publiée pour l'instant.
        if status == 404 { return .upToDate(latest: nil) }
        guard status == 200 else { throw Failure.unexpectedResponse(status) }
        guard let release = parseLatest(data) else { throw Failure.unexpectedResponse(status) }
        return release.version > current ? .available(release) : .upToDate(latest: release.version)
    }

    /// Lit la réponse de `GET /repos/{dépôt}/releases/latest`.
    public static func parseLatest(_ data: Data) -> ReleaseInfo? {
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              object["draft"] as? Bool != true, object["prerelease"] as? Bool != true,
              let tag = object["tag_name"] as? String, let version = Version(tag),
              let page = (object["html_url"] as? String).flatMap(URL.init(string:)) else { return nil }
        let assets = object["assets"] as? [[String: Any]] ?? []
        let zip = assets.first { ($0["name"] as? String)?.lowercased().hasSuffix(".zip") == true }
        let formatter = ISO8601DateFormatter()
        return ReleaseInfo(
            version: version,
            tag: tag,
            name: (object["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? tag,
            notes: object["body"] as? String ?? "",
            pageURL: page,
            downloadURL: (zip?["browser_download_url"] as? String).flatMap(URL.init(string:)),
            publishedAt: (object["published_at"] as? String).flatMap(formatter.date(from:))
        )
    }
}
