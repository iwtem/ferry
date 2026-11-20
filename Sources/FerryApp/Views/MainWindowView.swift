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
    public var uiState: MainWindowUIState
    public var onToggleDesktopWidget: () -> Void
    public var onOpenSettings: () -> Void

    public init(
        session: TranslatorSession,
        settingsStore: SettingsStore,
        copyMonitor: GlobalCopyMonitor,
        speechService: SpeechService,
        uiState: MainWindowUIState,
        onToggleDesktopWidget: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void
    ) {
        self.session = session
        self.settingsStore = settingsStore
        self.copyMonitor = copyMonitor
        self.speechService = speechService
        self.uiState = uiState
        self.onToggleDesktopWidget = onToggleDesktopWidget
        self.onOpenSettings = onOpenSettings
    }

    private var hasSource: Bool {
        !session.sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var hasResult: Bool {
        !session.translatedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public var body: some View {
        VStack(spacing: 0) {
            header

            Rectangle().fill(Stage.hairline).frame(height: 1)

            HStack(spacing: 0) {
                VStack(spacing: 10) {
                    languageBar
                    HStack(spacing: 12) {
                        sourceCard
                        resultCard
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
        .onChange(of: session.targetLanguage) { _, _ in
            if hasSource {
                session.translate()
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            FerryLogo(height: 17, color: FerryTheme.accentText)
            Text("渡 Ferry")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)

            Spacer()

            ModelMenu(settingsStore: settingsStore, onOpenSettings: onOpenSettings)
                .padding(.trailing, 4)

            GlassIconButton(systemName: "clock.arrow.circlepath", help: "翻译记录", isOn: uiState.showHistory) {
                withAnimation(FerryMotion.animation(FerryMotion.spring)) {
                    uiState.showHistory.toggle()
                }
            }
            GlassIconButton(systemName: "pip", help: "桌面小窗", action: onToggleDesktopWidget)
            GlassIconButton(systemName: "gearshape", help: "设置 (⌘,)", action: onOpenSettings)
        }
        .padding(.leading, 80) // room for the traffic-light buttons
        .padding(.trailing, 14)
        .frame(height: 50)
        .background(WindowDragArea())
    }

    // MARK: - Language bar

    private var languageBar: some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "text.viewfinder")
                    .font(.system(size: 11, weight: .medium))
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
                Image(systemName: "arrow.left.arrow.right")
                    .rotationEffect(.degrees(uiState.swapRotation))
            }
            .buttonStyle(GlassIconStyle(size: 30))
            .disabled(!hasResult || session.isTranslating)
            .help("把译文放回左侧，反向翻译")
            .padding(.horizontal, 6)

            HStack {
                LanguagePickerControl(selection: $session.targetLanguage)
                if session.targetLanguage == .auto && (hasResult || session.isTranslating) {
                    Text("译为\(session.resolvedLanguage.shortName)")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .frame(maxWidth: .infinity)
        }
    }

    /// Detected source language, e.g. "英语（自动检测）".
    private var sourceLanguageLabel: String {
        guard let name = LanguageDetection.displayName(for: session.sourceText) else { return "自动检测语言" }
        return "\(name)（自动检测）"
    }

    // MARK: - Source

    private var sourceCard: some View {
        VStack(spacing: 0) {
            SmartTextView(
                text: $session.sourceText,
                placeholder: "输入或粘贴文本，⌘⏎ 翻译",
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
                Text("\(session.sourceText.count) 字")
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)

                Spacer()

                SpeakButton(
                    speechService: speechService,
                    id: "main-source",
                    text: session.sourceText,
                    help: "朗读原文"
                )

                IconButton(systemName: "doc.on.clipboard", help: "粘贴并翻译") {
                    if let clip = NSPasteboard.general.string(forType: .string), !clip.isEmpty {
                        session.translate(text: clip)
                    }
                }
                if !session.sourceText.isEmpty {
                    IconButton(systemName: "xmark.circle", help: "清空") {
                        session.clear()
                    }
                }

                Group {
                    if session.isTranslating {
                        Button(role: .cancel) {
                            session.cancel()
                        } label: {
                            Label("停止", systemImage: "stop.fill")
                        }
                        .buttonStyle(GlassButtonStyle(height: 30))
                    } else {
                        Button {
                            session.translate()
                        } label: {
                            HStack(spacing: 6) {
                                Text("翻译")
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 11, weight: .bold))
                            }
                            .padding(.horizontal, 4)
                        }
                        .buttonStyle(GlassButtonStyle(kind: .glow, hue: .teal, height: 30))
                        .keyboardShortcut(.return, modifiers: .command)
                        .disabled(!hasSource)
                        .help("翻译 (⌘⏎)")
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
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if let error = session.errorMessage {
                        ErrorBannerView(
                            message: error,
                            showSettingsAction: error.contains("API Key") || error.contains("401"),
                            onOpenSettings: onOpenSettings
                        )
                    } else if !hasResult && !session.isTranslating {
                        emptyResult
                    } else if !hasResult && session.isTranslating {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("\(settingsStore.settings.activeProvider.shortName) 正在翻译…")
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
                .padding(.top, 12)
                .padding(.bottom, 8)
                .animation(FerryMotion.animation(FerryMotion.quick), value: hasResult)
                .animation(FerryMotion.animation(FerryMotion.quick), value: session.errorMessage)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack(spacing: 8) {
                if session.isTranslating {
                    ProgressView().controlSize(.mini)
                    Text("生成中")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                } else if hasResult {
                    Text("\(session.translatedText.count) 字")
                        .font(.system(size: 11))
                        .monospacedDigit()
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                SpeakButton(
                    speechService: speechService,
                    id: "main-result",
                    text: session.translatedText,
                    languageHint: session.resolvedLanguage,
                    help: "朗读译文"
                )
                CopyResultButton(copied: session.copiedRecently, disabled: !hasResult) {
                    session.copyTranslation()
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glassSurface(cornerRadius: 16, fill: FerryTheme.accent.opacity(0.07))
    }

    @ViewBuilder
    private var emptyResult: some View {
        if settingsStore.hasActiveAPIKey {
            Text("译文")
                .font(.system(size: 15))
                .foregroundStyle(.tertiary)
        } else {
            VStack(spacing: 12) {
                HueOrb(systemName: "key.fill", hue: .amber, size: 48)
                    .padding(.bottom, 4)
                Text("还没填 API Key")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                Button("去设置", action: onOpenSettings)
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
            Text("划词翻译需要辅助功能权限")
                .font(.system(size: 12))
            Spacer()
            Button("去开启") {
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
                GlassLabel("记录")
                Spacer()
                if !settingsStore.recentRecords.isEmpty {
                    Button("清空") {
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
                    Image(systemName: "text.bubble")
                        .font(.system(size: 24))
                        .foregroundStyle(.tertiary)
                    Text("还没有记录")
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
                                        Text("译为\(record.resolvedLanguage.shortName)")
                                        Text("·")
                                        Text(record.createdAt, format: .relative(presentation: .named))
                                            .environment(\.locale, Locale(identifier: "zh_CN"))
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

    var body: some View {
        Menu {
            ForEach(ProviderKind.allCases) { kind in
                Button {
                    settingsStore.settings.activeProvider = kind
                } label: {
                    if settingsStore.settings.activeProvider == kind {
                        Label("\(kind.shortName) · \(settingsStore.profile(for: kind).effectiveModel)", systemImage: "checkmark")
                    } else {
                        Text("\(kind.shortName) · \(settingsStore.profile(for: kind).effectiveModel)")
                    }
                }
            }
            Divider()
            Button("模型设置…", action: onOpenSettings)
        } label: {
            HStack(spacing: 5) {
                Circle()
                    .fill(settingsStore.hasActiveAPIKey ? Color.green : Color.orange)
                    .frame(width: 6, height: 6)
                Text(compact
                     ? settingsStore.settings.activeProfile.effectiveModel
                     : "\(settingsStore.settings.activeProvider.shortName) · \(settingsStore.settings.activeProfile.effectiveModel)")
                    .font(.system(size: compact ? 11 : 12, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8.5, weight: .bold))
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
        .help(settingsStore.hasActiveAPIKey ? "切换模型服务商" : "当前服务商还没有配置 API Key")
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
