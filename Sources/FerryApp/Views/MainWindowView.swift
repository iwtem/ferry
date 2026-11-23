import AppKit
import FerryCore
import Observation
import SwiftUI

@MainActor
@Observable
public final class MainWindowUIState {
    public var showHistory: Bool = false
    public var focusTrigger: Int = 1
    /// Accumulated rotation of the swap button's arrows (animates on every swap).
    public var swapRotation: Double = 0

    public init() {}
}

public struct MainWindowView: View {
    @Bindable public var session: TranslatorSession
    public var settingsStore: SettingsStore
    public var copyMonitor: GlobalCopyMonitor
    public var speechService: SpeechService
    public var updateService: AppUpdateService?
    public var uiState: MainWindowUIState
    public var onScreenshotOCR: () -> Void
    public var onPasteImageOCR: (CGImage) -> Void
    public var onToggleDesktopWidget: () -> Void
    public var onOpenSettings: () -> Void
    public var onOpenScreenRecordingSettings: () -> Void

    public init(
        session: TranslatorSession,
        settingsStore: SettingsStore,
        copyMonitor: GlobalCopyMonitor,
        speechService: SpeechService,
        updateService: AppUpdateService? = nil,
        uiState: MainWindowUIState,
        onScreenshotOCR: @escaping () -> Void = {},
        onPasteImageOCR: @escaping (CGImage) -> Void = { _ in },
        onToggleDesktopWidget: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void,
        onOpenScreenRecordingSettings: @escaping () -> Void = {}
    ) {
        self.session = session
        self.settingsStore = settingsStore
        self.copyMonitor = copyMonitor
        self.speechService = speechService
        self.updateService = updateService
        self.uiState = uiState
        self.onScreenshotOCR = onScreenshotOCR
        self.onPasteImageOCR = onPasteImageOCR
        self.onToggleDesktopWidget = onToggleDesktopWidget
        self.onOpenSettings = onOpenSettings
        self.onOpenScreenRecordingSettings = onOpenScreenRecordingSettings
    }

