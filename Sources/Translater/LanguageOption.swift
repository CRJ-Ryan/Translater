import Foundation

/// Represents a supported translation language with codes for each engine.
struct LanguageOption: Equatable {
    /// Generic short code (also used by MyMemory)
    let code: String
    /// Baidu Translate language code
    let baiduCode: String
    /// Locale identifier used by Apple Translation
    let appleCode: String
    /// Human-readable display name
    let displayName: String

    static let all: [LanguageOption] = [
        LanguageOption(code: "zh",     baiduCode: "zh",  appleCode: "zh-Hans", displayName: "中文（简体）"),
        LanguageOption(code: "zh-TW",  baiduCode: "cht", appleCode: "zh-Hant", displayName: "中文（繁体）"),
        LanguageOption(code: "en",     baiduCode: "en",  appleCode: "en",      displayName: "English"),
        LanguageOption(code: "ja",     baiduCode: "jp",  appleCode: "ja",      displayName: "日本語"),
        LanguageOption(code: "ko",     baiduCode: "kor", appleCode: "ko",      displayName: "한국어"),
        LanguageOption(code: "fr",     baiduCode: "fra", appleCode: "fr",      displayName: "Français"),
        LanguageOption(code: "de",     baiduCode: "de",  appleCode: "de",      displayName: "Deutsch"),
        LanguageOption(code: "es",     baiduCode: "spa", appleCode: "es",      displayName: "Español"),
        LanguageOption(code: "pt",     baiduCode: "pt",  appleCode: "pt",      displayName: "Português"),
        LanguageOption(code: "it",     baiduCode: "it",  appleCode: "it",      displayName: "Italiano"),
        LanguageOption(code: "ru",     baiduCode: "ru",  appleCode: "ru",      displayName: "Русский"),
        LanguageOption(code: "uk",     baiduCode: "ukr", appleCode: "uk",      displayName: "Українська"),
        LanguageOption(code: "ar",     baiduCode: "ara", appleCode: "ar",      displayName: "العربية"),
        LanguageOption(code: "fa",     baiduCode: "per", appleCode: "fa",      displayName: "فارسی"),
        LanguageOption(code: "tr",     baiduCode: "tr",  appleCode: "tr",      displayName: "Türkçe"),
        LanguageOption(code: "th",     baiduCode: "th",  appleCode: "th",      displayName: "ไทย"),
        LanguageOption(code: "vi",     baiduCode: "vie", appleCode: "vi",      displayName: "Tiếng Việt"),
    ]

    static func findByCode(_ code: String) -> LanguageOption {
        all.first { $0.code == code } ?? all[0]
    }

    static func findByAppleCode(_ appleCode: String) -> LanguageOption {
        all.first { $0.appleCode == appleCode } ?? all[0]
    }
}
