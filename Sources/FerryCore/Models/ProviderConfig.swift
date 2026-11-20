import Foundation

public enum ProviderKind: String, CaseIterable, Codable, Identifiable, Sendable {
    case deepseek
    case bailian
    case custom

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .deepseek: return "DeepSeek"
        case .bailian: return "阿里百炼 (DashScope)"
        case .custom: return "自定义 OpenAI 兼容"
        }
    }

    public var shortName: String {
        switch self {
        case .deepseek: return "DeepSeek"
        case .bailian: return "阿里百炼"
        case .custom: return "自定义"
        }
    }

    public var defaultBaseURL: String {
        switch self {
        case .deepseek:
            return "https://api.deepseek.com/v1"
        case .bailian:
            return "https://dashscope.aliyuncs.com/compatible-mode/v1"
        case .custom:
            return "https://api.openai.com/v1"
        }
    }

    public var recommendedModels: [String] {
        switch self {
        case .deepseek:
            return [
                "deepseek-chat",
                "deepseek-reasoner"
            ]
        case .bailian:
            return [
                "qwen-plus",
                "qwen-turbo",
                "qwen-max",
                "qwen-long"
            ]
        case .custom:
            return [
                "gpt-4o-mini",
                "gpt-4.1-mini"
            ]
        }
    }

    public var defaultModel: String {
        recommendedModels.first ?? "deepseek-chat"
    }

    public var apiKeyHint: String {
        switch self {
        case .deepseek:
            return "在 platform.deepseek.com 创建 API Key（以 sk- 开头）"
        case .bailian:
            return "在阿里云百炼控制台创建 API Key（以 sk- 开头）"
        case .custom:
            return "输入兼容 OpenAI Chat Completions 接口的 API Key（本地 Ollama 可留空或填 ollama）"
        }
    }
}

public struct ProviderProfile: Codable, Equatable, Sendable {
    public var baseURL: String
    public var model: String
    public var customModel: String
    /// Models last fetched from the provider's `/models` endpoint (empty until fetched).
    public var fetchedModels: [String]

    public init(baseURL: String, model: String, customModel: String = "", fetchedModels: [String] = []) {
        self.baseURL = baseURL
        self.model = model
        self.customModel = customModel
        self.fetchedModels = fetchedModels
    }

    private enum CodingKeys: String, CodingKey {
        case baseURL, model, customModel, fetchedModels
    }

    // Custom decoding so settings saved before `fetchedModels` existed still load.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        baseURL = try container.decode(String.self, forKey: .baseURL)
        model = try container.decode(String.self, forKey: .model)
        customModel = try container.decodeIfPresent(String.self, forKey: .customModel) ?? ""
        fetchedModels = try container.decodeIfPresent([String].self, forKey: .fetchedModels) ?? []
    }

    public var effectiveModel: String {
        let trimmedCustom = customModel.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedCustom.isEmpty ? model : trimmedCustom
    }

    /// Models to offer in the picker: the fetched list when available, otherwise the
    /// provider's built-in suggestions. The currently selected model is always included.
    public func selectableModels(for kind: ProviderKind) -> [String] {
        var models = fetchedModels.isEmpty ? kind.recommendedModels : fetchedModels
        if !model.isEmpty && !models.contains(model) {
            models.insert(model, at: 0)
        }
        return models
    }

    /// Base URL with trailing slashes and any `/chat/completions` suffix removed.
    private var normalizedBaseURL: String? {
        var cleaned = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while cleaned.hasSuffix("/") {
            cleaned.removeLast()
        }
        if cleaned.hasSuffix("/chat/completions") {
            cleaned.removeLast("/chat/completions".count)
        }
        return cleaned.isEmpty ? nil : cleaned
    }

    public var chatCompletionsURL: URL? {
        normalizedBaseURL.flatMap { URL(string: "\($0)/chat/completions") }
    }

    public var modelsURL: URL? {
        normalizedBaseURL.flatMap { URL(string: "\($0)/models") }
    }

    public static func defaultProfile(for kind: ProviderKind) -> ProviderProfile {
        ProviderProfile(
            baseURL: kind.defaultBaseURL,
            model: kind.defaultModel,
            customModel: ""
        )
    }
}

