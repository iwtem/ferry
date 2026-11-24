import AppKit
import Foundation
import FerryCore
import Observation

@MainActor
@Observable
public final class TranslatorSession {
    public var sourceText: String = "" {
        didSet {
            let wasEmpty = oldValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let isEmpty = sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            if !wasEmpty && isEmpty && !isRecognizingOCR {
                sourceFormat = .plainText
                showRawMarkdown = false
                clearOutput()
            }
        }
    }
    public var translatedText: String = ""
    public var sourceFormat: SourceContentFormat = .plainText
    public var showRawMarkdown: Bool = false
    public var targetLanguage: TargetLanguage
    public var resolvedLanguage: TargetLanguage = .zhCN
    public var mode: TranslationMode = .translate
    public var isTranslating: Bool = false
    public var isRecognizingOCR: Bool = false
    public var errorMessage: String? = nil
    public var needsScreenRecordingPermission: Bool = false
    public var needsAccessibilityPermission: Bool = false
    public var copiedRecently: Bool = false
    /// True when the currently displayed `translatedText` was served directly from the local LRU cache.
    public var isFromCache: Bool = false
    /// The specific provider + model used for the current primary translation (`nil` before first run).
    public var activeResultModel: ModelChoice? = nil

    // MARK: - Dual-Model Comparison State

    public var isComparing: Bool = false
    public var comparisonModel: ModelChoice? = nil
    public var comparisonText: String = ""
    public var isComparisonTranslating: Bool = false
    public var comparisonErrorMessage: String? = nil
    public var isComparisonFromCache: Bool = false
    public var comparisonCopiedRecently: Bool = false

    /// Effective model displayed for the primary result card.
    public var effectiveResultModel: ModelChoice {
        activeResultModel ?? settingsStore.activeModelChoice
    }

    /// True when the current primary translation was produced by a one-shot model override
    /// different from the user's global default provider/model.
    public var isModelOverridden: Bool {
        guard let activeResultModel else { return false }
        return activeResultModel != settingsStore.activeModelChoice
    }

    /// Language hint passed to SpeechService (`nil` lets TTS auto-detect when a writing mode keeps the source language).
    public var outputLanguageHint: TargetLanguage? {
        mode.preservesSourceLanguage(for: targetLanguage) ? nil : resolvedLanguage
    }

    public var hasStructuredOutput: Bool {
        MarkdownDocument.hasStructure(translatedText)
    }

    public var hasStructuredComparisonOutput: Bool {
        MarkdownDocument.hasStructure(comparisonText)
    }

    public var resolvedAutoCopyFormat: OutputCopyFormat {
        RichClipboardService.resolvedFormat(requested: .auto, sourceFormat: sourceFormat, text: translatedText)
    }

    public var resolvedComparisonCopyFormat: OutputCopyFormat {
        RichClipboardService.resolvedFormat(requested: .auto, sourceFormat: sourceFormat, text: comparisonText)
    }

    public var speakableSourceText: String {
        MarkdownDocument.hasStructure(sourceText) ? MarkdownDocument.toPlainText(sourceText) : sourceText
    }

    public var speakableTranslatedText: String {
        hasStructuredOutput ? MarkdownDocument.toPlainText(translatedText) : translatedText
    }

    public var speakableComparisonText: String {
        hasStructuredComparisonOutput ? MarkdownDocument.toPlainText(comparisonText) : comparisonText
    }

    private let settingsStore: SettingsStore
    private let translatorService: LLMTranslatorService
    private var activeTask: Task<Void, Never>?
    private var comparisonTask: Task<Void, Never>?
    private var copyFeedbackTask: Task<Void, Never>?
    private var comparisonCopyFeedbackTask: Task<Void, Never>?

    public init(settingsStore: SettingsStore, translatorService: LLMTranslatorService) {
        self.settingsStore = settingsStore
        self.translatorService = translatorService
        self.targetLanguage = settingsStore.settings.defaultTargetLanguage
    }

    // MARK: - Primary Translation

    public func translate(content: CapturedContent, bypassCache: Bool = false) {
        sourceFormat = content.format
        showRawMarkdown = false
        if content.format == .richText {
            // Structured Markdown extracted from HTML/RTF already has exact document paragraphs & line breaks.
            sourceText = content.text
        } else {
            sourceText = settingsStore.settings.pdfLineBreakFixEnabled
                ? TextPreprocessor.cleanPDFLineBreaks(content.text)
                : content.text
        }
        translate(text: nil, bypassCache: bypassCache)
    }

