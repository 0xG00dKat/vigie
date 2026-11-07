import Foundation

public enum SnapshotBuilder {
    /// Apps que macOS relance aussitôt : Vigie ne propose pas de les fermer.
    public static let protectedBundleIDs: Set<String> = [
        "com.apple.finder",
        "com.apple.dock",
        "com.apple.systemuiserver",
        "com.apple.controlcenter",
        "com.apple.notificationcenterui",
        "com.apple.loginwindow",
        "com.apple.Spotlight",
        "com.apple.WindowManager",
        "com.apple.wallpaper.agent",
    ]

    public static func capture(sampler: ProcessSampler, runningApps: [RunningApp], ownBundleID: String?) -> Snapshot {
        let processes = sampler.snapshot()
        var protected = protectedBundleIDs
        if let ownBundleID { protected.insert(ownBundleID) }

        let builder = GroupBuilder(
            runningApps: runningApps,
            myUID: getuid(),
            myPID: getpid(),
            homeDirectory: NSHomeDirectory(),
            protectedBundleIDs: protected,
            details: { sampler.details(for: $0) },
            bundleInfo: { BundleInfoCache.shared.info(for: $0) }
        )
        let groups = builder.build(processes)

        var children: [Int32: [Int32]] = [:]
        for process in processes where process.ppid > 0 {
            children[process.ppid, default: []].append(process.pid)
        }
        let memory = SystemMemory.current()
        return Snapshot(
            groups: groups,
            processCount: processes.count,
            memoryUsed: memory.used,
            memoryTotal: memory.total,
            date: Date(),
            children: children
        )
    }
}

/// Lit (une fois) l'Info.plist des paquets .app.
public final class BundleInfoCache: @unchecked Sendable {
    public static let shared = BundleInfoCache()
    private let lock = NSLock()
    private var cache: [String: BundleInfo?] = [:]

    public func info(for bundlePath: String) -> BundleInfo? {
        lock.lock()
        if let cached = cache[bundlePath] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        let plist = (bundlePath as NSString).appendingPathComponent("Contents/Info.plist")
        var info: BundleInfo?
        if let dictionary = NSDictionary(contentsOfFile: plist) as? [String: Any] {
            info = BundleInfo(
                name: (dictionary["CFBundleDisplayName"] as? String) ?? (dictionary["CFBundleName"] as? String),
                bundleID: dictionary["CFBundleIdentifier"] as? String,
                category: dictionary["LSApplicationCategoryType"] as? String,
                version: dictionary["CFBundleShortVersionString"] as? String
            )
        }
        lock.lock()
        cache[bundlePath] = info
        lock.unlock()
        return info
    }
}
