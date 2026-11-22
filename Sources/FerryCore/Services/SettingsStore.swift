import Foundation
import Observation

public extension Notification.Name {
    static let ferryHotkeySettingsDidChange = Notification.Name("Ferry.HotkeySettingsDidChange")
    static let ferryUpdateSettingsDidChange = Notification.Name("Ferry.UpdateSettingsDidChange")
}

@MainActor
@Observable
public final class SettingsStore {
    public var settings: AppSettings {
        didSet {
            if oldValue.language != settings.language {
                FerryLocalization.languageSetting = settings.language
                NotificationCenter.default.post(name: .ferryLanguageDidChange, object: nil)
            }
            if oldValue.quickTranslateShortcutEnabled != settings.quickTranslateShortcutEnabled
                || oldValue.quickTranslateShortcut != settings.quickTranslateShortcut
                || oldValue.mainWindowShortcutEnabled != settings.mainWindowShortcutEnabled
                || oldValue.mainWindowShortcut != settings.mainWindowShortcut
                || oldValue.screenshotOCREnabled != settings.screenshotOCREnabled
                || oldValue.screenshotOCRShortcut != settings.screenshotOCRShortcut
                || oldValue.selectionShortcutEnabled != settings.selectionShortcutEnabled
                || oldValue.selectionShortcut != settings.selectionShortcut {
                NotificationCenter.default.post(name: .ferryHotkeySettingsDidChange, object: nil)
            }
            if oldValue.autoCheckForUpdates != settings.autoCheckForUpdates
                || oldValue.realtimeUpdatePushEnabled != settings.realtimeUpdatePushEnabled {
                NotificationCenter.default.post(name: .ferryUpdateSettingsDidChange, object: nil)
            }
            saveSettings()
        }
    }

    public var resolvedLanguage: ResolvedAppLanguage {
        ResolvedAppLanguage.resolve(settings.language)
    }

    public var apiKeys: [ProviderKind: String] {
        didSet {
            saveSecrets()
        }
    }

    public var recentRecords: [TranslationRecord] = []
    public private(set) var cachedTranslationCount: Int = 0
    public private(set) var cacheHitCount: Int = 0

    public var translationCacheCapacity: Int {
        translationCache.capacity
    }

    private var translationCache: TranslationLRUCache
    private var cacheSaveTask: Task<Void, Never>?
    private var hasPendingCacheSave: Bool = false

    private let appSupportDirectory: URL
    private let settingsFileURL: URL
    private let secretsFileURL: URL
    private let recentRecordsFileURL: URL
    private let translationCacheFileURL: URL

    public init(directory: URL? = nil, cacheCapacity: Int = TranslationLRUCache.defaultCapacity) {
        let baseDir: URL
        if let directory {
            baseDir = directory
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
            baseDir = appSupport.appendingPathComponent("Ferry", isDirectory: true)
            Self.migrateLegacyDirectory(
                from: appSupport.appendingPathComponent("LumiTranslate", isDirectory: true),
                to: baseDir
            )
        }

        self.appSupportDirectory = baseDir
        self.settingsFileURL = baseDir.appendingPathComponent("settings.json")
        self.secretsFileURL = baseDir.appendingPathComponent("secrets.json")
        self.recentRecordsFileURL = baseDir.appendingPathComponent("recent_translations.json")
        self.translationCacheFileURL = baseDir.appendingPathComponent("translation_cache.json")
        self.translationCache = TranslationLRUCache(capacity: cacheCapacity)

        try? FileManager.default.createDirectory(at: baseDir, withIntermediateDirectories: true)

        self.settings = Self.loadJSON(from: settingsFileURL) ?? AppSettings()
        self.apiKeys = Self.loadSecrets(from: secretsFileURL)
        self.recentRecords = Self.loadJSON(from: recentRecordsFileURL) ?? []
        if let persistedCache: [TranslationCacheEntry] = Self.loadJSON(from: translationCacheFileURL) {
            self.translationCache.load(entries: persistedCache)
            self.cachedTranslationCount = self.translationCache.count
        }

        // Ensure all provider profiles exist
        for kind in ProviderKind.allCases where self.settings.profiles[kind] == nil {
            self.settings.profiles[kind] = .defaultProfile(for: kind)
        }
        FerryLocalization.languageSetting = self.settings.language
    }