    public func translate(text overrideText: String? = nil, bypassCache: Bool = false) {
        if let overrideText {
            let detectedFormat: SourceContentFormat = (settingsStore.settings.preserveFormattingEnabled
                && MarkdownDocument.hasStructure(overrideText)) ? .markdown : .plainText
            translate(content: CapturedContent(text: overrideText, format: detectedFormat), bypassCache: bypassCache)
            return
        }

        // Reconcile sourceFormat when translating manually edited input.
        let hasMarkdownSource = settingsStore.settings.preserveFormattingEnabled
            && MarkdownDocument.hasStructure(sourceText)
        if sourceFormat == .richText {
            if !hasMarkdownSource {
                sourceFormat = .plainText
            }
        } else {
            sourceFormat = hasMarkdownSource ? .markdown : .plainText
        }

        let trimmed = cleanedSourceText()
        guard !trimmed.isEmpty else {
            errorMessage = nil
            translatedText = ""
            isFromCache = false
            activeResultModel = nil
            comparisonText = ""
            comparisonErrorMessage = nil
            isComparisonFromCache = false
            return
        }

        let primaryChoice = settingsStore.activeModelChoice
        runPrimaryTranslation(trimmed: trimmed, choice: primaryChoice, bypassCache: bypassCache)

        if isComparing {
            let secondary = resolvedComparisonModel(excluding: primaryChoice)
            if let secondary {
                comparisonModel = secondary
                runComparisonTranslation(trimmed: trimmed, choice: secondary, bypassCache: bypassCache)
            }
        }
    }

    /// One-shot retranslate of the current source text using a specific model (or refreshing the current result model)
    /// without mutating the user's global default provider/model in `SettingsStore`.
    public func retranslate(with choice: ModelChoice? = nil, bypassCache: Bool = false) {
        let trimmed = cleanedSourceText()
        guard !trimmed.isEmpty else { return }

        let targetChoice = choice ?? effectiveResultModel
        runPrimaryTranslation(trimmed: trimmed, choice: targetChoice, bypassCache: bypassCache)
    }

    // MARK: - Dual-Model Comparison

    public func toggleComparison() {
        if isComparing {
            closeComparison()
        } else {
            startComparison()
        }
    }

    public func startComparison(with choice: ModelChoice? = nil, bypassCache: Bool = false) {
        let primary = effectiveResultModel
        guard let target = choice ?? resolvedComparisonModel(excluding: primary) else {
            return
        }

        isComparing = true
        comparisonModel = target

        let trimmed = cleanedSourceText()
        guard !trimmed.isEmpty else {
            comparisonText = ""
            comparisonErrorMessage = nil
            isComparisonFromCache = false
            isComparisonTranslating = false
            return
        }

        runComparisonTranslation(trimmed: trimmed, choice: target, bypassCache: bypassCache)
    }

    public func retranslateComparison(bypassCache: Bool = true) {
        guard let model = comparisonModel else { return }
        startComparison(with: model, bypassCache: bypassCache)
    }

    public func cancelComparison() {
        comparisonTask?.cancel()
        comparisonTask = nil
        isComparisonTranslating = false
    }

    public func closeComparison() {
        cancelComparison()
        isComparing = false
        comparisonText = ""
        comparisonErrorMessage = nil
        isComparisonFromCache = false
        comparisonCopiedRecently = false
    }

    /// Promotes the comparison model's output into the primary result slot and closes comparison.
    public func adoptComparisonResult() {
        let adopted = comparisonText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !adopted.isEmpty else { return }
        activeTask?.cancel()
        activeTask = nil
        isTranslating = false
        errorMessage = nil
        translatedText = adopted
        activeResultModel = comparisonModel
        isFromCache = isComparisonFromCache
        closeComparison()
    }

    public func copyComparisonTranslation(as format: OutputCopyFormat = .auto) {
        let content = comparisonText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return }
        RichClipboardService.writeTranslation(content, format: format, sourceFormat: sourceFormat)

