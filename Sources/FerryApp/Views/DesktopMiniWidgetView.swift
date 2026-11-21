import FerryCore
import SwiftUI

/// Compact translucent floating mini-window that rests on the desktop for direct typing and instant translation.
public struct DesktopMiniWidgetView: View {
    @Bindable public var session: TranslatorSession
    public var settingsStore: SettingsStore
    public var speechService: SpeechService
    public var onToggleAlwaysOnTop: (Bool) -> Void
    public var onOpenInMainWindow: () -> Void
    public var onOpenSettings: () -> Void
    public var onClose: () -> Void

    private let focusTrigger: Int = 1

    public init(
        session: TranslatorSession,
        settingsStore: SettingsStore,
        speechService: SpeechService,
        onToggleAlwaysOnTop: @escaping (Bool) -> Void,
        onOpenInMainWindow: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void,
        onClose: @escaping () -> Void
    ) {
        self.session = session
        self.settingsStore = settingsStore
        self.speechService = speechService
        self.onToggleAlwaysOnTop = onToggleAlwaysOnTop
        self.onOpenInMainWindow = onOpenInMainWindow
        self.onOpenSettings = onOpenSettings
        self.onClose = onClose
    }

    private var lang: ResolvedAppLanguage { settingsStore.resolvedLanguage }
    private var l10n: L10n { L10n(lang) }

    public var body: some View {
        VStack(spacing: 8) {
            // Draggable top bar
            HStack(spacing: 6) {
                LucideIcon(.languages, size: 13.5)
                    .foregroundStyle(FerryTheme.accentText)
                Text(l10n.miniWidgetTitle)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)

                LanguagePickerControl(selection: $session.targetLanguage, compact: true)

                Spacer()

                Button {
                    let next = !settingsStore.settings.desktopWidgetAlwaysOnTop
                    settingsStore.settings.desktopWidgetAlwaysOnTop = next
                    onToggleAlwaysOnTop(next)
                } label: {
                    LucideIcon(.pin, size: 13, filled: settingsStore.settings.desktopWidgetAlwaysOnTop)
                }
                .buttonStyle(HoverIconButtonStyle(isOn: settingsStore.settings.desktopWidgetAlwaysOnTop, size: 24))
                .help(settingsStore.settings.desktopWidgetAlwaysOnTop ? l10n.widgetPinnedTooltip : l10n.widgetUnpinnedTooltip)

                Button(action: onOpenInMainWindow) {
                    LucideIcon(.maximize2, size: 13)
                }
                .buttonStyle(HoverIconButtonStyle(size: 24))
                .help(l10n.expandMainWindowTooltip)

                Button(action: onClose) {
                    LucideIcon(.x, size: 13.5)
                }
                .buttonStyle(HoverIconButtonStyle(size: 24))
                .help(l10n.hideMiniWidgetTooltip)
            }

            // Input box
            SmartTextView(
                text: $session.sourceText,
                placeholder: l10n.widgetInputPlaceholder,
                submitOnEnter: true,
                fontSize: 13,
                focusTrigger: focusTrigger,
                onSubmit: {
                    session.translate()
                }
            )
            .frame(height: 64)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color(nsColor: .textBackgroundColor).opacity(0.75), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.primary.opacity(0.1), lineWidth: 1)
            )

            // Translation output
            let hasOutput = !session.translatedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            if let error = session.errorMessage {
                ErrorBannerView(
                    message: error,
                    showSettingsAction: error.contains("API Key") || error.contains("401"),
                    onOpenSettings: onOpenSettings
                )
            } else {
                VStack(spacing: 0) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            if session.translatedText.isEmpty && session.isTranslating {
                                HStack(spacing: 6) {
                                    ProgressView()
                                        .controlSize(.mini)
                                    Text(l10n.translatingEllipsis)
                                        .font(.system(size: 12))
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 4)
                            } else if session.translatedText.isEmpty {
                                Text(l10n.widgetEmptyOutput)
                                    .font(.system(size: 12))
                                    .foregroundStyle(.tertiary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            } else {
                                Text(session.translatedText)
                                    .font(.system(size: 13))
                                    .lineSpacing(3)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.top, 8)
                        .padding(.bottom, 2)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    HStack(spacing: 2) {
                        Spacer()
                        SpeakButton(
                            speechService: speechService,
                            id: "widget-result",
                            text: session.translatedText,
                            languageHint: session.outputLanguageHint,
                            help: l10n.speakTranslation,
                            size: 24
                        )
                        CopyResultButton(
                            copied: session.copiedRecently,
                            disabled: !hasOutput,
                            size: 24
                        ) {
                            session.copyTranslation()
                        }
                    }
                    .padding(.horizontal, 5)
                    .padding(.bottom, 5)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            SpeechErrorBanner(speechService: speechService)

            // Compact footer
            HStack(spacing: 6) {
                ModePickerControl(selection: $session.mode, compact: true)

                Spacer()

                if !session.sourceText.isEmpty {
                    Button(l10n.clear) {
                        session.clear()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                }
            }
        }
        .padding(11)
        .frame(width: 320, height: 270)
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
        .onChange(of: session.mode) { _, _ in
            if !session.sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                session.translate()
            }
        }
    }
}

#if DEBUG
#Preview("桌面迷你小窗") {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("FerryPreview", isDirectory: true)
    let store = SettingsStore(directory: dir)
    let service = LLMTranslatorService()
    let session = TranslatorSession(settingsStore: store, translatorService: service)
    let speech = SpeechService(settingsStore: store)
    DesktopMiniWidgetView(
        session: session,
        settingsStore: store,
        speechService: speech,
        onToggleAlwaysOnTop: { _ in },
        onOpenInMainWindow: {},
        onOpenSettings: {},
        onClose: {}
    )
}
#endif
