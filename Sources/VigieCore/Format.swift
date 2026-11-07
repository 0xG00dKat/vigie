import Foundation

/// Formats selon la langue : « 5,9 Go » / « 5.9 GB », « 1 079 » / « 1,079 », « depuis 2 j 23 h » / « up 2d 23h ».
public enum Format {
    /// Mémoire en unités binaires (comme le Moniteur d'activité) ; disque en unités décimales
    /// (`decimal: true`, comme le Finder, `df -H` et Docker).
    public static func bytes(_ value: UInt64, decimal: Bool = false) -> String {
        let french = Localization.current == .fr
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

    public static func processes(_ count: Int) -> String {
        if Localization.current == .fr { return "\(Self.count(count)) processus" }
        return count == 1 ? "1 process" : "\(Self.count(count)) processes"
    }
}
