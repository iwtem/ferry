import Foundation
import NaturalLanguage

/// Detects the language of the source text for display ("英语", "日语"…).
public enum LanguageDetection {
    /// Chinese display name of the dominant language, or nil when the text is too short or ambiguous.
    public static func displayName(for text: String) -> String? {
        let sample = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(600))
        guard sample.count >= 2 else { return nil }

        let recognizer = NLLanguageRecognizer()
        recognizer.processString(sample)
        guard let (language, confidence) = recognizer.languageHypotheses(withMaximum: 1).first,
              confidence >= 0.5
        else { return nil }

        switch language {
        case .simplifiedChinese: return "简体中文"
        case .traditionalChinese: return "繁体中文"
        default:
            return Locale(identifier: "zh_CN").localizedString(forLanguageCode: language.rawValue)
        }
    }

    /// Best-effort BCP-47 language code for speech synthesis (e.g. `"en-US"`, `"zh-CN"`, `"ja-JP"`).
    public static func speechLanguageCode(
        for text: String,
        hint: TargetLanguage? = nil,
        englishAccent: EnglishAccent = .us
    ) -> String {
        if let hint, hint != .auto {
            return bcp47Code(for: hint, englishAccent: englishAccent)
        }

        let sample = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(600))
        guard !sample.isEmpty else { return englishAccent.rawValue }

        if TargetLanguage.isPredominantlyChinese(sample) {
            return "zh-CN"
        }

        let recognizer = NLLanguageRecognizer()
        recognizer.processString(sample)
        if let (language, confidence) = recognizer.languageHypotheses(withMaximum: 1).first,
           confidence >= 0.45 {
            switch language {
            case .simplifiedChinese: return "zh-CN"
            case .traditionalChinese: return "zh-TW"
            case .english: return englishAccent.rawValue
            case .japanese: return "ja-JP"
            case .korean: return "ko-KR"
            case .french: return "fr-FR"
            case .german: return "de-DE"
            case .spanish: return "es-ES"
            default:
                return language.rawValue
            }
        }

        return englishAccent.rawValue
    }

    /// DashScope Qwen-TTS `language_type` hint (`"Chinese"`, `"English"`, `"Japanese"`, `"Auto"`, etc.).
    public static func dashScopeLanguageType(for bcp47: String) -> String {
        let prefix = bcp47.split(separator: "-").first.map(String.init)?.lowercased() ?? ""
        switch prefix {
        case "zh": return "Chinese"
        case "en": return "English"
        case "ja": return "Japanese"
        case "ko": return "Korean"
        case "fr": return "French"
        case "de": return "German"
        case "es": return "Spanish"
        default: return "Auto"
        }
    }

    private static func bcp47Code(for target: TargetLanguage, englishAccent: EnglishAccent) -> String {
        switch target {
        case .auto, .en: return englishAccent.rawValue
        case .zhCN: return "zh-CN"
        case .ja: return "ja-JP"
        case .ko: return "ko-KR"
        case .fr: return "fr-FR"
        case .de: return "de-DE"
        case .es: return "es-ES"
        }
    }
}
