import Foundation

/// User-selected app interface language. Defaults to following the macOS system language.
public enum AppLanguage: String, CaseIterable, Codable, Identifiable, Sendable {
    case system
    case zhHans = "zh-Hans"
    case en

    public var id: String { rawValue }

    public var displayName: String {
        displayName(in: FerryLocalization.resolved)
    }

    public func displayName(in language: ResolvedAppLanguage) -> String {
        switch self {
        case .system:
            return FerryLocalization.text(zh: "跟随系统", en: "System", in: language)
        case .zhHans:
            return "简体中文"
        case .en:
            return "English"
        }
    }
}

/// Concrete supported UI language after resolving `.system` against `Locale.preferredLanguages`.
public enum ResolvedAppLanguage: String, CaseIterable, Codable, Hashable, Sendable {
    case zhHans = "zh-Hans"
    case en

    public var locale: Locale {
        switch self {
        case .zhHans: return Locale(identifier: "zh_CN")
        case .en: return Locale(identifier: "en_US")
        }
    }

    public var nativeName: String {
        switch self {
        case .zhHans: return "简体中文"
        case .en: return "English"
        }
    }

    /// Resolves `setting` against an ordered list of BCP-47 preferred languages (e.g. `Locale.preferredLanguages`).
    /// For `.system`, picks the first supported language (`zh*` → Simplified Chinese, `en*` → English),
    /// falling back to English when no preferred language matches.
    public static func resolve(
        _ setting: AppLanguage,
        preferredLanguages: [String] = Locale.preferredLanguages
    ) -> ResolvedAppLanguage {
        switch setting {
        case .zhHans:
            return .zhHans
        case .en:
            return .en
        case .system:
            for identifier in preferredLanguages {
                let normalized = identifier.lowercased()
                if normalized == "zh" || normalized.hasPrefix("zh-") || normalized.hasPrefix("zh_") {
                    return .zhHans
                }
                if normalized == "en" || normalized.hasPrefix("en-") || normalized.hasPrefix("en_") {
                    return .en
                }
            }
            return .en
        }
    }
}
