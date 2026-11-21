import Foundation

/// Shared translation entry persisted locally; designed to be shared with a future WidgetKit extension.
public struct TranslationRecord: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public let sourceText: String
    public let translatedText: String
    public let targetLanguage: TargetLanguage
    public let resolvedLanguage: TargetLanguage
    public let mode: TranslationMode
    public let provider: ProviderKind
    public let model: String
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        sourceText: String,
        translatedText: String,
        targetLanguage: TargetLanguage,
        resolvedLanguage: TargetLanguage,
        mode: TranslationMode = .translate,
        provider: ProviderKind,
        model: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.sourceText = sourceText
        self.translatedText = translatedText
        self.targetLanguage = targetLanguage
        self.resolvedLanguage = resolvedLanguage
        self.mode = mode
        self.provider = provider
        self.model = model
        self.createdAt = createdAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, sourceText, translatedText, targetLanguage, resolvedLanguage, mode, provider, model, createdAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        sourceText = try c.decode(String.self, forKey: .sourceText)
        translatedText = try c.decode(String.self, forKey: .translatedText)
        targetLanguage = try c.decode(TargetLanguage.self, forKey: .targetLanguage)
        resolvedLanguage = try c.decode(TargetLanguage.self, forKey: .resolvedLanguage)
        mode = try c.decodeIfPresent(TranslationMode.self, forKey: .mode) ?? .translate
        provider = try c.decode(ProviderKind.self, forKey: .provider)
        model = try c.decode(String.self, forKey: .model)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
    }
}