        comparisonCopiedRecently = true
        comparisonCopyFeedbackTask?.cancel()
        comparisonCopyFeedbackTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            self?.comparisonCopiedRecently = false
        }
    }

    // MARK: - OCR & Permission Helpers

    public func beginOCRRecognition() {
        cancel()
        sourceFormat = .plainText
        showRawMarkdown = false
        sourceText = ""
        translatedText = ""
        errorMessage = nil
        needsScreenRecordingPermission = false
        needsAccessibilityPermission = false
        isFromCache = false
        activeResultModel = nil
        comparisonText = ""
        comparisonErrorMessage = nil
        isComparisonFromCache = false
        isRecognizingOCR = true
    }

    public func finishOCRRecognition(withText text: String) {
        isRecognizingOCR = false
        needsScreenRecordingPermission = false
        needsAccessibilityPermission = false
        translate(text: text)
    }

    public func failOCRRecognition(message: String, needsScreenRecordingPermission: Bool = false) {
        isRecognizingOCR = false
        isTranslating = false
        isFromCache = false
        errorMessage = message
        self.needsScreenRecordingPermission = needsScreenRecordingPermission
        self.needsAccessibilityPermission = false
    }

    public func failWithAccessibilityError(_ message: String) {
        isRecognizingOCR = false
        isTranslating = false
        isFromCache = false
        errorMessage = message
        needsScreenRecordingPermission = false
        needsAccessibilityPermission = true
    }

    public func cancel() {
        activeTask?.cancel()
        activeTask = nil
        comparisonTask?.cancel()
        comparisonTask = nil
        isTranslating = false
        isComparisonTranslating = false
        isRecognizingOCR = false
    }

    public func clear() {
        cancel()
        sourceFormat = .plainText
        showRawMarkdown = false
        sourceText = ""
        clearOutput()
    }

    /// Resets all translation outputs, errors, and in-flight requests without touching `sourceText` or OCR state.
    private func clearOutput() {
        activeTask?.cancel()
        activeTask = nil
        comparisonTask?.cancel()
        comparisonTask = nil
        copyFeedbackTask?.cancel()
        copyFeedbackTask = nil
        comparisonCopyFeedbackTask?.cancel()
        comparisonCopyFeedbackTask = nil
        isTranslating = false
        isComparisonTranslating = false
        translatedText = ""
        errorMessage = nil
        needsScreenRecordingPermission = false
        needsAccessibilityPermission = false
        copiedRecently = false
        isFromCache = false
        activeResultModel = nil
        comparisonText = ""
        comparisonErrorMessage = nil
        isComparisonFromCache = false
        comparisonCopiedRecently = false
    }

    public func copyTranslation(as format: OutputCopyFormat = .auto) {
        let content = translatedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return }
        RichClipboardService.writeTranslation(content, format: format, sourceFormat: sourceFormat)

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
        let preservedFormat = sourceFormat
        sourceText = result
        sourceFormat = preservedFormat
        translatedText = ""
        errorMessage = nil
        translate()
    }

    public func loadFrom(_ other: TranslatorSession) {
        cancel()
        sourceText = other.sourceText
        sourceFormat = other.sourceFormat
        showRawMarkdown = other.showRawMarkdown
        translatedText = other.translatedText
        targetLanguage = other.targetLanguage
        resolvedLanguage = other.resolvedLanguage
        mode = other.mode
        errorMessage = other.errorMessage
        needsScreenRecordingPermission = other.needsScreenRecordingPermission
        needsAccessibilityPermission = other.needsAccessibilityPermission
        isFromCache = other.isFromCache
        activeResultModel = other.activeResultModel
        isComparing = other.isComparing
        comparisonModel = other.comparisonModel
        comparisonText = other.comparisonText
        comparisonErrorMessage = other.comparisonErrorMessage
        isComparisonFromCache = other.isComparisonFromCache

        if other.isTranslating {
            retranslate(with: other.activeResultModel)
        }
        if other.isComparisonTranslating, let compModel = other.comparisonModel {
            startComparison(with: compModel)
        }
    }

    public func loadRecord(_ record: TranslationRecord) {
        cancel()
        sourceText = record.sourceText
        sourceFormat = record.sourceFormat
        showRawMarkdown = false
        translatedText = record.translatedText
        targetLanguage = record.targetLanguage
        resolvedLanguage = record.resolvedLanguage
        mode = record.mode
        errorMessage = nil
        needsScreenRecordingPermission = false
        needsAccessibilityPermission = false
        isFromCache = false
        activeResultModel = ModelChoice(provider: record.provider, model: record.model)
        comparisonText = ""
        comparisonErrorMessage = nil
        isComparisonFromCache = false
    }

    // MARK: - Internal Execution

    private func cleanedSourceText() -> String {
        if sourceFormat == .richText {
            return trimOuterBlankLines(sourceText)
        }
        let rawTrimmed = trimOuterBlankLines(sourceText)
        return settingsStore.settings.pdfLineBreakFixEnabled
            ? TextPreprocessor.cleanPDFLineBreaks(rawTrimmed)
            : rawTrimmed
    }

    private func trimOuterBlankLines(_ text: String) -> String {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        var lines = normalized.components(separatedBy: "\n")
        while let first = lines.first, first.trimmingCharacters(in: .whitespaces).isEmpty {
            lines.removeFirst()
        }
        while let last = lines.last, last.trimmingCharacters(in: .whitespaces).isEmpty {
            lines.removeLast()
        }
        let joined = lines.joined(separator: "\n")
        if !joined.contains("\n") {
            return joined.trimmingCharacters(in: .whitespaces)
        }
        return joined
    }

    private func resolvedComparisonModel(excluding primary: ModelChoice) -> ModelChoice? {
        if let existing = comparisonModel, existing != primary {
            return existing
        }
        return settingsStore.suggestedSecondaryModel(for: primary)
    }

    private func makeRequestConfig(for choice: ModelChoice, mode: TranslationMode) -> TranslationRequestConfig {
        TranslationRequestConfig(
            provider: choice.provider,
            profile: settingsStore.profile(for: choice),
            apiKey: settingsStore.apiKey(for: choice.provider),
            temperature: settingsStore.settings.temperature,
            wordLookup: settingsStore.settings.wordLookupEnabled,
            mode: mode
        )
    }

    private func runPrimaryTranslation(trimmed: String, choice: ModelChoice, bypassCache: Bool) {
        activeTask?.cancel()
        activeTask = nil
        isRecognizingOCR = false
        errorMessage = nil
        needsScreenRecordingPermission = false
        needsAccessibilityPermission = false
        isFromCache = false
        activeResultModel = choice

        let chosenTarget = targetLanguage
        let chosenMode = mode
        let chosenFormat = sourceFormat
        let resolved = chosenTarget.resolvedTarget(for: trimmed)
        resolvedLanguage = resolved

        let config = makeRequestConfig(for: choice, mode: chosenMode)
        let cacheKey = TranslationCacheKey.make(
            text: trimmed,
            targetLanguage: chosenTarget,
            config: config
        )

        if !bypassCache, let cachedOutput = settingsStore.cachedTranslation(for: cacheKey) {
            isTranslating = false
            translatedText = cachedOutput
            isFromCache = true
            let record = TranslationRecord(
                sourceText: trimmed,
                translatedText: cachedOutput,
                targetLanguage: chosenTarget,
                resolvedLanguage: resolved,
                mode: chosenMode,
                sourceFormat: chosenFormat,
                provider: choice.provider,
                model: choice.model
            )
            settingsStore.recordTranslation(record)
            return
        }

        translatedText = ""
        isTranslating = true

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
                    let finalOutput = MarkdownDocument.unwrapOuterMarkdownFenceIfNeeded(
                        buffer.trimmingCharacters(in: .whitespacesAndNewlines),
                        source: trimmed
                    )
                    if !finalOutput.isEmpty {
                        self.translatedText = finalOutput
                        self.settingsStore.cacheTranslation(finalOutput, for: cacheKey)
                        let record = TranslationRecord(
                            sourceText: trimmed,
                            translatedText: finalOutput,
                            targetLanguage: chosenTarget,
                            resolvedLanguage: resolved,
                            mode: chosenMode,
                            sourceFormat: chosenFormat,
                            provider: choice.provider,
                            model: choice.model
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

    private func runComparisonTranslation(trimmed: String, choice: ModelChoice, bypassCache: Bool) {
        comparisonTask?.cancel()
        comparisonTask = nil
        comparisonErrorMessage = nil
        isComparisonFromCache = false
        comparisonModel = choice

        let chosenTarget = targetLanguage
        let chosenMode = mode
        let config = makeRequestConfig(for: choice, mode: chosenMode)
        let cacheKey = TranslationCacheKey.make(
            text: trimmed,
            targetLanguage: chosenTarget,
            config: config
        )

        if !bypassCache, let cachedOutput = settingsStore.cachedTranslation(for: cacheKey) {
            isComparisonTranslating = false
            comparisonText = cachedOutput
            isComparisonFromCache = true
            return
        }

        comparisonText = ""
        isComparisonTranslating = true

        comparisonTask = Task { [weak self] in
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
                    self.comparisonText = buffer
                }

                if !Task.isCancelled {
                    self.isComparisonTranslating = false
                    let finalOutput = MarkdownDocument.unwrapOuterMarkdownFenceIfNeeded(
                        buffer.trimmingCharacters(in: .whitespacesAndNewlines),
                        source: trimmed
                    )
                    if !finalOutput.isEmpty {
                        self.comparisonText = finalOutput
                        self.settingsStore.cacheTranslation(finalOutput, for: cacheKey)
                    }
                }
            } catch {
                if !Task.isCancelled {
                    self.isComparisonTranslating = false
                    self.comparisonErrorMessage = error.localizedDescription
                }
            }
        }
    }
}