    public func apiKey(for kind: ProviderKind) -> String {
        apiKeys[kind] ?? ""
    }

    public func setAPIKey(_ key: String, for kind: ProviderKind) {
        apiKeys[kind] = key.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var activeAPIKey: String {
        apiKey(for: settings.activeProvider)
    }

    public var hasActiveAPIKey: Bool {
        hasAPIKey(for: settings.activeProvider)
    }

    public func hasAPIKey(for kind: ProviderKind) -> Bool {
        if kind == .custom {
            // Custom provider might point to local Ollama without a key
            let url = profile(for: .custom).baseURL.lowercased()
            if url.contains("localhost") || url.contains("127.0.0.1") {
                return true
            }
        }
        return !apiKey(for: kind).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public func profile(for kind: ProviderKind) -> ProviderProfile {
        settings.profiles[kind] ?? .defaultProfile(for: kind)
    }

    /// Returns a provider profile pinned to the given one-shot or comparison model choice.
    public func profile(for choice: ModelChoice) -> ProviderProfile {
        var resolved = profile(for: choice.provider)
        resolved.model = choice.model
        resolved.customModel = ""
        return resolved
    }

    /// Current global default provider + model.
    public var activeModelChoice: ModelChoice {
        ModelChoice(
            provider: settings.activeProvider,
            model: settings.activeProfile.effectiveModel
        )
    }

    /// Curated model choices grouped by provider (active provider first, followed by other configured providers).
    public func quickSwitchModelGroups(maxPerProvider: Int = 8) -> [(provider: ProviderKind, choices: [ModelChoice])] {
        var orderedProviders: [ProviderKind] = [settings.activeProvider]
        for kind in ProviderKind.allCases where kind != settings.activeProvider && hasAPIKey(for: kind) {
            orderedProviders.append(kind)
        }

        return orderedProviders.compactMap { kind in
            let p = profile(for: kind)
            var seen = Set<String>()
            var names: [String] = []

            func appendIfNew(_ modelName: String) {
                let trimmed = modelName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty, seen.insert(trimmed).inserted else { return }
                names.append(trimmed)
            }

            appendIfNew(p.effectiveModel)
            if let secondary = settings.secondaryModel, secondary.provider == kind {
                appendIfNew(secondary.model)
            }
            for rec in kind.recommendedModels {
                appendIfNew(rec)
            }

            if !p.fetchedModels.isEmpty {
                let prioritized = p.fetchedModels.filter { Self.isHighCapabilityModel($0) }
                for name in prioritized where names.count < maxPerProvider {
                    appendIfNew(name)
                }
                for name in p.fetchedModels where names.count < maxPerProvider {
                    appendIfNew(name)
                }
            }

            let choices = names.prefix(maxPerProvider).map { ModelChoice(provider: kind, model: $0) }
            return choices.isEmpty ? nil : (provider: kind, choices: Array(choices))
        }
    }

    /// Best default model for one-click comparison or strong-model retranslation.
    public func suggestedSecondaryModel(for primary: ModelChoice? = nil) -> ModelChoice? {
        let basePrimary = primary ?? activeModelChoice

        // 1. Respect explicit user preference if configured and distinct from primary.
        if let preferred = settings.secondaryModel,
           preferred != basePrimary,
           preferred.provider == settings.activeProvider || hasAPIKey(for: preferred.provider) {
            return preferred
        }

        // 2. Prefer another configured provider's active model for genuine cross-provider comparison.
        for kind in ProviderKind.allCases where kind != basePrimary.provider && hasAPIKey(for: kind) {
            let candidate = ModelChoice(provider: kind, model: profile(for: kind).effectiveModel)
            if candidate != basePrimary {
                return candidate
            }
        }

        // 3. Fall back to a stronger or alternative model within the same provider.
        let sameProviderModels = profile(for: basePrimary.provider)
            .selectableModels(for: basePrimary.provider)
            .filter { $0 != basePrimary.model }

        if let stronger = sameProviderModels.first(where: { Self.isHighCapabilityModel($0) }) {
            return ModelChoice(provider: basePrimary.provider, model: stronger)
        }
        if let fallback = sameProviderModels.first {
            return ModelChoice(provider: basePrimary.provider, model: fallback)
        }
        return nil
    }

    private static func isHighCapabilityModel(_ model: String) -> Bool {
        let lower = model.lowercased()
        let strongHints = ["reasoner", "max", "pro", "opus", "sonnet", "gpt-4.1", "gpt-4o", "o1", "o3", "r1", "plus"]
        return strongHints.contains { lower.contains($0) }
    }

    public func updateProfile(_ profile: ProviderProfile, for kind: ProviderKind) {
        settings.profiles[kind] = profile
    }

    public func recordTranslation(_ record: TranslationRecord) {
        var updated = recentRecords.filter {
            !($0.sourceText == record.sourceText
              && $0.resolvedLanguage == record.resolvedLanguage
              && $0.mode == record.mode)
        }
        updated.insert(record, at: 0)
        if updated.count > 50 {
            updated = Array(updated.prefix(50))
        }
        recentRecords = updated
        saveRecentRecords()
    }

    public func clearRecentRecords() {
        recentRecords = []
        saveRecentRecords()
    }

    // MARK: - Translation LRU Cache

    /// Looks up a cached translation if caching is enabled, promoting it to most-recently-used.
    public func cachedTranslation(for key: TranslationCacheKey) -> String? {
        guard settings.translationCacheEnabled else { return nil }
        guard let entry = translationCache.get(key) else { return nil }
        cacheHitCount = translationCache.hitCount
        scheduleCacheSave()
        return entry.translatedText
    }

    /// Stores or refreshes a translation in the LRU cache if caching is enabled.
    public func cacheTranslation(_ translatedText: String, for key: TranslationCacheKey) {
        guard settings.translationCacheEnabled else { return }
        translationCache.set(translatedText, for: key)
        cachedTranslationCount = translationCache.count
        saveTranslationCacheNow()
    }

    /// Empties all cached translations and deletes persisted cache entries.
    public func clearTranslationCache() {
        cacheSaveTask?.cancel()
        cacheSaveTask = nil
        hasPendingCacheSave = false
        translationCache.clear()
        cachedTranslationCount = 0
        cacheHitCount = 0
        saveTranslationCacheNow()
    }

    /// Flushes any debounced LRU-order update to disk (call on app termination).
    public func flushTranslationCache() {
        guard hasPendingCacheSave else { return }
        saveTranslationCacheNow()
    }

    // MARK: - Persistence

    private func saveSettings() {
        Self.writeJSON(settings, to: settingsFileURL, restrictedPermissions: false)
    }

    private func saveSecrets() {
        var rawDict: [String: String] = [:]
        for (kind, key) in apiKeys {
            rawDict[kind.rawValue] = key
        }
        Self.writeJSON(rawDict, to: secretsFileURL, restrictedPermissions: true)
    }

    private func saveRecentRecords() {
        Self.writeJSON(recentRecords, to: recentRecordsFileURL, restrictedPermissions: false)
    }

    private func scheduleCacheSave() {
        hasPendingCacheSave = true
        cacheSaveTask?.cancel()
        cacheSaveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            self?.saveTranslationCacheNow()
        }
    }

    private func saveTranslationCacheNow() {
        cacheSaveTask?.cancel()
        cacheSaveTask = nil
        hasPendingCacheSave = false
        Self.writeJSON(translationCache.orderedEntries(), to: translationCacheFileURL, restrictedPermissions: false)
    }

    /// One-time move of data saved under the app's old name (LumiTranslate) so settings,
    /// API keys and history survive the rename. Skipped if the new folder already exists.
    private static func migrateLegacyDirectory(from legacy: URL, to current: URL) {
        let fm = FileManager.default
        guard fm.fileExists(atPath: legacy.path), !fm.fileExists(atPath: current.path) else { return }
        try? fm.moveItem(at: legacy, to: current)
    }

    private static func loadJSON<T: Decodable>(from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(T.self, from: data)
    }

    private static func loadSecrets(from url: URL) -> [ProviderKind: String] {
        guard let raw: [String: String] = loadJSON(from: url) else { return [:] }
        var mapped: [ProviderKind: String] = [:]
        for (k, v) in raw {
            if let kind = ProviderKind(rawValue: k) {
                mapped[kind] = v
            }
        }
        return mapped
    }

    private static func writeJSON<T: Encodable>(_ value: T, to url: URL, restrictedPermissions: Bool) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(value) else { return }
        do {
            try data.write(to: url, options: .atomic)
            if restrictedPermissions {
                try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            }
        } catch {
            // Silently ignore disk write failures in non-critical store
        }
    }
}
