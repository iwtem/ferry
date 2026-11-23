import FerryCore
import SwiftUI

/// Dropdown panel under the menu bar icon: type, press Enter, read the result.
public struct MenuBarPopoverView: View {
    @Bindable public var session: TranslatorSession
    public var settingsStore: SettingsStore
    public var speechService: SpeechService
    public var updateService: AppUpdateService? = nil
    public var onScreenshotOCR: () -> Void = {}
    public var onOpenMainWindow: () -> Void
    public var onToggleDesktopWidget: () -> Void
    public var onOpenSettings: () -> Void
    public var onQuit: () -> Void
    /// Reports the panel's natural height so the host window can follow the content.
    public var onHeightChange: (CGFloat) -> Void = { _ in }

    static let width: CGFloat = 368
    /// The translation text area fits its content between these heights, then scrolls.
    private static let outputTextMinHeight: CGFloat = 42
    private static let outputTextMaxHeight: CGFloat = 290
    private static let compareTextMaxHeight: CGFloat = 145
    @ViewState private var outputContentHeight: CGFloat = 0
    @ViewState private var comparisonContentHeight: CGFloat = 0

    private var hasSource: Bool {
        !session.sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var hasResult: Bool {
        !session.translatedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var hasComparisonResult: Bool {
        !session.comparisonText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var showOutputActions: Bool {
        session.errorMessage == nil && (hasResult || settingsStore.hasActiveAPIKey)
    }

    private var lang: ResolvedAppLanguage { settingsStore.resolvedLanguage }
    private var l10n: L10n { L10n(lang) }

    public var body: some View {
        VStack(spacing: 10) {
            headerBar
            if let updateService {
                UpdateBannerView(updateService: updateService, compact: true)
            }
            inputCard
            controlRow
            outputCard
            if session.isComparing {
                comparisonCard
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
            if speechService.lastErrorMessage != nil {
                SpeechErrorBanner(speechService: speechService)
            }
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
        .onChange(of: session.mode) { _, _ in
            if hasSource {
                session.translate()
            }
        }
        .onChange(of: hasSource) { wasNonEmpty, isNowNonEmpty in
            if wasNonEmpty && !isNowNonEmpty {
                speechService.stop()
            }
        }
    }

    // MARK: - Header

    private var headerBar: some View {
        let ocrHelp = settingsStore.settings.screenshotOCREnabled
            ? l10n.screenshotOCRShortcutTooltip(settingsStore.settings.screenshotOCRShortcut.displayString)
            : l10n.screenshotOCRTooltip

        return HStack(spacing: 2) {
            FerryLogo(height: 16, color: FerryTheme.accentText)
                .padding(.trailing, 6)

            ModelMenu(settingsStore: settingsStore, onOpenSettings: onOpenSettings, compact: true)
                .frame(maxWidth: 126, alignment: .leading)

            Spacer(minLength: 4)

            headerButton(.scanText, help: ocrHelp, action: onScreenshotOCR)
            headerButton(.pictureInPicture2, help: l10n.miniWidgetTooltip, action: onToggleDesktopWidget)
            headerButton(.maximize2, help: l10n.openInMainWindowTooltip, action: onOpenMainWindow)
            headerButton(.settings, help: l10n.settings, action: onOpenSettings)
            headerButton(.logOut, help: l10n.quitFerry, action: onQuit)
        }
    }

    private func headerButton(_ icon: LucideIcon.Name, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            LucideIcon(icon, size: 14.5)
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
                        LucideIcon(.circleX, size: 14)
                    }
                    .buttonStyle(GhostIconStyle(size: 24))
                    .help(l10n.clear)
                    .accessibilityLabel(l10n.clear)
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
                        HStack(spacing: 5) {
                            LucideIcon(.square, size: 10, filled: true)
                            Text(l10n.stop)
                        }
                    }
                    .buttonStyle(GlassButtonStyle(height: 24))
                } else {
                    Button(l10n.runActionLabel(for: session.mode)) {
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
            ModePickerControl(selection: $session.mode, compact: true)
            LanguagePickerControl(selection: $session.targetLanguage, compact: true)

            Spacer(minLength: 4)

            if hasResult && !session.isTranslating {
                Button {
                    session.swapWithTranslation()
                } label: {
                    LucideIcon(.arrowUpDown, size: 14)
                }
                .buttonStyle(GhostIconStyle(size: 24))
                .help(l10n.swapPopoverTooltip)
                .accessibilityLabel(l10n.swapPopoverTooltip)
            }
        }
    }

    // MARK: - Output

    private var outputCard: some View {
        let maxHeight = session.isComparing ? Self.compareTextMaxHeight : Self.outputTextMaxHeight
        return VStack(spacing: 0) {
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
                .padding(.horizontal, 11)
                .padding(.top, 7)
                .padding(.bottom, 5)
                Rectangle().fill(Stage.hairline).frame(height: 1)
            }

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
                .padding(.horizontal, 12)
                .padding(.top, session.isComparing ? 8 : 10)
                .padding(.bottom, showOutputActions ? 4 : 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                    outputContentHeight = height
                }
            }
            .scrollDisabled(outputContentHeight <= maxHeight)
            .frame(maxWidth: .infinity)
            .frame(height: min(max(outputContentHeight, Self.outputTextMinHeight), maxHeight))

            if showOutputActions {
                HStack(spacing: 2) {
                    if session.isFromCache && hasResult && !session.isTranslating {
                        CachedResultBadge(compact: true)
                            .padding(.leading, 4)
                    }
                    if session.isModelOverridden && !session.isComparing && hasResult && !session.isTranslating {
                        ModelOverrideBadge(model: session.effectiveResultModel.model, compact: true)
                            .padding(.leading, session.isFromCache ? 2 : 4)
                    }
                    Spacer()
                    if hasResult && !session.isTranslating {
                        QuickModelSwitchMenu(
                            session: session,
                            settingsStore: settingsStore,
                            showCompareOption: !session.isComparing,
                            size: 24,
                            onOpenSettings: onOpenSettings
                        )
                        CompareToggleButton(
                            session: session,
                            settingsStore: settingsStore,
                            size: 24
                        )
                    }
                    if (session.isFromCache || session.isModelOverridden) && hasResult && !session.isTranslating {
                        RetranslateButton(size: 24, bypassCache: session.isFromCache) {
                            session.retranslate(bypassCache: true)
                        }
                    }
                    SpeakButton(
                        speechService: speechService,
                        id: "popover-result",
                        text: session.translatedText,
                        languageHint: session.outputLanguageHint,
                        help: l10n.speakTranslation,
                        size: 24
                    )
                    CopyResultButton(
                        copied: session.copiedRecently,
                        disabled: !hasResult,
                        size: 24
                    ) {
                        session.copyTranslation()
                    }
                }
                .padding(.horizontal, 6)
                .padding(.bottom, 6)
            }
        }
        .glassSurface(cornerRadius: 12, fill: FerryTheme.accent.opacity(0.07))
    }

    private var comparisonCard: some View {
        VStack(spacing: 0) {
            HStack(spacing: 5) {
                ComparisonModelPicker(
                    session: session,
                    settingsStore: settingsStore,
                    compact: true,
                    onOpenSettings: onOpenSettings
                )
                Spacer(minLength: 4)
                if hasComparisonResult && !session.isComparisonTranslating {
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
                .accessibilityLabel(l10n.closeCompareTooltip)
            }
            .padding(.horizontal, 8)
            .padding(.top, 6)
            .padding(.bottom, 5)

            Rectangle().fill(Stage.hairline).frame(height: 1)

            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    if let error = session.comparisonErrorMessage {
                        ErrorBannerView(
                            message: error,
                            showSettingsAction: error.contains("API Key") || error.contains("401"),
                            onOpenSettings: onOpenSettings
                        )
                    } else if !hasComparisonResult && session.isComparisonTranslating {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text(l10n.translatingEllipsis)
                                .font(.system(size: 12.5))
                                .foregroundStyle(Stage.textSecondary)
                        }
                        .padding(.vertical, 4)
                    } else if hasComparisonResult {
                        Text(session.comparisonText)
                            .font(.system(size: 13.5))
                            .lineSpacing(3.5)
                            .foregroundStyle(.primary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Text(l10n.translationPlaceholder)
                            .font(.system(size: 13.5))
                            .foregroundStyle(Stage.textTertiary)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                    comparisonContentHeight = height
                }
            }
            .scrollDisabled(comparisonContentHeight <= Self.compareTextMaxHeight)
            .frame(maxWidth: .infinity)
            .frame(height: min(max(comparisonContentHeight, Self.outputTextMinHeight), Self.compareTextMaxHeight))

            HStack(spacing: 2) {
                if session.isComparisonFromCache && hasComparisonResult && !session.isComparisonTranslating {
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
                    RetranslateButton(
                        size: 24,
                        bypassCache: session.isComparisonFromCache,
                        disabled: !hasSource
                    ) {
                        session.retranslateComparison(bypassCache: true)
                    }
                }
                SpeakButton(
                    speechService: speechService,
                    id: "popover-compare-result",
                    text: session.comparisonText,
                    languageHint: session.outputLanguageHint,
                    help: l10n.speakTranslation,
                    size: 24
                )
                CopyResultButton(
                    copied: session.comparisonCopiedRecently,
                    disabled: !hasComparisonResult,
                    size: 24
                ) {
                    session.copyComparisonTranslation()
                }
            }
            .padding(.horizontal, 6)
            .padding(.bottom, 6)
        }
        .glassSurface(cornerRadius: 12, fill: StageHue.azure.bottom.opacity(0.065))
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
