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

    public var body: some View {
        VStack(spacing: 8) {
            // Draggable top bar
            HStack(spacing: 6) {
                Image(systemName: "translate")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(FerryTheme.accent)
                Text("渡 Ferry 小窗")
                    .font(.system(size: 12, weight: .semibold))

                LanguagePickerControl(selection: $session.targetLanguage, compact: true)

                Spacer()

                Button {
                    let next = !settingsStore.settings.desktopWidgetAlwaysOnTop
                    settingsStore.settings.desktopWidgetAlwaysOnTop = next
                    onToggleAlwaysOnTop(next)
                } label: {
                    Image(systemName: settingsStore.settings.desktopWidgetAlwaysOnTop ? "pin.fill" : "pin")
                        .font(.system(size: 11))
                        .foregroundStyle(settingsStore.settings.desktopWidgetAlwaysOnTop ? FerryTheme.accent : Color.secondary)
                        .padding(4)
                }
                .buttonStyle(.plain)
                .help(settingsStore.settings.desktopWidgetAlwaysOnTop ? "当前置顶，点击改为贴近桌面" : "点击置顶浮窗")

                Button(action: onOpenInMainWindow) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .padding(4)
                }
                .buttonStyle(.plain)
                .help("展开大窗口")

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(4)
                }
                .buttonStyle(.plain)
                .help("隐藏桌面小窗")
            }

            // Input box
            SmartTextView(
                text: $session.sourceText,
                placeholder: "输入内容按 Enter 快速翻译…",
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
            if let error = session.errorMessage {
                ErrorBannerView(
                    message: error,
                    showSettingsAction: error.contains("API Key") || error.contains("401"),
                    onOpenSettings: onOpenSettings
                )
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        if session.translatedText.isEmpty && session.isTranslating {
                            HStack(spacing: 6) {
                                ProgressView()
                                    .controlSize(.mini)
                                Text("翻译中…")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                        } else if session.translatedText.isEmpty {
                            Text("译文将实时显示在这里")
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
                    .padding(8)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            SpeechErrorBanner(speechService: speechService)

            // Compact footer
            HStack(spacing: 6) {
                Text(settingsStore.settings.activeProvider.shortName)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)

                Spacer()

                if !session.sourceText.isEmpty {
                    Button("清空") {
                        session.clear()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                }

                SpeakButton(
                    speechService: speechService,
                    id: "widget-result",
                    text: session.translatedText,
                    languageHint: session.resolvedLanguage,
                    help: "朗读译文",
                    size: 24
                )

                CopyResultButton(
                    copied: session.copiedRecently,
                    disabled: session.translatedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ) {
                    session.copyTranslation()
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
