import FanKitCore
import Foundation

/// The language FanKit presents itself in.
///
/// The choice is stored as a language code and applied immediately: `L10n` reads
/// its table on every lookup, so changing it only needs a fresh render.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case english = "en"
    case simplifiedChinese = "zh-Hans"

    var id: String { rawValue }

    /// Label written in the language itself, so the option is recognisable even
    /// when the rest of the UI is in another language.
    var label: String {
        switch self {
        case .system: return L10n.string("System Default")
        case .english: return "English"
        case .simplifiedChinese: return "简体中文"
        }
    }

    static let defaultsKey = "appLanguage"

    static var current: AppLanguage {
        let stored = UserDefaults.standard.string(forKey: defaultsKey)
        return AppLanguage(rawValue: stored ?? "") ?? .system
    }

    /// The code `L10n` should load, or nil to follow the system.
    var languageCode: String? {
        switch self {
        case .system: return nil
        case .english: return "en"
        case .simplifiedChinese: return "zh-Hans"
        }
    }

    /// Persists the choice and refreshes every localized string.
    static func select(_ language: AppLanguage) {
        UserDefaults.standard.set(language.rawValue, forKey: defaultsKey)
        L10n.overrideLanguage = language.languageCode
        L10n.invalidate()
    }
}
