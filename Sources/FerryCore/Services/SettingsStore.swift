import Foundation
import Observation

@MainActor
@Observable
public final class SettingsStore {
    public var settings: AppSettings {
        didSet {
            saveSettings()
        }
    }

    public var apiKeys: [ProviderKind: String] {
        didSet {
            saveSecrets()
        }
    }

    public var recentRecords: [TranslationRecord] = []

    private let appSupportDirectory: URL
    private let settingsFileURL: URL
    private let secretsFileURL: URL
    private let recentRecordsFileURL: URL

    public init(directory: URL? = nil) {
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

        try? FileManager.default.createDirectory(at: baseDir, withIntermediateDirectories: true)

        self.settings = Self.loadJSON(from: settingsFileURL) ?? AppSettings()
        self.apiKeys = Self.loadSecrets(from: secretsFileURL)
        self.recentRecords = Self.loadJSON(from: recentRecordsFileURL) ?? []

        // Ensure all provider profiles exist
        for kind in ProviderKind.allCases where self.settings.profiles[kind] == nil {
            self.settings.profiles[kind] = .defaultProfile(for: kind)
        }
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
        if settings.activeProvider == .custom {
            // Custom provider might point to local Ollama without a key
            let url = settings.activeProfile.baseURL.lowercased()
            if url.contains("localhost") || url.contains("127.0.0.1") {
                return true
            }
        }
        return !activeAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public func profile(for kind: ProviderKind) -> ProviderProfile {
        settings.profiles[kind] ?? .defaultProfile(for: kind)
    }

    public func updateProfile(_ profile: ProviderProfile, for kind: ProviderKind) {
        settings.profiles[kind] = profile
    }

    public func recordTranslation(_ record: TranslationRecord) {
        var updated = recentRecords.filter {
            !($0.sourceText == record.sourceText && $0.resolvedLanguage == record.resolvedLanguage)
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
