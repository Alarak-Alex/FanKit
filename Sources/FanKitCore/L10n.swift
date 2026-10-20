import Foundation

/// Lookup helpers for the strings that are assembled in Swift rather than
/// written inline in a view.
///
/// The table is loaded by hand from the `lproj` matching the chosen language
/// instead of going through `NSLocalizedString`. `CFBundle` resolves its
/// preferred localization once per process, so switching language would need a
/// relaunch; reading the table directly lets the choice apply immediately.
public enum L10n {
    /// The language the user picked, as an `lproj` code. `nil` follows the system.
    public static var overrideLanguage: String? {
        get {
            let stored = UserDefaults.standard.string(forKey: "appLanguage")
            guard let stored, supported.contains(stored) else { return nil }
            return stored
        }
        set {
            if let newValue {
                UserDefaults.standard.set(newValue, forKey: "appLanguage")
            } else {
                UserDefaults.standard.removeObject(forKey: "appLanguage")
            }
        }
    }

    /// Languages the bundle actually carries a table for.
    private static let supported = ["en", "zh-Hans"]

    private static let lock = NSLock()
    private static var cachedLanguage: String?
    private static var cachedTable: [String: String]?

    /// Text for `key`, falling back to the key itself when it is missing.
    public static func string(_ key: String) -> String {
        table()[key] ?? key
    }

    public static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: string(key), arguments: arguments)
    }

    /// Drops the cache so a language change is picked up by the next lookup.
    public static func invalidate() {
        lock.lock()
        defer { lock.unlock() }
        cachedLanguage = nil
        cachedTable = nil
    }

    /// The language code actually in use, for display in Settings.
    public static var activeLanguageCode: String {
        resolveLanguage()
    }

    private static func table() -> [String: String] {
        let language = resolveLanguage()
        lock.lock()
        defer { lock.unlock() }
        if language == cachedLanguage, let cachedTable {
            return cachedTable
        }
        let loaded = loadTable(language: language, bundle: .main)
        cachedLanguage = language
        cachedTable = loaded
        return loaded
    }

    /// The override wins; otherwise the first localization the bundle supports
    /// and the system prefers; otherwise English.
    private static func resolveLanguage() -> String {
        if let override = overrideLanguage, !override.isEmpty {
            return override
        }
        for preferred in Locale.preferredLanguages {
            if preferred.hasPrefix("zh") { return "zh-Hans" }
            if preferred.hasPrefix("en") { return "en" }
        }
        return "en"
    }

    private static func loadTable(language: String, bundle: Bundle) -> [String: String] {
        let candidates = [language, String(language.prefix(2))]
        for code in candidates {
            if let path = bundle.path(forResource: "Localizable", ofType: "strings",
                                      inDirectory: nil, forLocalization: code),
               let table = NSDictionary(contentsOfFile: path) as? [String: String] {
                return table
            }
        }
        // Development builds run from `.build`, where no lproj exists yet.
        if let path = bundle.path(forResource: "Localizable", ofType: "strings"),
           let table = NSDictionary(contentsOfFile: path) as? [String: String] {
            return table
        }
        return [:]
    }
}
