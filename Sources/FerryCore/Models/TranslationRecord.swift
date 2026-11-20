import Foundation

/// Shared translation entry persisted locally; designed to be shared with a future WidgetKit extension.
public struct TranslationRecord: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public let sourceText: String
    public let translatedText: String
    public let targetLanguage: TargetLanguage
    public let resolvedLanguage: TargetLanguage
    public let provider: ProviderKind
    public let model: String
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        sourceText: String,
        translatedText: String,
        targetLanguage: TargetLanguage,
        resolvedLanguage: TargetLanguage,
        provider: ProviderKind,
        model: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.sourceText = sourceText
        self.translatedText = translatedText
        self.targetLanguage = targetLanguage
        self.resolvedLanguage = resolvedLanguage
        self.provider = provider
        self.model = model
        self.createdAt = createdAt
    }
}
