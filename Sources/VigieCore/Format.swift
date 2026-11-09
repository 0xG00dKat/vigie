import Foundation

/// Formats selon la langue : « 5,9 Go » / « 5.9 GB », « 1 079 » / « 1,079 », « depuis 2 j 23 h » / « up 2d 23h ».
public enum Format {
    /// Mémoire en unités binaires (comme le Moniteur d'activité) ; disque en unités décimales
    /// (`decimal: true`, comme le Finder, `df -H` et Docker).
    public static func bytes(_ value: UInt64, decimal: Bool = false) -> String {
        bytes(value, decimal: decimal, in: Localization.current)
    }

    public static func bytes(_ value: UInt64, decimal: Bool = false, in language: Language) -> String {
        let french = language == .fr
        let megaUnit = french ? "Mo" : "MB"
        let gigaUnit = french ? "Go" : "GB"
        let mega: Double = decimal ? 1_000_000 : 1_048_576
        let megabytes = Double(value) / mega
        if megabytes < 1 { return "< 1 \(megaUnit)" }
        if megabytes < 1000 { return "\(Int(megabytes.rounded())) \(megaUnit)" }
        let gigabytes = megabytes / (decimal ? 1000 : 1024)
        var text = gigabytes < 10 ? String(format: "%.1f", gigabytes) : String(format: "%.0f", gigabytes)
        if french { text = text.replacingOccurrences(of: ".", with: ",") }
        return "\(text) \(gigaUnit)"
    }

    private static let formatters: [Language: NumberFormatter] = {
        var result: [Language: NumberFormatter] = [:]
        for (language, locale) in [(Language.fr, "fr_FR"), (Language.en, "en_US")] {
            let formatter = NumberFormatter()
            formatter.locale = Locale(identifier: locale)
            formatter.numberStyle = .decimal
            result[language] = formatter
        }
        return result
    }()

    public static func count(_ value: Int) -> String {
        formatters[Localization.current]?.string(from: NSNumber(value: value)) ?? String(value)
    }

    /// `nil` sous 1 % : inutile d'afficher du bruit.
    public static func cpu(_ percent: Double) -> String? {
        guard percent >= 1 else { return nil }
        let value = Int(percent.rounded())
        return Localization.current == .fr ? "\(value) % CPU" : "\(value)% CPU"
    }

    public static func uptime(since start: Date, now: Date = Date()) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(start)))
        let days = seconds / 86_400
        let hours = (seconds % 86_400) / 3600
        let minutes = (seconds % 3600) / 60
        if Localization.current == .fr {
            if seconds < 60 { return "depuis \(seconds) s" }
            if seconds < 3600 { return "depuis \(minutes) min" }
            if days == 0 { return minutes == 0 ? "depuis \(hours) h" : "depuis \(hours) h \(String(format: "%02d", minutes))" }
            return hours == 0 ? "depuis \(days) j" : "depuis \(days) j \(hours) h"
        }
        if seconds < 60 { return "up \(seconds)s" }
        if seconds < 3600 { return "up \(minutes)m" }
        if days == 0 { return minutes == 0 ? "up \(hours)h" : "up \(hours)h \(String(format: "%02d", minutes))m" }
        return hours == 0 ? "up \(days)d" : "up \(days)d \(hours)h"
    }

    /// « il y a 3 mois » / « 3 months ago », dans une langue donnée.
    public static func ago(_ date: Date, in language: Language, now: Date = Date()) -> String {
        let days = max(0, Int(now.timeIntervalSince(date) / 86_400))
        let french = language == .fr
        func plural(_ n: Int, _ fr: String, _ frPlural: String, _ en: String) -> String {
            french ? "il y a \(n) \(n > 1 ? frPlural : fr)" : "\(n) \(en)\(n > 1 ? "s" : "") ago"
        }
        if days < 1 { return french ? "aujourd'hui" : "today" }
        if days < 31 { return plural(days, "jour", "jours", "day") }
        if days < 365 { return plural(days / 30, "mois", "mois", "month") }
        return plural(days / 365, "an", "ans", "year")
    }

    /// « à l'instant », « il y a 12 min », « il y a 3 h », puis comme `ago`.
    public static func elapsed(since date: Date, in language: Language = Localization.current, now: Date = Date()) -> String {
        let minutes = max(0, Int(now.timeIntervalSince(date) / 60))
        let french = language == .fr
        if minutes < 1 { return french ? "à l'instant" : "just now" }
        if minutes < 60 { return french ? "il y a \(minutes) min" : "\(minutes) min ago" }
        if minutes < 24 * 60 { return french ? "il y a \(minutes / 60) h" : "\(minutes / 60) h ago" }
        return ago(date, in: language, now: now)
    }

    /// Nombre de photos de téléphone (environ 4 Mo chacune) que représente une taille, arrondi (« 45 000 »).
    public static func photos(_ bytes: UInt64, in language: Language = Localization.current) -> String {
        let count = Double(bytes) / 4_000_000
        let magnitude = count >= 1000 ? pow(10, floor(log10(count)) - 1) : (count >= 100 ? 10 : 1)
        let rounded = Int((count / magnitude).rounded() * magnitude)
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: language == .fr ? "fr_FR" : "en_US")
        return formatter.string(from: NSNumber(value: rounded)) ?? "\(rounded)"
    }

    public static func processes(_ count: Int) -> String {
        if Localization.current == .fr { return "\(Self.count(count)) processus" }
        return count == 1 ? "1 process" : "\(Self.count(count)) processes"
    }
}
