import AppKit
import Foundation
import FerryCore
import Observation

@MainActor
@Observable
public final class TranslatorSession {
    public var sourceText: String = ""
    public var translatedText: String = ""
    public var targetLanguage: TargetLanguage
    public var resolvedLanguage: TargetLanguage = .zhCN
    public var isTranslating: Bool = false
    public var errorMessage: String? = nil
    public var copiedRecently: Bool = false

    private let settingsStore: SettingsStore
    private let translatorService: LLMTranslatorService
    private var activeTask: Task<Void, Never>?
    private var copyFeedbackTask: Task<Void, Never>?

    public init(settingsStore: SettingsStore, translatorService: LLMTranslatorService) {
        self.settingsStore = settingsStore
        self.translatorService = translatorService
        self.targetLanguage = settingsStore.settings.defaultTargetLanguage
    }

    public func translate(text overrideText: String? = nil) {
        if let overrideText {
            sourceText = overrideText
        }

        let trimmed = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = nil
            translatedText = ""
            return
        }

        cancel()
        errorMessage = nil
        translatedText = ""
        isTranslating = true

        let chosenTarget = targetLanguage
        let resolved = chosenTarget.resolvedTarget(for: trimmed)
        resolvedLanguage = resolved

        let provider = settingsStore.settings.activeProvider
        let profile = settingsStore.profile(for: provider)
        let apiKey = settingsStore.apiKey(for: provider)
        let config = TranslationRequestConfig(
            provider: provider,
            profile: profile,
            apiKey: apiKey,
            temperature: settingsStore.settings.temperature,
            wordLookup: settingsStore.settings.wordLookupEnabled
        )

        activeTask = Task { [weak self] in
            guard let self else { return }
            var buffer = ""
            do {
                let stream = self.translatorService.streamTranslate(
                    text: trimmed,
                    targetLanguage: chosenTarget,
                    config: config
                )
                for try await chunk in stream {
                    if Task.isCancelled { break }
                    buffer += chunk
                    self.translatedText = buffer
                }

                if !Task.isCancelled {
                    self.isTranslating = false
                    let finalOutput = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !finalOutput.isEmpty {
                        self.translatedText = finalOutput
                        let record = TranslationRecord(
                            sourceText: trimmed,
                            translatedText: finalOutput,
                            targetLanguage: chosenTarget,
                            resolvedLanguage: resolved,
                            provider: provider,
                            model: profile.effectiveModel
                        )
                        self.settingsStore.recordTranslation(record)
                    }
                }
            } catch {
                if !Task.isCancelled {
                    self.isTranslating = false
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    public func cancel() {
        activeTask?.cancel()
        activeTask = nil
        isTranslating = false
    }

    public func clear() {
        cancel()
        sourceText = ""
        translatedText = ""
        errorMessage = nil
    }

    public func copyTranslation() {
        let content = translatedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(content, forType: .string)

        copiedRecently = true
        copyFeedbackTask?.cancel()
        copyFeedbackTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            self?.copiedRecently = false
        }
    }

    public func swapWithTranslation() {
        let result = translatedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.isEmpty else { return }
        sourceText = result
        translatedText = ""
        errorMessage = nil
        translate()
    }

    public func loadFrom(_ other: TranslatorSession) {
        cancel()
        sourceText = other.sourceText
        translatedText = other.translatedText
        targetLanguage = other.targetLanguage
        resolvedLanguage = other.resolvedLanguage
        errorMessage = other.errorMessage
        if other.isTranslating {
            translate()
        }
    }

    public func loadRecord(_ record: TranslationRecord) {
        cancel()
        sourceText = record.sourceText
        translatedText = record.translatedText
        targetLanguage = record.targetLanguage
        resolvedLanguage = record.resolvedLanguage
        errorMessage = nil
    }
}
