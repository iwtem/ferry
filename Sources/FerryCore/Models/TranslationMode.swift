import Foundation

/// Prompt preset controlling whether Ferry performs standard translation or writing refinement.
public enum TranslationMode: String, CaseIterable, Codable, Identifiable, Sendable {
    case translate
    case polish
    case grammar
    case concise
    case academic

    public var id: String { rawValue }

    /// True for rewriting / proofreading presets (as opposed to standard translation).
    public var isWritingMode: Bool {
        self != .translate
    }

    /// In writing modes, `.auto` preserves the input text's original language instead of flipping ZH↔EN.
    public func preservesSourceLanguage(for targetLanguage: TargetLanguage) -> Bool {
        isWritingMode && targetLanguage == .auto
    }

    public var symbolName: String {
        switch self {
        case .translate: return "translate"
        case .polish: return "sparkles"
        case .grammar: return "checkmark.seal"
        case .concise: return "briefcase"
        case .academic: return "graduationcap"
        }
    }

    public var displayName: String {
        displayName(in: FerryLocalization.resolved)
    }

    public func displayName(in language: ResolvedAppLanguage) -> String {
        switch self {
        case .translate: return FerryLocalization.text(zh: "标准翻译", en: "Translate", in: language)
        case .polish: return FerryLocalization.text(zh: "地道润色", en: "Natural Polish", in: language)
        case .grammar: return FerryLocalization.text(zh: "语法纠错", en: "Grammar Fix", in: language)
        case .concise: return FerryLocalization.text(zh: "职场简洁", en: "Work & Concise", in: language)
        case .academic: return FerryLocalization.text(zh: "学术表达", en: "Academic Tone", in: language)
        }
    }

    public var shortName: String {
        shortName(in: FerryLocalization.resolved)
    }

    public func shortName(in language: ResolvedAppLanguage) -> String {
        switch self {
        case .translate: return FerryLocalization.text(zh: "翻译", en: "Translate", in: language)
        case .polish: return FerryLocalization.text(zh: "润色", en: "Polish", in: language)
        case .grammar: return FerryLocalization.text(zh: "纠错", en: "Grammar", in: language)
        case .concise: return FerryLocalization.text(zh: "简洁", en: "Concise", in: language)
        case .academic: return FerryLocalization.text(zh: "学术", en: "Academic", in: language)
        }
    }

    public func subtitle(in language: ResolvedAppLanguage) -> String {
        switch self {
        case .translate:
            return FerryLocalization.text(zh: "自然准确的多语种互译", en: "Accurate, natural translation", in: language)
        case .polish:
            return FerryLocalization.text(zh: "母语级流畅表达，去翻译腔", en: "Native-sounding phrasing and flow", in: language)
        case .grammar:
            return FerryLocalization.text(zh: "最小改动修正拼写与语法错误", en: "Fix grammar & spelling with minimal edits", in: language)
        case .concise:
            return FerryLocalization.text(zh: "精炼直接，适合邮件、Slack 与 PR", en: "Clear & concise for email, Slack & PRs", in: language)
        case .academic:
            return FerryLocalization.text(zh: "严谨客观，适合论文与技术文档", en: "Formal, precise academic register", in: language)
        }
    }
}
