import Foundation

/// Represents a supported translation language.
struct LanguageOption: Equatable {
    /// Short code used by MyMemory API (e.g., "zh", "en", "ja")
    let code: String
    /// Locale identifier used by Apple Translation (e.g., "zh-Hans", "en", "ja")
    let appleCode: String
    /// Human-readable display name
    let displayName: String

    static let all: [LanguageOption] = [
        LanguageOption(code: "zh",     appleCode: "zh-Hans", displayName: "中文（简体）"),
        LanguageOption(code: "zh-TW",  appleCode: "zh-Hant", displayName: "中文（繁体）"),
        LanguageOption(code: "en",     appleCode: "en",      displayName: "English"),
        LanguageOption(code: "ja",     appleCode: "ja",      displayName: "日本語"),
        LanguageOption(code: "ko",     appleCode: "ko",      displayName: "한국어"),
        LanguageOption(code: "fr",     appleCode: "fr",      displayName: "Français"),
        LanguageOption(code: "de",     appleCode: "de",      displayName: "Deutsch"),
        LanguageOption(code: "es",     appleCode: "es",      displayName: "Español"),
        LanguageOption(code: "pt",     appleCode: "pt",      displayName: "Português"),
        LanguageOption(code: "it",     appleCode: "it",      displayName: "Italiano"),
        LanguageOption(code: "ru",     appleCode: "ru",      displayName: "Русский"),
        LanguageOption(code: "ar",     appleCode: "ar",      displayName: "العربية"),
        LanguageOption(code: "th",     appleCode: "th",      displayName: "ไทย"),
        LanguageOption(code: "vi",     appleCode: "vi",      displayName: "Tiếng Việt"),
    ]

    /// Look up a language by its short code.
    static func findByCode(_ code: String) -> LanguageOption {
        all.first { $0.code == code } ?? all[0]
    }

    /// Look up a language by its Apple locale identifier.
    static func findByAppleCode(_ appleCode: String) -> LanguageOption {
        all.first { $0.appleCode == appleCode } ?? all[0]
    }
}