    private var hasSource: Bool {
        !session.sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var hasResult: Bool {
        !session.translatedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var hasComparisonResult: Bool {
        !session.comparisonText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var lang: ResolvedAppLanguage { settingsStore.resolvedLanguage }
    private var l10n: L10n { L10n(lang) }

    public var body: some View {
        VStack(spacing: 0) {
            header

            Rectangle().fill(Stage.hairline).frame(height: 1)

            HStack(spacing: 0) {
                VStack(spacing: 10) {
                    modeBar
                    languageBar
                    HStack(spacing: 12) {
                        sourceCard
                        VStack(spacing: 10) {
                            resultCard
                            if session.isComparing {
                                comparisonCard
                                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .animation(FerryMotion.animation(FerryMotion.spring), value: session.isComparing)
                    }
                    if let updateService {
                        UpdateBannerView(updateService: updateService)
                    }
                    if settingsStore.settings.doubleCopyEnabled && !copyMonitor.isAccessibilityTrusted {
                        permissionNotice
                    }
                    SpeechErrorBanner(speechService: speechService)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 16)
                .animation(FerryMotion.animation(FerryMotion.spring), value: copyMonitor.isAccessibilityTrusted)

                if uiState.showHistory {
                    Rectangle().fill(Stage.hairline).frame(width: 1)
                    historySidebar
                        .frame(width: 250)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
        }
        .frame(minWidth: 760, minHeight: 460)
        .background(StageBackdrop(hue: .teal))
        .ignoresSafeArea(.container, edges: .top)
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

    static let headerHeight: CGFloat = 44

    private var header: some View {
        HStack(spacing: 8) {
            Rectangle()
                .fill(Stage.hairline)
                .frame(width: 1, height: 14)
                .padding(.trailing, 4)

            FerryLogo(height: 15.5, color: FerryTheme.accentText)
            Text(l10n.brandName)
                .font(.system(size: 14.5, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)

            Spacer()

            ModelMenu(settingsStore: settingsStore, onOpenSettings: onOpenSettings)
                .padding(.trailing, 4)

            GlassIconButton(
                icon: .scanText,
                help: settingsStore.settings.screenshotOCREnabled
                    ? l10n.screenshotOCRShortcutTooltip(settingsStore.settings.screenshotOCRShortcut.displayString)
                    : l10n.screenshotOCRTooltip,
                action: onScreenshotOCR
            )
            GlassIconButton(icon: .history, help: l10n.historyTooltip, isOn: uiState.showHistory) {
                withAnimation(FerryMotion.animation(FerryMotion.spring)) {
                    uiState.showHistory.toggle()
                }
            }
            GlassIconButton(icon: .pictureInPicture2, help: l10n.miniWidgetTooltip, action: onToggleDesktopWidget)
            GlassIconButton(icon: .settings, help: l10n.settingsShortcutHelp, action: onOpenSettings)
        }
        .padding(.leading, 84) // aligned next to the centered macOS traffic-light buttons
        .padding(.trailing, 14)
        .frame(height: Self.headerHeight)
        .background(WindowDragArea())
    }

    // MARK: - Mode bar & Language bar

    private var modeBar: some View {
        HStack(spacing: 12) {
            ModePillStrip(selection: $session.mode)
                .layoutPriority(1)
            Spacer(minLength: 8)
            Text(session.mode.subtitle(in: lang))
                .font(.system(size: 11.5))
                .foregroundStyle(Stage.textTertiary)
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(-1)
        }
    }

    private var languageBar: some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                LucideIcon(.messageSquareText, size: 13)
                    .foregroundStyle(.secondary)
                Text(sourceLanguageLabel)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .contentTransition(.opacity)
                    .animation(FerryMotion.animation(FerryMotion.quick), value: sourceLanguageLabel)
                Spacer()
            }
            .padding(.leading, 4)
            .frame(maxWidth: .infinity)

            Button {
                withAnimation(FerryMotion.animation(FerryMotion.spring)) {
                    uiState.swapRotation += 180
                    session.swapWithTranslation()
                }
            } label: {
                LucideIcon(.arrowLeftRight, size: 14.5)
                    .rotationEffect(.degrees(uiState.swapRotation))
            }
            .buttonStyle(GlassIconStyle(size: 30))
            .disabled(!hasResult || session.isTranslating)
            .help(l10n.swapMainTooltip)
            .padding(.horizontal, 6)

            HStack {
                LanguagePickerControl(selection: $session.targetLanguage)
                if session.mode.preservesSourceLanguage(for: session.targetLanguage) {
                    Text(l10n.keepSourceLanguageLabel)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                } else if session.targetLanguage == .auto && (hasResult || session.isTranslating) {
                    Text(l10n.translatedTo(session.resolvedLanguage))
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .frame(maxWidth: .infinity)
        }
    }

    /// Detected source language, e.g. "英语（自动检测）" or "English (Detected)".
    private var sourceLanguageLabel: String {
        guard let name = LanguageDetection.displayName(for: session.sourceText, in: lang) else {
            return l10n.autoDetectLanguage
        }
        return l10n.detectedSourceLanguage(name)
    }

    // MARK: - Source

    private var sourceCard: some View {
        VStack(spacing: 0) {
            SmartTextView(
                text: $session.sourceText,
                placeholder: l10n.mainInputPlaceholder,
                submitOnEnter: false,
                fontSize: 15,
                focusTrigger: uiState.focusTrigger,
                onSubmit: {
                    session.translate()
                }
            )
            .padding(.horizontal, 8)
            .padding(.top, 6)

            HStack(spacing: 8) {
                Text(l10n.characterCount(session.sourceText.count))
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)

                Spacer()

                SpeakButton(
                    speechService: speechService,
                    id: "main-source",
                    text: session.sourceText,
                    help: l10n.speakSource
                )

                IconButton(icon: .clipboardPaste, help: l10n.pasteAndTranslateTooltip) {
                    if let clip = NSPasteboard.general.string(forType: .string), !clip.isEmpty {
                        session.translate(text: clip)
                    } else if let image = ScreenCaptureService.imageFromPasteboard() {
                        onPasteImageOCR(image)
                    }
                }
                if !session.sourceText.isEmpty {
                    IconButton(icon: .circleX, help: l10n.clear) {
                        session.clear()
                    }
                }

                Group {
                    if session.isTranslating {
                        Button(role: .cancel) {
                            session.cancel()
                        } label: {
                            HStack(spacing: 6) {
                                LucideIcon(.square, size: 10.5, filled: true)
                                Text(l10n.stop)
                            }
                        }
                        .buttonStyle(GlassButtonStyle(height: 30))
                    } else {
                        Button {
                            session.translate()
                        } label: {
                            HStack(spacing: 6) {
                                Text(l10n.runActionLabel(for: session.mode))
                                LucideIcon(.arrowRight, size: 13, strokeWidth: 2.2)
                            }
                            .padding(.horizontal, 4)
                        }
                        .buttonStyle(GlassButtonStyle(kind: .glow, hue: .teal, height: 30))
                        .keyboardShortcut(.return, modifiers: .command)
                        .disabled(!hasSource)
                        .help(l10n.runActionShortcutHelp(for: session.mode))
                    }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glassSurface(cornerRadius: 16)
        .animation(FerryMotion.animation(FerryMotion.quick), value: session.isTranslating)
        .animation(FerryMotion.animation(FerryMotion.quick), value: session.sourceText.isEmpty)
    }

    // MARK: - Result

    private var resultCard: some View {
        VStack(spacing: 0) {
            if session.isComparing {
                HStack(spacing: 6) {
                    Circle()
                        .fill(FerryTheme.accent)
                        .frame(width: 5.5, height: 5.5)
                    Text(session.effectiveResultModel.displayLabel(in: lang))
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.top, 9)
                .padding(.bottom, 4)

                Rectangle().fill(Stage.hairline).frame(height: 1)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
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
                    } else if session.isRecognizingOCR {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text(l10n.recognizingOCREllipsis)
                                .font(.system(size: 13.5))
                                .foregroundStyle(.secondary)
                        }
                    } else if !hasResult && !session.isTranslating {
                        emptyResult
                    } else if !hasResult && session.isTranslating {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text(l10n.providerTranslating(session.effectiveResultModel.provider))
                                .font(.system(size: 13.5))
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text(session.translatedText)
                            .font(.system(size: 15))
                            .lineSpacing(5)
                            .foregroundStyle(.primary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, session.isComparing ? 10 : 12)
                .padding(.bottom, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .animation(FerryMotion.animation(FerryMotion.quick), value: hasResult)
                .animation(FerryMotion.animation(FerryMotion.quick), value: session.errorMessage)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack(spacing: 8) {
                if session.isTranslating {
                    ProgressView().controlSize(.mini)
                    Text(l10n.generating)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                } else if hasResult {
                    Text(l10n.characterCount(session.translatedText.count))
                        .font(.system(size: 11))
                        .monospacedDigit()
                        .foregroundStyle(.tertiary)
                    if session.isFromCache {
                        CachedResultBadge()
                    }
                    if session.isModelOverridden && !session.isComparing {
                        ModelOverrideBadge(model: session.effectiveResultModel.model)
                    }
                }
                Spacer()
                HStack(spacing: 4) {
                    if hasResult && !session.isTranslating {
                        QuickModelSwitchMenu(
                            session: session,
                            settingsStore: settingsStore,
                            showCompareOption: !session.isComparing,
                            size: 26,
                            onOpenSettings: onOpenSettings
                        )
                        CompareToggleButton(
                            session: session,
                            settingsStore: settingsStore,
                            size: 26
                        )
                    }
                    if (session.isFromCache || session.isModelOverridden) && hasResult && !session.isTranslating {
                        RetranslateButton(size: 26, bypassCache: session.isFromCache) {
                            session.retranslate(bypassCache: true)
                        }
                    }
                    SpeakButton(
                        speechService: speechService,
                        id: "main-result",
                        text: session.translatedText,
                        languageHint: session.outputLanguageHint,
                        help: l10n.speakTranslation
                    )
                    CopyResultButton(copied: session.copiedRecently, disabled: !hasResult) {
                        session.copyTranslation()
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glassSurface(cornerRadius: 16, fill: FerryTheme.accent.opacity(0.07))
    }

    private var comparisonCard: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                ComparisonModelPicker(
                    session: session,
                    settingsStore: settingsStore,
                    onOpenSettings: onOpenSettings
                )
                Spacer(minLength: 4)
                if hasComparisonResult && !session.isComparisonTranslating {
                    Button(l10n.adoptComparisonButton) {
                        withAnimation(FerryMotion.animation(FerryMotion.spring)) {
                            session.adoptComparisonResult()
                        }
                    }
                    .buttonStyle(GlassButtonStyle(kind: .glass, height: 22))
                    .help(l10n.adoptComparisonTooltip)
                }
                Button {
                    withAnimation(FerryMotion.animation(FerryMotion.spring)) {
                        session.closeComparison()
                    }
                } label: {
                    LucideIcon(.x, size: 12.5)
                }
                .buttonStyle(HoverIconButtonStyle(size: 22))
                .help(l10n.closeCompareTooltip)
                .accessibilityLabel(l10n.closeCompareTooltip)
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 6)

            Rectangle().fill(Stage.hairline).frame(height: 1)

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if let error = session.comparisonErrorMessage {
                        ErrorBannerView(
                            message: error,
                            showSettingsAction: error.contains("API Key") || error.contains("401"),
                            onOpenSettings: onOpenSettings
                        )
                    } else if !hasComparisonResult && session.isComparisonTranslating {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text(l10n.providerTranslating(session.comparisonModel?.provider ?? settingsStore.settings.activeProvider))
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                        }
                    } else if hasComparisonResult {
                        Text(session.comparisonText)
                            .font(.system(size: 14.5))
                            .lineSpacing(4.5)
                            .foregroundStyle(.primary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Text(l10n.translationPlaceholder)
                            .font(.system(size: 14.5))
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 10)
                .padding(.bottom, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack(spacing: 8) {
                if session.isComparisonTranslating {
                    ProgressView().controlSize(.mini)
                    Text(l10n.generating)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                } else if hasComparisonResult {
                    Text(l10n.characterCount(session.comparisonText.count))
                        .font(.system(size: 11))
                        .monospacedDigit()
                        .foregroundStyle(.tertiary)
                    if session.isComparisonFromCache {
                        CachedResultBadge()
                    }
                }
                Spacer()
                HStack(spacing: 4) {
                    if session.isComparisonTranslating {
                        Button(l10n.stop) {
                            session.cancelComparison()
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.red)
                    } else {
                        RetranslateButton(
                            size: 26,
                            bypassCache: session.isComparisonFromCache,
                            disabled: !hasSource
                        ) {
                            session.retranslateComparison(bypassCache: true)
                        }
                    }
                    SpeakButton(
                        speechService: speechService,
                        id: "main-compare-result",
                        text: session.comparisonText,
                        languageHint: session.outputLanguageHint,
                        help: l10n.speakTranslation
                    )
                    CopyResultButton(copied: session.comparisonCopiedRecently, disabled: !hasComparisonResult) {
                        session.copyComparisonTranslation()
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glassSurface(cornerRadius: 16, fill: StageHue.azure.bottom.opacity(0.065))
    }

    @ViewBuilder
    private var emptyResult: some View {
        if settingsStore.hasActiveAPIKey {
            Text(l10n.translationPlaceholder)
                .font(.system(size: 15))
                .foregroundStyle(.tertiary)
        } else {
            VStack(spacing: 12) {
                HueOrb(systemName: "key.fill", hue: .amber, size: 48)
                    .padding(.bottom, 4)
                Text(l10n.missingAPIKeyTitle)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                Button(l10n.openSettings, action: onOpenSettings)
                    .buttonStyle(GlassButtonStyle(kind: .glow, hue: .teal, height: 30))
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 60)
        }
    }

    private var permissionNotice: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(l10n.permissionNoticeText)
                .font(.system(size: 12))
            Spacer()
            Button(l10n.permissionNoticeAction) {
                copyMonitor.openAccessibilitySettings()
            }
            .buttonStyle(GlassButtonStyle(kind: .glow, hue: .coral, height: 24))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .glassSurface(cornerRadius: 12, fill: Color.orange.opacity(0.12))
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }

    // MARK: - History

    private var historySidebar: some View {
        VStack(spacing: 0) {
            HStack {
                GlassLabel(l10n.historyHeader)
                Spacer()
                if !settingsStore.recentRecords.isEmpty {
                    Button(l10n.clear) {
                        settingsStore.clearRecentRecords()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Stage.textSecondary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            if settingsStore.recentRecords.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    LucideIcon(.messageSquareText, size: 24, strokeWidth: 1.6)
                        .foregroundStyle(.tertiary)
                    Text(l10n.historyEmpty)
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(settingsStore.recentRecords) { record in
                            Button {
                                session.loadRecord(record)
                            } label: {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(record.sourceText)
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(.primary)
                                        .lineLimit(2)
                                    Text(record.translatedText)
                                        .font(.system(size: 12))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                    HStack(spacing: 4) {
                                        if record.mode.isWritingMode {
                                            Text(record.mode.shortName(in: lang))
                                                .foregroundStyle(FerryTheme.accentText)
                                            Text("·")
                                        }
                                        Text(record.mode.preservesSourceLanguage(for: record.targetLanguage)
                                             ? l10n.keepSourceLanguageLabel
                                             : l10n.translatedTo(record.resolvedLanguage))
                                        Text("·")
                                        Text(record.createdAt, format: .relative(presentation: .named))
                                            .environment(\.locale, lang.locale)
                                    }
                                    .font(.system(size: 10.5))
                                    .foregroundStyle(.tertiary)
                                }
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .glassSurface(cornerRadius: 11)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                }
            }
        }
        .background(Stage.sidebarFill)
    }
}

/// Provider + model chip with a menu to switch providers; shared by the main window and the popover.
struct ModelMenu: View {
    var settingsStore: SettingsStore
    var onOpenSettings: () -> Void
    var compact: Bool = false

    private var lang: ResolvedAppLanguage { settingsStore.resolvedLanguage }
    private var l10n: L10n { L10n(lang) }

    var body: some View {
        Menu {
            ForEach(ProviderKind.allCases) { kind in
                Button {
                    settingsStore.settings.activeProvider = kind
                } label: {
                    if settingsStore.settings.activeProvider == kind {
                        Label("\(kind.shortName(in: lang)) · \(settingsStore.profile(for: kind).effectiveModel)", systemImage: "checkmark")
                    } else {
                        Text("\(kind.shortName(in: lang)) · \(settingsStore.profile(for: kind).effectiveModel)")
                    }
                }
            }
            Divider()
            Button(l10n.modelSettingsItem, action: onOpenSettings)
        } label: {
            HStack(spacing: 5) {
                Circle()
                    .fill(settingsStore.hasActiveAPIKey ? Color.green : Color.orange)
                    .frame(width: 6, height: 6)
                Text(compact
                     ? settingsStore.settings.activeProfile.effectiveModel
                     : "\(settingsStore.settings.activeProvider.shortName(in: lang)) · \(settingsStore.settings.activeProfile.effectiveModel)")
                    .font(.system(size: compact ? 11 : 12, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                LucideIcon(.chevronDown, size: 10.5, strokeWidth: 2.1)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, compact ? 9 : 11)
            .padding(.vertical, compact ? 3 : 6)
            .background(FerryTheme.chipFill, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.1), lineWidth: 1))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(settingsStore.hasActiveAPIKey ? l10n.switchProviderHelp : l10n.missingProviderKeyHelp)
    }
}

#if DEBUG
#Preview("主窗口") {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("FerryPreview", isDirectory: true)
    let store = SettingsStore(directory: dir)
    let service = LLMTranslatorService()
    let session = TranslatorSession(settingsStore: store, translatorService: service)
    let monitor = GlobalCopyMonitor(settingsStore: store)
    let speech = SpeechService(settingsStore: store)
    let uiState = MainWindowUIState()
    MainWindowView(
        session: session,
        settingsStore: store,
        copyMonitor: monitor,
        speechService: speech,
        uiState: uiState,
        onToggleDesktopWidget: {},
        onOpenSettings: {}
    )
    .frame(width: 920, height: 580)
}
#endif
