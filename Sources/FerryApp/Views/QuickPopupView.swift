import FerryCore
import Observation
import SwiftUI

@MainActor
@Observable
public final class QuickPopupUIState {
    public var isPinned: Bool = false
    public var showFullSource: Bool = false
    public var sourceAppName: String? = nil

    public init() {}
}

/// DeepL-style compact floating translation & writing popup triggered near the cursor.
public struct QuickPopupView: View {
    @Bindable public var session: TranslatorSession
    public var settingsStore: SettingsStore
    public var speechService: SpeechService
    public var uiState: QuickPopupUIState

    public var onTogglePin: (Bool) -> Void
    public var onOpenInMainWindow: () -> Void
    public var onOpenSettings: () -> Void
    public var onOpenScreenRecordingSettings: () -> Void
    public var onOpenAccessibilitySettings: () -> Void
    public var onReplaceInSourceApp: (() -> Void)?
    public var onHeightChange: (CGFloat) -> Void
    public var onClose: () -> Void

    static let width: CGFloat = 404
    static let standardHeight: CGFloat = 300
    static let compareHeight: CGFloat = 420

    public init(
        session: TranslatorSession,
        settingsStore: SettingsStore,
        speechService: SpeechService,
        uiState: QuickPopupUIState,
        onTogglePin: @escaping (Bool) -> Void,
        onOpenInMainWindow: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void,
        onOpenScreenRecordingSettings: @escaping () -> Void = {},
        onOpenAccessibilitySettings: @escaping () -> Void = {},
        onReplaceInSourceApp: (() -> Void)? = nil,
        onHeightChange: @escaping (CGFloat) -> Void = { _ in },
        onClose: @escaping () -> Void
    ) {
        self.session = session
        self.settingsStore = settingsStore
        self.speechService = speechService
        self.uiState = uiState
        self.onTogglePin = onTogglePin
        self.onOpenInMainWindow = onOpenInMainWindow
        self.onOpenSettings = onOpenSettings
        self.onOpenScreenRecordingSettings = onOpenScreenRecordingSettings
        self.onOpenAccessibilitySettings = onOpenAccessibilitySettings
        self.onReplaceInSourceApp = onReplaceInSourceApp
        self.onHeightChange = onHeightChange
        self.onClose = onClose
    }

    private var lang: ResolvedAppLanguage { settingsStore.resolvedLanguage }
    private var l10n: L10n { L10n(lang) }

