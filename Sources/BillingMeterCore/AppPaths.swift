import Foundation

/// Where the app and the terminal report keep their data and preferences.
///
/// The app was called ClaudeMon until 2026-10-21. `migrateLegacyData()` moves that name's data
/// folder and copies its preferences once, so the usage history (which cannot be rebuilt once
/// Claude Code has deleted old transcripts) survives the rename.
public enum AppPaths {
    public static let bundleIdentifier = "com.bogovich.AIBillingMeter"
    static let legacyBundleIdentifier = "com.bogovich.ClaudeMon"
    static let folderName = "AI Billing Meter"
    static let legacyFolderName = "ClaudeMon"
    static let migratedKey = "migratedFromClaudeMon"

    public static var supportDirectory: URL {
        applicationSupport.appendingPathComponent(folderName, isDirectory: true)
    }

    public static var cacheURL: URL { supportDirectory.appendingPathComponent("usage-cache.json") }
    public static var pricesURL: URL { supportDirectory.appendingPathComponent("pricing.json") }

    /// The app's preferences. The app reads `.standard`; the terminal report reads them by suite.
    public static var defaults: UserDefaults {
        Bundle.main.bundleIdentifier == bundleIdentifier ? .standard
            : UserDefaults(suiteName: bundleIdentifier) ?? .standard
    }

    private static var applicationSupport: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }

    /// Moves `~/Library/Application Support/ClaudeMon` to the new folder when the new one does
    /// not exist yet, and copies preferences the new domain does not have. Safe to call on every
    /// launch, from the app or the terminal report.
    public static func migrateLegacyData(fileManager fm: FileManager = .default) {
        let old = applicationSupport.appendingPathComponent(legacyFolderName, isDirectory: true)
        if fm.fileExists(atPath: old.path), !fm.fileExists(atPath: supportDirectory.path) {
            try? fm.moveItem(at: old, to: supportDirectory)
        }
        let target = defaults
        guard !target.bool(forKey: migratedKey) else { return }
        if let legacy = UserDefaults(suiteName: legacyBundleIdentifier)?.persistentDomain(forName: legacyBundleIdentifier) {
            for (key, value) in legacy where target.object(forKey: key) == nil
                && !key.hasPrefix("NSWindow Frame") && !key.hasPrefix("NSStatusItem") {
                target.set(value, forKey: key)
            }
        }
        target.set(true, forKey: migratedKey)
    }
}
