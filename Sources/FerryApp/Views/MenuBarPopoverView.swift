import FerryCore
import SwiftUI

/// Dropdown panel under the menu bar icon: type, press Enter, read the result.
public struct MenuBarPopoverView: View {
    @Bindable public var session: TranslatorSession
    public var settingsStore: SettingsStore
    public var speechService: SpeechService
    public var onOpenMainWindow: () -> Void
    public var onToggleDesktopWidget: () -> Void
    public var onOpenSettings: () -> Void
    public var onQuit: () -> Void
    /// Reports the panel's natural height so the host window can follow the content.
    public var onHeightChange: (CGFloat) -> Void = { _ in }

    static let width: CGFloat = 340
    /// The translation area fits its text between these heights, then scrolls.
    private static let outputMinHeight: CGFloat = 64
    private static let outputMaxHeight: CGFloat = 320
    @ViewState private var outputContentHeight: CGFloat = 0

    private var hasSource: Bool {
        !session.sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var hasResult: Bool {
        !session.translatedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var lang: ResolvedAppLanguage { settingsStore.resolvedLanguage }
    private var l10n: L10n { L10n(lang) }

    public var body: some View {
        VStack(spacing: 10) {
            headerBar
            inputCard
            controlRow
            outputCard
        }
        .padding(12)
        .frame(width: Self.width)
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
            onHeightChange(height)
        }
        .background {
            ZStack {
                VisualEffectBackground(material: .popover, blendingMode: .behindWindow)
                StageBackdrop(hue: .teal, opaque: false)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Stage.controlStroke, lineWidth: 1)
        )
        .tint(FerryTheme.accent)
        .ferryLocalized(lang)
        .onChange(of: session.targetLanguage) { _, _ in
            if hasSource {
                session.translate()
            }
        }
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack(spacing: 2) {
            FerryLogo(height: 16, color: FerryTheme.accentText)
                .padding(.trailing, 6)

            ModelMenu(settingsStore: settingsStore, onOpenSettings: onOpenSettings, compact: true)
                .frame(maxWidth: 150, alignment: .leading)

            Spacer(minLength: 6)

            headerButton("pip", help: l10n.miniWidgetTooltip, action: onToggleDesktopWidget)
            headerButton("arrow.up.left.and.arrow.down.right", help: l10n.openInMainWindowTooltip, action: onOpenMainWindow)
            headerButton("gearshape", help: l10n.settings, action: onOpenSettings)
            headerButton("power", help: l10n.quitFerry, action: onQuit)
        }
    }

    private func headerButton(_ systemName: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
        }
        .buttonStyle(GhostIconStyle(size: 26))
        .help(help)
        .accessibilityLabel(help)
    }

    // MARK: - Input

    private var inputCard: some View {
        VStack(spacing: 0) {
            SmartTextView(
                text: $session.sourceText,
                placeholder: l10n.popoverInputPlaceholder,
                submitOnEnter: true,
                fontSize: 13.5,
                onSubmit: {
                    session.translate()
                }
            )
            .frame(height: 56)
            .padding(.horizontal, 6)
            .padding(.top, 4)

            HStack(spacing: 4) {
                if !session.sourceText.isEmpty {
                    Button {
                        session.clear()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(GhostIconStyle(size: 24))
                    .help(l10n.clear)
                } else {
                    Text(l10n.shiftReturnHint)
                        .font(.system(size: 10.5))
                        .foregroundStyle(Stage.textTertiary)
                        .padding(.leading, 4)
                }

                Spacer()

                if hasSource {
                    SpeakButton(
                        speechService: speechService,
                        id: "popover-source",
                        text: session.sourceText,
                        help: l10n.speakSource,
                        size: 24
                    )
                }

                if session.isTranslating {
                    Button(role: .cancel) {
                        session.cancel()
                    } label: {
                        Label(l10n.stop, systemImage: "stop.fill")
                    }
                    .buttonStyle(GlassButtonStyle(height: 24))
                } else {
                    Button(l10n.translate) {
                        session.translate()
                    }
                    .buttonStyle(GlassButtonStyle(kind: .glow, hue: .teal, height: 24))
                    .disabled(!hasSource)
                }
            }
            .padding(.horizontal, 6)
            .padding(.bottom, 6)
        }
        .glassSurface(cornerRadius: 12)
    }

    // MARK: - Controls

    private var controlRow: some View {
        HStack(spacing: 6) {
            LanguagePickerControl(selection: $session.targetLanguage, compact: true)

            if hasResult || session.isTranslating {
                Text("→ \(session.resolvedLanguage.shortName(in: lang))")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Stage.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            if hasResult && !session.isTranslating {
                Button {
                    session.swapWithTranslation()
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                }
                .buttonStyle(GhostIconStyle(size: 24))
                .help(l10n.swapPopoverTooltip)
            }

            SpeakButton(
                speechService: speechService,
                id: "popover-result",
                text: session.translatedText,
                languageHint: session.resolvedLanguage,
                help: l10n.speakTranslation,
                size: 24
            )

            CopyResultButton(copied: session.copiedRecently, disabled: !hasResult) {
                session.copyTranslation()
            }
        }
    }

    // MARK: - Output

    private var outputCard: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                if let error = session.errorMessage {
                    ErrorBannerView(
                        message: error,
                        showSettingsAction: error.contains("API Key") || error.contains("401"),
                        onOpenSettings: onOpenSettings
                    )
                } else if !hasResult && session.isTranslating {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text(l10n.translatingEllipsis)
                            .font(.system(size: 12.5))
                            .foregroundStyle(Stage.textSecondary)
                    }
                    .padding(.vertical, 4)
                } else if hasResult {
                    Text(session.translatedText)
                        .font(.system(size: 14))
                        .lineSpacing(4)
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else if !settingsStore.hasActiveAPIKey {
                    VStack(spacing: 10) {
                        HueOrb(systemName: "key.fill", hue: .amber, size: 40)
                        Text(l10n.missingAPIKeyTitle)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                        Button(l10n.openSettings, action: onOpenSettings)
                            .buttonStyle(GlassButtonStyle(kind: .glow, hue: .teal, height: 26))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                } else {
                    Text(l10n.translationPlaceholder)
                        .font(.system(size: 14))
                        .foregroundStyle(Stage.textTertiary)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                outputContentHeight = height
            }
        }
        .scrollDisabled(outputContentHeight <= Self.outputMaxHeight)
        .frame(maxWidth: .infinity)
        .frame(height: min(max(outputContentHeight, Self.outputMinHeight), Self.outputMaxHeight))
        .glassSurface(cornerRadius: 12, fill: FerryTheme.accent.opacity(0.07))
        .overlay(alignment: .bottom) {
            SpeechErrorBanner(speechService: speechService)
                .padding(8)
        }
    }
}

#if DEBUG
#Preview("菜单栏快译") {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("FerryPreview", isDirectory: true)
    let store = SettingsStore(directory: dir)
    let service = LLMTranslatorService()
    let session = TranslatorSession(settingsStore: store, translatorService: service)
    let speech = SpeechService(settingsStore: store)
    MenuBarPopoverView(
        session: session,
        settingsStore: store,
        speechService: speech,
        onOpenMainWindow: {},
        onToggleDesktopWidget: {},
        onOpenSettings: {},
        onQuit: {}
    )
}
#endif