    public var body: some View {
        VStack(spacing: 8) {
            // Header: drag anywhere that isn't a control to move the popup.
            HStack(spacing: 4) {
                FerryLogo(height: 13)
                    .padding(.trailing, 2)

                ModePickerControl(selection: $session.mode, compact: true)

                LanguagePickerControl(selection: $session.targetLanguage, compact: true)

                if !session.mode.preservesSourceLanguage(for: session.targetLanguage)
                    && (!session.translatedText.isEmpty || session.isTranslating) {
                    Text("→ \(session.resolvedLanguage.shortName(in: lang))")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                Button {
                    uiState.isPinned.toggle()
                    onTogglePin(uiState.isPinned)
                } label: {
                    LucideIcon(.pin, size: 13.5, filled: uiState.isPinned)
                }
                .buttonStyle(HoverIconButtonStyle(isOn: uiState.isPinned, size: 24))
                .help(uiState.isPinned ? l10n.unpinTooltip : l10n.pinPopupTooltip)

                Button(action: onOpenInMainWindow) {
                    LucideIcon(.maximize2, size: 13.5)
                }
                .buttonStyle(HoverIconButtonStyle(size: 24))
                .help(l10n.openInMainWindowTooltip)

                Button(action: onClose) {
                    LucideIcon(.x, size: 14)
                }
                .buttonStyle(HoverIconButtonStyle(size: 24))
                .help(l10n.closeEscTooltip)
            }
            .padding(.vertical, 2)
            .background(WindowDragArea())
            .help(l10n.dragToMoveTooltip)

            // Collapsible source text preview + source speak button
            if !session.sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                HStack(alignment: .top, spacing: 6) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            uiState.showFullSource.toggle()
                        }
                    } label: {
                        HStack(alignment: .top, spacing: 6) {
                            let previewText = uiState.showFullSource
                                ? session.speakableSourceText
                                : session.speakableSourceText
                                    .replacingOccurrences(of: #"\s*\n+\s*"#, with: " · ", options: .regularExpression)
                            Text(previewText)
                                .font(.system(size: 11.5))
                                .foregroundStyle(.secondary)
                                .lineLimit(uiState.showFullSource ? 8 : 2)
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            LucideIcon(uiState.showFullSource ? .chevronUp : .chevronDown, size: 11, strokeWidth: 2.1)
                                .foregroundStyle(.tertiary)
                                .padding(.top, 2)
                        }
                    }
                    .buttonStyle(.plain)

                    SpeakButton(
                        speechService: speechService,
                        id: "popup-source",
                        text: session.speakableSourceText,
                        help: l10n.speakSource,
                        size: 22
                    )
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            }

            let hasOutput = !session.translatedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

            // Translation output
            if let error = session.errorMessage {
                if session.needsScreenRecordingPermission {
                    ErrorBannerView(
                        message: error,
                        actionTitle: l10n.openScreenRecordingSettings,
                        onAction: onOpenScreenRecordingSettings
                    )
                } else if session.needsAccessibilityPermission {
                    ErrorBannerView(
                        message: error,
                        actionTitle: l10n.openAccessibilitySettings,
                        onAction: onOpenAccessibilitySettings
                    )
                } else {
                    ErrorBannerView(
                        message: error,
                        showSettingsAction: error.contains("API Key") || error.contains("401"),
                        onOpenSettings: onOpenSettings
                    )
                }
                Spacer(minLength: 0)
            } else {
                VStack(spacing: 0) {
                    if session.isComparing {
                        HStack(spacing: 5) {
                            Circle()
                                .fill(FerryTheme.accent)
                                .frame(width: 5.5, height: 5.5)
                            Text(session.effectiveResultModel.model)
                                .font(.system(size: 10.5, weight: .medium))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                        }
                        .padding(.horizontal, 10)
                        .padding(.top, 6)
                        .padding(.bottom, 5)
                        Rectangle().fill(Stage.hairline).frame(height: 1)
                    }

                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            if session.isRecognizingOCR {
                                HStack(spacing: 6) {
                                    ProgressView()
                                        .controlSize(.small)
                                    Text(l10n.recognizingOCREllipsis)
                                        .font(.system(size: 13))
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 10)
                            } else if session.translatedText.isEmpty && session.isTranslating {
                                HStack(spacing: 6) {
                                    ProgressView()
                                        .controlSize(.small)
                                    Text(l10n.translatingLongEllipsis)
                                        .font(.system(size: 13))
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 10)
                            } else {
                                StructuredResultView(
                                    text: session.translatedText,
                                    fontSize: 13.5,
                                    lineSpacing: 3.5,
                                    showRawMarkdown: session.showRawMarkdown
                                )
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.top, 10)
                        .padding(.bottom, 4)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    HStack(spacing: 2) {
                        if session.isFromCache && hasOutput && !session.isTranslating {
                            CachedResultBadge(compact: true)
                                .padding(.leading, 4)
                        }
                        if session.sourceFormat == .richText && hasOutput && !session.isTranslating {
                            StructuredFormatBadge(compact: true)
                                .padding(.leading, session.isFromCache ? 2 : 4)
                        }
                        Spacer()
                        if hasOutput && session.hasStructuredOutput {
                            MarkdownModeToggleButton(showRawMarkdown: $session.showRawMarkdown, size: 24)
                        }
                        SpeakButton(
                            speechService: speechService,
                            id: "popup-result",
                            text: session.speakableTranslatedText,
                            languageHint: session.outputLanguageHint,
                            help: l10n.speakTranslation,
                            size: 24
                        )
                        CopyResultButton(
                            copied: session.copiedRecently,
                            disabled: !hasOutput,
                            size: 24,
                            autoFormat: session.resolvedAutoCopyFormat,
                            isStructured: session.hasStructuredOutput,
                            onCopyFormat: { format in
                                session.copyTranslation(as: format)
                            }
                        ) {
                            session.copyTranslation()
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.bottom, 6)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .modifier(PanelCardSurface())

                if session.isComparing {
                    let hasComparisonOutput = !session.comparisonText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    VStack(spacing: 0) {
                        HStack(spacing: 5) {
                            ComparisonModelPicker(
                                session: session,
                                settingsStore: settingsStore,
                                compact: true,
                                onOpenSettings: onOpenSettings
                            )
                            Spacer(minLength: 4)
                            if hasComparisonOutput && !session.isComparisonTranslating {
                                Button(l10n.adoptComparisonButton) {
                                    session.adoptComparisonResult()
                                }
                                .buttonStyle(GlassButtonStyle(kind: .glass, height: 20))
                                .help(l10n.adoptComparisonTooltip)
                            }
                            Button {
                                session.closeComparison()
                            } label: {
                                LucideIcon(.x, size: 12)
                            }
                            .buttonStyle(HoverIconButtonStyle(size: 20))
                            .help(l10n.closeCompareTooltip)
                        }
                        .padding(.horizontal, 8)
                        .padding(.top, 6)
                        .padding(.bottom, 5)

                        Rectangle().fill(Stage.hairline).frame(height: 1)

                        ScrollView {
                            VStack(alignment: .leading, spacing: 4) {
                                if let error = session.comparisonErrorMessage {
                                    ErrorBannerView(
                                        message: error,
                                        showSettingsAction: error.contains("API Key") || error.contains("401"),
                                        onOpenSettings: onOpenSettings
                                    )
                                } else if !hasComparisonOutput && session.isComparisonTranslating {
                                    HStack(spacing: 6) {
                                        ProgressView().controlSize(.small)
                                        Text(l10n.translatingLongEllipsis)
                                            .font(.system(size: 12.5))
                                            .foregroundStyle(.secondary)
                                    }
                                    .padding(.vertical, 6)
                                } else {
                                    StructuredResultView(
                                        text: session.comparisonText,
                                        fontSize: 13,
                                        lineSpacing: 3,
                                        showRawMarkdown: session.showRawMarkdown
                                    )
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.top, 8)
                            .padding(.bottom, 4)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                        HStack(spacing: 2) {
                            if session.isComparisonFromCache && hasComparisonOutput && !session.isComparisonTranslating {
                                CachedResultBadge(compact: true)
                                    .padding(.leading, 4)
                            }
                            Spacer()
                            if session.isComparisonTranslating {
                                Button(l10n.stop) {
                                    session.cancelComparison()
                                }
                                .buttonStyle(.plain)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.red)
                                .padding(.trailing, 4)
                            } else {
                                RetranslateButton(size: 22, bypassCache: session.isComparisonFromCache) {
                                    session.retranslateComparison(bypassCache: true)
                                }
                            }
                            SpeakButton(
                                speechService: speechService,
                                id: "popup-compare-result",
                                text: session.speakableComparisonText,
                                languageHint: session.outputLanguageHint,
                                help: l10n.speakTranslation,
                                size: 22
                            )
                            CopyResultButton(
                                copied: session.comparisonCopiedRecently,
                                disabled: !hasComparisonOutput,
                                size: 22,
                                autoFormat: session.resolvedComparisonCopyFormat,
                                isStructured: session.hasStructuredComparisonOutput,
                                onCopyFormat: { format in
                                    session.copyComparisonTranslation(as: format)
                                }
                            ) {
                                session.copyComparisonTranslation()
                            }
                        }
                        .padding(.horizontal, 6)
                        .padding(.bottom, 5)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(StageHue.azure.bottom.opacity(0.065), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                    )
                }
            }

            SpeechErrorBanner(speechService: speechService)

            // Bottom action bar
            HStack(spacing: 5) {
                QuickModelSwitchMenu(
                    session: session,
                    settingsStore: settingsStore,
                    showCompareOption: !session.isComparing,
                    chipStyle: true,
                    onOpenSettings: onOpenSettings
                )
                .frame(maxWidth: 190, alignment: .leading)

                Spacer(minLength: 4)

                CompareToggleButton(
                    session: session,
                    settingsStore: settingsStore,
                    size: 24
                )

                if session.isTranslating {
                    Button {
                        session.cancel()
                    } label: {
                        Text(l10n.stop)
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                } else {
                    RetranslateButton(size: 24, bypassCache: session.isFromCache) {
                        session.retranslate(bypassCache: true)
                    }
                }

                if let onReplace = onReplaceInSourceApp, uiState.sourceAppName != nil {
                    Button {
                        onReplace()
                    } label: {
                        HStack(spacing: 4) {
                            LucideIcon(.cornerDownLeft, size: 11.5, strokeWidth: 2.2)
                            Text(l10n.replaceSelectionButton)
                        }
                    }
                    .buttonStyle(GlassButtonStyle(kind: .glow, hue: .teal, height: 24))
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(!hasOutput || session.isTranslating)
                    .help(
                        uiState.sourceAppName.map { l10n.replaceInAppTooltip($0) }
                            ?? l10n.replaceSelectionTooltip
                    )
                }
            }
        }
        .padding(12)
        .frame(width: Self.width, height: session.isComparing ? Self.compareHeight : Self.standardHeight)
        .background {
            ZStack {
                VisualEffectBackground(material: .hudWindow, blendingMode: .behindWindow)
                StageBackdrop(hue: .teal, opaque: false)
            }
        }
        .tint(FerryTheme.accent)
        .ferryLocalized(lang)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onChange(of: session.targetLanguage) { _, _ in
            if !session.sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                session.translate()
            }
        }
        .onChange(of: session.mode) { _, _ in
            if !session.sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                session.translate()
            }
        }
        .onChange(of: session.isComparing) { _, comparing in
            onHeightChange(comparing ? Self.compareHeight : Self.standardHeight)
        }
    }
}

#if DEBUG
#Preview("划词悬浮窗") {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("FerryPreview", isDirectory: true)
    let store = SettingsStore(directory: dir)
    let service = LLMTranslatorService()
    let session = TranslatorSession(settingsStore: store, translatorService: service)
    session.sourceText = "Serendipity"
    session.translatedText = "意外发现珍奇事物的运气；机缘巧合"
    let uiState = QuickPopupUIState()
    let speech = SpeechService(settingsStore: store)
    return QuickPopupView(
        session: session,
        settingsStore: store,
        speechService: speech,
        uiState: uiState,
        onTogglePin: { _ in },
        onOpenInMainWindow: {},
        onOpenSettings: {},
        onClose: {}
    )
}
#endif
