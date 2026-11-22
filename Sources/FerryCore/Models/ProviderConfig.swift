import Foundation

public enum ProviderKind: String, CaseIterable, Codable, Identifiable, Sendable {
    case deepseek
    case bailian
    case custom

    public var id: String { rawValue }

    public var displayName: String {
        displayName(in: FerryLocalization.resolved)
    }

    public func displayName(in language: ResolvedAppLanguage) -> String {
        switch self {
        case .deepseek: return "DeepSeek"
        case .bailian: return FerryLocalization.text(zh: "阿里百炼 (DashScope)", en: "Alibaba Bailian (DashScope)", in: language)
        case .custom: return FerryLocalization.text(zh: "自定义 OpenAI 兼容", en: "Custom OpenAI-Compatible", in: language)
        }
    }

    public var shortName: String {
        shortName(in: FerryLocalization.resolved)
    }

    public func shortName(in language: ResolvedAppLanguage) -> String {
        switch self {
        case .deepseek: return "DeepSeek"
        case .bailian: return FerryLocalization.text(zh: "阿里百炼", en: "Bailian", in: language)
        case .custom: return FerryLocalization.text(zh: "自定义", en: "Custom", in: language)
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
        apiKeyHint(in: FerryLocalization.resolved)
    }

    public func apiKeyHint(in language: ResolvedAppLanguage) -> String {
        switch self {
        case .deepseek:
            return FerryLocalization.text(
                zh: "在 platform.deepseek.com 创建 API Key（以 sk- 开头）",
                en: "Create an API Key at platform.deepseek.com (starts with sk-)",
                in: language
            )
        case .bailian:
            return FerryLocalization.text(
                zh: "在阿里云百炼控制台创建 API Key（以 sk- 开头）",
                en: "Create an API Key in the Alibaba Cloud Bailian console (starts with sk-)",
                in: language
            )
        case .custom:
            return FerryLocalization.text(
                zh: "输入兼容 OpenAI Chat Completions 接口的 API Key（本地 Ollama 可留空或填 ollama）",
                en: "Enter an OpenAI Chat Completions compatible API Key (leave blank or use 'ollama' for local Ollama)",
                in: language
            )
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
    var normalizedBaseURL: String? {
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

/// Identifies a specific provider + model target for one-shot retranslation or dual-model comparison.
public struct ModelChoice: Codable, Hashable, Identifiable, Sendable {
    public let provider: ProviderKind
    public let model: String

    public var id: String { "\(provider.rawValue)::\(model)" }

    public init(provider: ProviderKind, model: String) {
        self.provider = provider
        self.model = model
    }

    public func displayLabel(in language: ResolvedAppLanguage) -> String {
        "\(provider.shortName(in: language)) · \(model)"
    }
}

/// Window color scheme: follow macOS, or force light / dark.
public enum AppearanceMode: String, CaseIterable, Codable, Identifiable, Sendable {
    case system
    case light
    case dark

    public var id: String { rawValue }

    public var displayName: String {
        displayName(in: FerryLocalization.resolved)
    }

    public func displayName(in language: ResolvedAppLanguage) -> String {
        switch self {
        case .system: return FerryLocalization.text(zh: "跟随系统", en: "System", in: language)
        case .light: return FerryLocalization.text(zh: "浅色", en: "Light", in: language)
        case .dark: return FerryLocalization.text(zh: "深色", en: "Dark", in: language)
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
    /// Automatically merge wrapped PDF line breaks and de-hyphenate split words before translating.
    public var pdfLineBreakFixEnabled: Bool
    /// Cache translation results locally (LRU) so repeated lookups return immediately without using tokens.
    public var translationCacheEnabled: Bool
    /// Speech / pronunciation configuration (offline macOS voice or cloud TTS).
    public var speech: SpeechSettings
    public var appearance: AppearanceMode
    /// App interface language (defaults to following the macOS system language).
    public var language: AppLanguage
    /// Enable the global shortcut for toggling the menu bar quick-translate panel.
    public var quickTranslateShortcutEnabled: Bool
    /// Global shortcut for toggling the menu bar quick-translate panel (defaults to ⌥Space).
    public var quickTranslateShortcut: HotkeyShortcut
    /// Enable the global shortcut for opening/toggling the standalone main window.
    public var mainWindowShortcutEnabled: Bool
    /// Global shortcut for opening/toggling the standalone main window (defaults to ⌥⇧F).
    public var mainWindowShortcut: HotkeyShortcut
    /// Enable the global shortcut for interactive screenshot OCR translation.
    public var screenshotOCREnabled: Bool
    /// Global shortcut for interactive screenshot OCR translation (defaults to ⌥⇧S).
    public var screenshotOCRShortcut: HotkeyShortcut
    /// Enable the global shortcut for capturing selected text to translate/polish & replace in place.
    public var selectionShortcutEnabled: Bool
    /// Global shortcut for selection translate / polish & replace (defaults to ⌥⇧R).
    public var selectionShortcut: HotkeyShortcut
    /// Automatically check GitHub Releases for newer versions on launch and periodically.
    public var autoCheckForUpdates: Bool
    /// Automatically download verified release archives in the background when a new version is found.
    public var autoDownloadUpdates: Bool
    /// Subscribe to real-time SSE release push events so new releases download within seconds of publishing.
    public var realtimeUpdatePushEnabled: Bool
    /// Optional preferred secondary/strong model used for one-click comparison & retranslation (`nil` = auto-pick).
    public var secondaryModel: ModelChoice?
    /// Optional version string the user chose to skip reminders for.
    public var skippedUpdateVersion: String?

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
        pdfLineBreakFixEnabled: Bool = true,
        translationCacheEnabled: Bool = true,
        speech: SpeechSettings = SpeechSettings(),
        appearance: AppearanceMode = .system,
        language: AppLanguage = .system,
        quickTranslateShortcutEnabled: Bool = true,
        quickTranslateShortcut: HotkeyShortcut = .defaultQuickTranslate,
        mainWindowShortcutEnabled: Bool = true,
        mainWindowShortcut: HotkeyShortcut = .defaultMainWindow,
        screenshotOCREnabled: Bool = true,
        screenshotOCRShortcut: HotkeyShortcut = .defaultScreenshotOCR,
        selectionShortcutEnabled: Bool = true,
        selectionShortcut: HotkeyShortcut = .defaultSelectionTranslate,
        autoCheckForUpdates: Bool = true,
        autoDownloadUpdates: Bool = true,
        realtimeUpdatePushEnabled: Bool = true,
        secondaryModel: ModelChoice? = nil,
        skippedUpdateVersion: String? = nil
    ) {
        self.activeProvider = activeProvider
        self.profiles = profiles
        self.defaultTargetLanguage = defaultTargetLanguage
        self.doubleCopyEnabled = doubleCopyEnabled
        self.doubleCopyIntervalMs = doubleCopyIntervalMs
        self.desktopWidgetAlwaysOnTop = desktopWidgetAlwaysOnTop
        self.temperature = temperature
        self.wordLookupEnabled = wordLookupEnabled
        self.pdfLineBreakFixEnabled = pdfLineBreakFixEnabled
        self.translationCacheEnabled = translationCacheEnabled
        self.speech = speech
        self.appearance = appearance
        self.language = language
        self.quickTranslateShortcutEnabled = quickTranslateShortcutEnabled
        self.quickTranslateShortcut = quickTranslateShortcut
        self.mainWindowShortcutEnabled = mainWindowShortcutEnabled
        self.mainWindowShortcut = mainWindowShortcut
        self.screenshotOCREnabled = screenshotOCREnabled
        self.screenshotOCRShortcut = screenshotOCRShortcut
        self.selectionShortcutEnabled = selectionShortcutEnabled
        self.selectionShortcut = selectionShortcut
        self.autoCheckForUpdates = autoCheckForUpdates
        self.autoDownloadUpdates = autoDownloadUpdates
        self.realtimeUpdatePushEnabled = realtimeUpdatePushEnabled
        self.secondaryModel = secondaryModel
        self.skippedUpdateVersion = skippedUpdateVersion
    }

    private enum CodingKeys: String, CodingKey {
        case activeProvider, profiles, defaultTargetLanguage, doubleCopyEnabled, doubleCopyIntervalMs
        case desktopWidgetAlwaysOnTop, temperature, wordLookupEnabled, pdfLineBreakFixEnabled, translationCacheEnabled
        case speech, appearance, language
        case quickTranslateShortcutEnabled, quickTranslateShortcut
        case mainWindowShortcutEnabled, mainWindowShortcut
        case screenshotOCREnabled, screenshotOCRShortcut
        case selectionShortcutEnabled, selectionShortcut
        case autoCheckForUpdates, autoDownloadUpdates, realtimeUpdatePushEnabled, secondaryModel, skippedUpdateVersion
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
        pdfLineBreakFixEnabled = try c.decodeIfPresent(Bool.self, forKey: .pdfLineBreakFixEnabled) ?? defaults.pdfLineBreakFixEnabled
        translationCacheEnabled = try c.decodeIfPresent(Bool.self, forKey: .translationCacheEnabled) ?? defaults.translationCacheEnabled
        speech = try c.decodeIfPresent(SpeechSettings.self, forKey: .speech) ?? defaults.speech
        appearance = try c.decodeIfPresent(AppearanceMode.self, forKey: .appearance) ?? defaults.appearance
        language = try c.decodeIfPresent(AppLanguage.self, forKey: .language) ?? defaults.language
        quickTranslateShortcutEnabled = try c.decodeIfPresent(Bool.self, forKey: .quickTranslateShortcutEnabled) ?? defaults.quickTranslateShortcutEnabled
        quickTranslateShortcut = try c.decodeIfPresent(HotkeyShortcut.self, forKey: .quickTranslateShortcut) ?? defaults.quickTranslateShortcut
        mainWindowShortcutEnabled = try c.decodeIfPresent(Bool.self, forKey: .mainWindowShortcutEnabled) ?? defaults.mainWindowShortcutEnabled
        mainWindowShortcut = try c.decodeIfPresent(HotkeyShortcut.self, forKey: .mainWindowShortcut) ?? defaults.mainWindowShortcut
        screenshotOCREnabled = try c.decodeIfPresent(Bool.self, forKey: .screenshotOCREnabled) ?? defaults.screenshotOCREnabled
        screenshotOCRShortcut = try c.decodeIfPresent(HotkeyShortcut.self, forKey: .screenshotOCRShortcut) ?? defaults.screenshotOCRShortcut
        selectionShortcutEnabled = try c.decodeIfPresent(Bool.self, forKey: .selectionShortcutEnabled) ?? defaults.selectionShortcutEnabled
        selectionShortcut = try c.decodeIfPresent(HotkeyShortcut.self, forKey: .selectionShortcut) ?? defaults.selectionShortcut
        autoCheckForUpdates = try c.decodeIfPresent(Bool.self, forKey: .autoCheckForUpdates) ?? defaults.autoCheckForUpdates
        autoDownloadUpdates = try c.decodeIfPresent(Bool.self, forKey: .autoDownloadUpdates) ?? defaults.autoDownloadUpdates
        realtimeUpdatePushEnabled = try c.decodeIfPresent(Bool.self, forKey: .realtimeUpdatePushEnabled) ?? defaults.realtimeUpdatePushEnabled
        secondaryModel = try c.decodeIfPresent(ModelChoice.self, forKey: .secondaryModel) ?? defaults.secondaryModel
        skippedUpdateVersion = try c.decodeIfPresent(String.self, forKey: .skippedUpdateVersion) ?? defaults.skippedUpdateVersion
    }

    public var activeProfile: ProviderProfile {
        profiles[activeProvider] ?? .defaultProfile(for: activeProvider)
    }

    public func isHotkeyEnabled(_ action: GlobalHotkeyAction) -> Bool {
        switch action {
        case .quickTranslate: return quickTranslateShortcutEnabled
        case .mainWindow: return mainWindowShortcutEnabled
        case .selectionTranslate: return selectionShortcutEnabled
        case .screenshotOCR: return screenshotOCREnabled
        }
    }

    public func hotkeyShortcut(for action: GlobalHotkeyAction) -> HotkeyShortcut {
        switch action {
        case .quickTranslate: return quickTranslateShortcut
        case .mainWindow: return mainWindowShortcut
        case .selectionTranslate: return selectionShortcut
        case .screenshotOCR: return screenshotOCRShortcut
        }
    }

    /// Returns enabled hotkey actions that share the same key combination with another enabled Ferry action.
    public func conflictingHotkeyActions() -> Set<GlobalHotkeyAction> {
        var seen: [HotkeyShortcut: GlobalHotkeyAction] = [:]
        var conflicts: Set<GlobalHotkeyAction> = []
        for action in GlobalHotkeyAction.allCases {
            guard isHotkeyEnabled(action) else { continue }
            let shortcut = hotkeyShortcut(for: action)
            guard shortcut.isValid else { continue }
            if let existing = seen[shortcut] {
                conflicts.insert(existing)
                conflicts.insert(action)
            } else {
                seen[shortcut] = action
            }
        }
        return conflicts
    }
}
