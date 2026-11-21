import FerryCore
import Observation
import SwiftUI

@MainActor
@Observable
public final class QuickPopupUIState {
    public var isPinned: Bool = false
    public var showFullSource: Bool = false

    public init() {}
}

/// DeepL-style compact floating translation popup triggered near the mouse cursor on double Cmd+C.
public struct QuickPopupView: View {
    @Bindable public var session: TranslatorSession
    public var settingsStore: SettingsStore
    public var speechService: SpeechService
    public var uiState: QuickPopupUIState

    public var onTogglePin: (Bool) -> Void
    public var onOpenInMainWindow: () -> Void
    public var onOpenSettings: () -> Void
    public var onOpenScreenRecordingSettings: () -> Void
    public var onClose: () -> Void

    public init(
        session: TranslatorSession,
        settingsStore: SettingsStore,
        speechService: SpeechService,
        uiState: QuickPopupUIState,
        onTogglePin: @escaping (Bool) -> Void,
        onOpenInMainWindow: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void,
        onOpenScreenRecordingSettings: @escaping () -> Void = {},
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

                LanguagePickerControl(selection: $session.targetLanguage, compact: true)

                if !session.translatedText.isEmpty || session.isTranslating {
                    Text("→ \(session.resolvedLanguage.shortName(in: lang))")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Button {
                    uiState.isPinned.toggle()
                    onTogglePin(uiState.isPinned)
                } label: {
                    Image(systemName: uiState.isPinned ? "pin.fill" : "pin")
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(HoverIconButtonStyle(isOn: uiState.isPinned, size: 24))
                .help(uiState.isPinned ? l10n.unpinTooltip : l10n.pinPopupTooltip)

                Button(action: onOpenInMainWindow) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                }
                .buttonStyle(HoverIconButtonStyle(size: 24))
                .help(l10n.openInMainWindowTooltip)

                Button(action: onClose) {
                    Image(systemName: "xmark")
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
                            Text(session.sourceText)
                                .font(.system(size: 11.5))
                                .foregroundStyle(.secondary)
                                .lineLimit(uiState.showFullSource ? 8 : 2)
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Image(systemName: uiState.showFullSource ? "chevron.up" : "chevron.down")
                                .font(.system(size: 9))
                                .foregroundStyle(.tertiary)
                                .padding(.top, 2)
                        }
                    }
                    .buttonStyle(.plain)

                    SpeakButton(
                        speechService: speechService,
                        id: "popup-source",
                        text: session.sourceText,
                        help: l10n.speakSource,
                        size: 22
                    )
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            }

            // Translation output
            if let error = session.errorMessage {
                if session.needsScreenRecordingPermission {
                    ErrorBannerView(
                        message: error,
                        actionTitle: l10n.openScreenRecordingSettings,
                        onAction: onOpenScreenRecordingSettings
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
                            Text(session.translatedText)
                                .font(.system(size: 13.5))
                                .lineSpacing(3.5)
                                .foregroundStyle(.primary)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(10)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .modifier(PanelCardSurface())
            }

            SpeechErrorBanner(speechService: speechService)

            // Bottom action bar
            HStack(spacing: 6) {
                Text("\(settingsStore.settings.activeProvider.shortName(in: lang)) · \(settingsStore.settings.activeProfile.effectiveModel)")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)

                Spacer()

                SpeakButton(
                    speechService: speechService,
                    id: "popup-result",
                    text: session.translatedText,
                    languageHint: session.resolvedLanguage,
                    help: l10n.speakTranslation,
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
                    Button {
                        session.translate()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                            .padding(5)
                            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .help(l10n.retranslateTooltip)
                }

                CopyResultButton(
                    copied: session.copiedRecently,
                    disabled: session.translatedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ) {
                    session.copyTranslation()
                }
            }
        }
        .padding(12)
        .frame(width: 370, height: 290)
        .background {
            ZStack {
                VisualEffectBackground(material: .hudWindow, blendingMode: .behindWindow)
                StageBackdrop(hue: .teal, opaque: false)
            }
        }
        .tint(FerryTheme.accent)
        .ferryLocalized(lang)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.primary.opacity(0.16), lineWidth: 1)
        )
        .onChange(of: session.targetLanguage) { _, _ in
            if !session.sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                session.translate()
            }
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