/// Window color scheme: follow macOS, or force light / dark.
public enum AppearanceMode: String, CaseIterable, Codable, Identifiable, Sendable {
    case system
    case light
    case dark

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .system: return "跟随系统"
        case .light: return "浅色"
        case .dark: return "深色"
        }
    }
}

public struct AppSettings: Codable, Equatable, Sendable {
    public var activeProvider: ProviderKind
    public var profiles: [ProviderKind: ProviderProfile]
    public var defaultTargetLanguage: TargetLanguage
    public var doubleCopyEnabled: Bool
    public var doubleCopyIntervalMs: Int
    public var desktopWidgetAlwaysOnTop: Bool
    public var temperature: Double
    /// Show a short dictionary entry when a single word or short term is translated.
    public var wordLookupEnabled: Bool
    /// Speech / pronunciation configuration (offline macOS voice or cloud TTS).
    public var speech: SpeechSettings
    public var appearance: AppearanceMode

    public init(
        activeProvider: ProviderKind = .deepseek,
        profiles: [ProviderKind: ProviderProfile] = [
            .deepseek: .defaultProfile(for: .deepseek),
            .bailian: .defaultProfile(for: .bailian),
            .custom: .defaultProfile(for: .custom)
        ],
        defaultTargetLanguage: TargetLanguage = .auto,
        doubleCopyEnabled: Bool = true,
        doubleCopyIntervalMs: Int = 450,
        desktopWidgetAlwaysOnTop: Bool = true,
        temperature: Double = 0.2,
        wordLookupEnabled: Bool = true,
        speech: SpeechSettings = SpeechSettings(),
        appearance: AppearanceMode = .system
    ) {
        self.activeProvider = activeProvider
        self.profiles = profiles
        self.defaultTargetLanguage = defaultTargetLanguage
        self.doubleCopyEnabled = doubleCopyEnabled
        self.doubleCopyIntervalMs = doubleCopyIntervalMs
        self.desktopWidgetAlwaysOnTop = desktopWidgetAlwaysOnTop
        self.temperature = temperature
        self.wordLookupEnabled = wordLookupEnabled
        self.speech = speech
        self.appearance = appearance
    }

    private enum CodingKeys: String, CodingKey {
        case activeProvider, profiles, defaultTargetLanguage, doubleCopyEnabled, doubleCopyIntervalMs
        case desktopWidgetAlwaysOnTop, temperature, wordLookupEnabled, speech, appearance
    }

    // Every field falls back to its default, so settings files from older versions
    // (or with a newly added field missing) load instead of being reset.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = AppSettings()
        activeProvider = try c.decodeIfPresent(ProviderKind.self, forKey: .activeProvider) ?? defaults.activeProvider
        profiles = try c.decodeIfPresent([ProviderKind: ProviderProfile].self, forKey: .profiles) ?? defaults.profiles
        defaultTargetLanguage = try c.decodeIfPresent(TargetLanguage.self, forKey: .defaultTargetLanguage) ?? defaults.defaultTargetLanguage
        doubleCopyEnabled = try c.decodeIfPresent(Bool.self, forKey: .doubleCopyEnabled) ?? defaults.doubleCopyEnabled
        doubleCopyIntervalMs = try c.decodeIfPresent(Int.self, forKey: .doubleCopyIntervalMs) ?? defaults.doubleCopyIntervalMs
        desktopWidgetAlwaysOnTop = try c.decodeIfPresent(Bool.self, forKey: .desktopWidgetAlwaysOnTop) ?? defaults.desktopWidgetAlwaysOnTop
        temperature = try c.decodeIfPresent(Double.self, forKey: .temperature) ?? defaults.temperature
        wordLookupEnabled = try c.decodeIfPresent(Bool.self, forKey: .wordLookupEnabled) ?? defaults.wordLookupEnabled
        speech = try c.decodeIfPresent(SpeechSettings.self, forKey: .speech) ?? defaults.speech
        appearance = try c.decodeIfPresent(AppearanceMode.self, forKey: .appearance) ?? defaults.appearance
    }

    public var activeProfile: ProviderProfile {
        profiles[activeProvider] ?? .defaultProfile(for: activeProvider)
    }
}
