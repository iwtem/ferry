import Foundation

public enum TargetLanguage: String, CaseIterable, Codable, Identifiable, Sendable {
    case auto = "auto"
    case zhCN = "zh-CN"
    case en = "en"
    case ja = "ja"
    case ko = "ko"
    case fr = "fr"
    case de = "de"
    case es = "es"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .auto: return "自动 (中↔英)"
        case .zhCN: return "简体中文"
        case .en: return "English"
        case .ja: return "日本語"
        case .ko: return "한국어"
        case .fr: return "Français"
        case .de: return "Deutsch"
        case .es: return "Español"
        }
    }

    public var shortName: String {
        switch self {
        case .auto: return "中↔英"
        case .zhCN: return "中文"
        case .en: return "英文"
        case .ja: return "日语"
        case .ko: return "韩语"
        case .fr: return "法语"
        case .de: return "德语"
        case .es: return "西语"
        }
    }

    public var promptLanguageName: String {
        switch self {
        case .auto: return "Simplified Chinese or English"
        case .zhCN: return "Simplified Chinese (简体中文)"
        case .en: return "natural, idiomatic English"
        case .ja: return "natural Japanese (日本語)"
        case .ko: return "natural Korean (한국어)"
        case .fr: return "natural French (Français)"
        case .de: return "natural German (Deutsch)"
        case .es: return "natural Spanish (Español)"
        }
    }

    /// Plain English name of the language, used in the translation prompt.
    public var englishName: String {
        switch self {
        case .auto: return "Simplified Chinese or English"
        case .zhCN: return "Simplified Chinese"
        case .en: return "English"
        case .ja: return "Japanese"
        case .ko: return "Korean"
        case .fr: return "French"
        case .de: return "German"
        case .es: return "Spanish"
        }
    }

    /// `target_lang` value for Alibaba qwen-mt `translation_options`.
    public var qwenMTLanguageName: String {
        switch self {
        case .auto, .zhCN: return "Chinese"
        default: return englishName
        }
    }

    /// Resolves `.auto` to `.en` when source text is predominantly Chinese, otherwise `.zhCN`.
    public func resolvedTarget(for sourceText: String) -> TargetLanguage {
        guard self == .auto else { return self }
        return Self.isPredominantlyChinese(sourceText) ? .en : .zhCN
    }

    /// Heuristic detection of Chinese text based on CJK Unified Ideograph ratio.
    public static func isPredominantlyChinese(_ text: String) -> Bool {
        var cjkCount = 0
        var latinCount = 0
        var kanaOrHangulCount = 0

        for scalar in text.unicodeScalars {
            let v = scalar.value
            if (0x4E00...0x9FFF).contains(v) || (0x3400...0x4DBF).contains(v) || (0xF900...0xFAFF).contains(v) {
                cjkCount += 1
            } else if (0x3040...0x30FF).contains(v) || (0xAC00...0xD7AF).contains(v) {
                // Hiragana, Katakana, or Hangul -> Japanese/Korean text should translate into Chinese
                kanaOrHangulCount += 1
            } else if (0x0041...0x005A).contains(v) || (0x0061...0x007A).contains(v) {
                latinCount += 1
            }
        }

        if kanaOrHangulCount > 0 && kanaOrHangulCount * 3 >= cjkCount {
            return false
        }
        if cjkCount == 0 {
            return false
        }
        // Treat text as Chinese if CJK characters make up a meaningful share relative to Latin letters.
        // Note: a Chinese word is typically 1-2 chars while an English word averages ~5 chars.
        return cjkCount * 3 >= latinCount
    }
}
