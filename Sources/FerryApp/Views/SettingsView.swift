import FerryCore
import Observation
import SwiftUI

public enum SettingsPane: String, CaseIterable, Identifiable, Sendable {
    case models
    case shortcut
    case general

    public var id: String { rawValue }

    var title: String {
        switch self {
        case .models: return "模型"
        case .shortcut: return "划词"
        case .general: return "通用"
        }
    }

    var tagline: String {
        switch self {
        case .models: return "选一个服务商，填好 Key 就能翻译"
        case .shortcut: return "选中文字，连按两次 ⌘C"
        case .general: return "外观、语言、朗读与数据"
        }
    }

    var systemImage: String {
        switch self {
        case .models: return "cpu"
        case .shortcut: return "command"
        case .general: return "slider.horizontal.3"
        }
    }

    var hue: StageHue {
        switch self {
        case .models: return .teal
        case .shortcut: return .coral
        case .general: return .violet
        }
    }
}

extension ProviderKind {
    var stageHue: StageHue {
        switch self {
        case .deepseek: return StageHue(top: Color(hex: 0x7D9BFF), bottom: Color(hex: 0x3D5AFE))
        case .bailian: return .amber
        case .custom: return .violet
        }
    }

    var symbol: String {
        switch self {
        case .deepseek: return "fish.fill"
        case .bailian: return "cloud.fill"
        case .custom: return "puzzlepiece.extension.fill"
        }
    }
}

@MainActor
@Observable
public final class SettingsUIState {
    public var selectedPane: SettingsPane = .models
    public var selectedProviderTab: ProviderKind
    public var isTestingConnection: Bool = false
    public var testStatusMessage: String? = nil
    public var testStatusSuccess: Bool = false
    public var isFetchingModels: Bool = false
    /// Result of the last model-list fetch, keyed by provider so switching providers doesn't mix messages.
    public var modelFetchMessage: [ProviderKind: (text: String, success: Bool)] = [:]

    public init(initialProvider: ProviderKind) {
        self.selectedProviderTab = initialProvider
    }
}

public struct SettingsView: View {
    public var settingsStore: SettingsStore
    public var copyMonitor: GlobalCopyMonitor
    public var translatorService: LLMTranslatorService
    public var speechService: SpeechService
    @Bindable public var uiState: SettingsUIState

    public static let windowSize = CGSize(width: 780, height: 600)

    public init(
        settingsStore: SettingsStore,
        copyMonitor: GlobalCopyMonitor,
        translatorService: LLMTranslatorService,
        speechService: SpeechService,
        uiState: SettingsUIState
    ) {
        self.settingsStore = settingsStore
        self.copyMonitor = copyMonitor
        self.translatorService = translatorService
        self.speechService = speechService
        self.uiState = uiState
    }

    private var needsAccessibilityAttention: Bool {
        settingsStore.settings.doubleCopyEnabled && !copyMonitor.isAccessibilityTrusted
    }

    public var body: some View {
        HStack(spacing: 0) {
            sidebar
            detailPane
        }
        .frame(width: Self.windowSize.width, height: Self.windowSize.height)
        .background(StageBackdrop(hue: uiState.selectedPane.hue))
        .tint(FerryTheme.accent)
        .onAppear {
            copyMonitor.refreshPermissionStatus()
            uiState.selectedProviderTab = settingsStore.settings.activeProvider
        }
        .onChange(of: settingsStore.settings.activeProvider) { _, newValue in
            uiState.selectedProviderTab = newValue
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                FerryLogo(height: 16, color: FerryTheme.accentText)
                Text("渡 Ferry")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
            }
            .padding(.leading, 8)
            .padding(.bottom, 14)

            ForEach(SettingsPane.allCases) { pane in
                SidebarItem(
                    pane: pane,
                    selected: uiState.selectedPane == pane,
                    alert: pane == .shortcut && needsAccessibilityAttention
                ) {
                    withAnimation(FerryMotion.animation(FerryMotion.spring)) {
                        uiState.selectedPane = pane
                    }
                }
            }

            Spacer(minLength: 0)

            Text("v\(Self.appVersion)")
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(Stage.textTertiary)
                .padding(.leading, 8)
        }
        .padding(.top, 52)
        .padding(.horizontal, 12)
        .padding(.bottom, 16)
        .frame(width: 188)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Stage.sidebarFill)
        .overlay(alignment: .trailing) {
            Rectangle().fill(Stage.hairline).frame(width: 1)
        }
        .background(WindowDragArea())
    }

    // MARK: - Detail

    private var detailPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Group {
                    switch uiState.selectedPane {
                    case .models: modelsPane
                    case .shortcut: shortcutPane
                    case .general: generalPane
                    }
                }
                .id(uiState.selectedPane)
                .transition(.opacity.combined(with: .offset(y: 6)))
            }
            .padding(.horizontal, 28)
            .padding(.top, 44)
            .padding(.bottom, 28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.never)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func hero(_ pane: SettingsPane) -> some View {
        StageHero(systemName: pane.systemImage, hue: pane.hue, title: pane.title, tagline: pane.tagline)
            .background(WindowDragArea())
    }

    // MARK: - Models

    private var modelsPane: some View {
        let provider = uiState.selectedProviderTab
        let profile = settingsStore.profile(for: provider)
        let customBaseURL = profile.baseURL != provider.defaultBaseURL
        let hasCustomModel = !profile.customModel.trimmingCharacters(in: .whitespaces).isEmpty

        return VStack(alignment: .leading, spacing: 22) {
            hero(.models)

            HStack(spacing: 10) {
                ForEach(ProviderKind.allCases) { kind in
                    ProviderTile(
                        kind: kind,
                        model: settingsStore.profile(for: kind).effectiveModel,
                        configured: !settingsStore.apiKey(for: kind).trimmingCharacters(in: .whitespaces).isEmpty,
                        selected: settingsStore.settings.activeProvider == kind
                    ) {
                        withAnimation(FerryMotion.animation(FerryMotion.spring)) {
                            settingsStore.settings.activeProvider = kind
                            uiState.selectedProviderTab = kind
                            uiState.testStatusMessage = nil
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                GlassLabel("\(provider.shortName) 连接")
                GlassCard {
                    GlassRow(title: "API Key") {
                        GlassField(placeholder: "sk-…", text: apiKeyBinding(for: provider), secure: true)
                            .frame(width: 320)
                    }

                    GlassRow(title: "接口地址") {
                        HStack(spacing: 6) {
                            GlassField(
                                placeholder: provider.defaultBaseURL,
                                text: Binding(
                                    get: { profile.baseURL },
                                    set: { newValue in
                                        var updated = settingsStore.profile(for: provider)
                                        updated.baseURL = newValue
                                        updated.fetchedModels = []
                                        settingsStore.updateProfile(updated, for: provider)
                                    }
                                )
                            )
                            if customBaseURL {
                                GlassIconButton(systemName: "arrow.uturn.backward", help: "恢复默认地址") {
                                    var updated = settingsStore.profile(for: provider)
                                    updated.baseURL = provider.defaultBaseURL
                                    updated.fetchedModels = []
                                    withAnimation(FerryMotion.animation(FerryMotion.quick)) {
                                        settingsStore.updateProfile(updated, for: provider)
                                    }
                                }
                            }
                        }
                        .frame(width: 320)
                    }

                    GlassRow(title: "模型", caption: hasCustomModel ? "已被自定义模型覆盖" : nil) {
                        HStack(spacing: 6) {
                            ModelPickerButton(
                                models: profile.selectableModels(for: provider),
                                selection: Binding(
                                    get: { profile.model },
                                    set: { newValue in
                                        var updated = settingsStore.profile(for: provider)
                                        updated.model = newValue
                                        settingsStore.updateProfile(updated, for: provider)
                                    }
                                )
                            )
                            .disabled(hasCustomModel)
                            .opacity(hasCustomModel ? 0.45 : 1)

                            Button {
                                fetchModels(for: provider)
                            } label: {
                                SpinningRefreshIcon(active: uiState.isFetchingModels)
                                    .font(.system(size: 12, weight: .medium))
                            }
                            .buttonStyle(GlassIconStyle())
                            .disabled(uiState.isFetchingModels)
                            .help("从服务商拉取模型列表")
                        }
                    }

                    GlassRow(title: "自定义模型", divider: false) {
                        GlassField(
                            placeholder: "可选，填写模型 ID",
                            text: Binding(
                                get: { profile.customModel },
                                set: { newValue in
                                    var updated = settingsStore.profile(for: provider)
                                    updated.customModel = newValue
                                    settingsStore.updateProfile(updated, for: provider)
                                }
                            )
                        )
                        .frame(width: 220)
                    }
                }

                HStack(spacing: 10) {
                    Text(modelListFooter(provider: provider, profile: profile))
                        .font(.system(size: 11))
                        .foregroundStyle(modelFooterColor(provider))
                        .lineLimit(2)
                        .help(uiState.modelFetchMessage[provider]?.text ?? "")
                    Spacer(minLength: 8)
                }
                .padding(.horizontal, 4)
            }

            HStack(spacing: 12) {
                Button {
                    runConnectionTest(for: provider)
                } label: {
                    HStack(spacing: 6) {
                        if uiState.isTestingConnection {
                            ProgressView().controlSize(.mini)
                        } else {
                            Image(systemName: "bolt.fill").font(.system(size: 11))
                        }
                        Text(uiState.isTestingConnection ? "测试中" : "测试连接")
                    }
                }
                .buttonStyle(GlassButtonStyle(kind: .glow, hue: .teal, height: 30))
                .disabled(uiState.isTestingConnection)

                if let message = uiState.testStatusMessage {
                    StatusLine(text: message, success: uiState.testStatusSuccess)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
            }
            .animation(FerryMotion.animation(FerryMotion.spring), value: uiState.testStatusMessage)
        }
        .task(id: provider) {
            if settingsStore.profile(for: provider).fetchedModels.isEmpty,
               !settingsStore.apiKey(for: provider).isEmpty,
               uiState.modelFetchMessage[provider] == nil {
                fetchModels(for: provider)
            }
        }
    }

    private func modelListFooter(provider: ProviderKind, profile: ProviderProfile) -> String {
        if let message = uiState.modelFetchMessage[provider], !message.success {
            return message.text
        }
        if profile.fetchedModels.isEmpty {
            return "内置推荐列表 · 填好 Key 后点 ↻ 拉取全部模型"
        }
        return "\(profile.fetchedModels.count) 个可用模型"
    }

    private func modelFooterColor(_ provider: ProviderKind) -> Color {
        if let message = uiState.modelFetchMessage[provider], !message.success {
            return Stage.warn
        }
        return Stage.textTertiary
    }

    private func apiKeyBinding(for provider: ProviderKind) -> Binding<String> {
        Binding(
            get: { settingsStore.apiKey(for: provider) },
            set: { settingsStore.setAPIKey($0, for: provider) }
        )
    }

    // MARK: - Shortcut

    private var shortcutPane: some View {
        let enabled = settingsStore.settings.doubleCopyEnabled
        let trusted = copyMonitor.isAccessibilityTrusted

        return VStack(alignment: .leading, spacing: 22) {
            StageHero(
                systemName: SettingsPane.shortcut.systemImage,
                hue: SettingsPane.shortcut.hue,
                title: SettingsPane.shortcut.title,
                tagline: SettingsPane.shortcut.tagline
            ) {
                DoubleCopyKeys()
            }
            .background(WindowDragArea())

            GlassCard {
                GlassRow(title: "双击 ⌘C 翻译") {
                    GlassToggle(isOn: Binding(
                        get: { settingsStore.settings.doubleCopyEnabled },
                        set: { newValue in
                            withAnimation(FerryMotion.animation(FerryMotion.quick)) {
                                settingsStore.settings.doubleCopyEnabled = newValue
                            }
                        }
                    ))
                }
                GlassRow(title: "按键间隔", caption: "按得慢就调大一点", divider: false) {
                    HStack(spacing: 10) {
                        Slider(
                            value: Binding(
                                get: { Double(settingsStore.settings.doubleCopyIntervalMs) },
                                set: { settingsStore.settings.doubleCopyIntervalMs = Int(($0 / 25).rounded() * 25) }
                            ),
                            in: 250...700
                        )
                        .controlSize(.small)
                        .frame(width: 170)
                        Text("\(settingsStore.settings.doubleCopyIntervalMs) ms")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(Stage.textSecondary)
                            .frame(width: 56, alignment: .trailing)
                    }
                    .disabled(!enabled)
                    .opacity(enabled ? 1 : 0.4)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                GlassLabel("系统权限")
                GlassCard {
                    HStack(spacing: 12) {
                        HueTile(
                            systemName: trusted ? "checkmark.shield.fill" : "exclamationmark.shield.fill",
                            hue: trusted ? .teal : .amber,
                            size: 32
                        )
                        .contentTransition(.symbolEffect(.replace))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("辅助功能")
                                .font(.system(size: 13, weight: .medium))
                            Text(trusted ? "可以在任意应用里划词" : "授权后才能识别双击 ⌘C")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        StatusPill(
                            text: trusted ? "已授权" : "未授权",
                            color: trusted ? Stage.ok : Stage.warn
                        )
                        GlassIconButton(systemName: "arrow.clockwise", help: "重新检测") {
                            withAnimation(FerryMotion.animation(FerryMotion.spring)) {
                                copyMonitor.refreshPermissionStatus()
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)

                    if !trusted {
                        Rectangle().fill(Stage.hairline).frame(height: 1)
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 8) {
                                Button("打开系统设置") {
                                    copyMonitor.openAccessibilitySettings()
                                }
                                .buttonStyle(GlassButtonStyle(kind: .glow, hue: .coral))
                                Button("请求授权") {
                                    copyMonitor.requestAccessibilityPermission()
                                }
                                .buttonStyle(GlassButtonStyle())
                            }
                            Text("已勾选仍显示未授权？在列表里删掉 Ferry，再重新添加。")
                                .font(.system(size: 11))
                                .foregroundStyle(Stage.textTertiary)
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                Text("只在识别到双击 ⌘C 时读取一次剪贴板，不记录其他按键。")
                    .font(.system(size: 11))
                    .foregroundStyle(Stage.textTertiary)
                    .padding(.horizontal, 4)
            }
            .animation(FerryMotion.animation(FerryMotion.spring), value: trusted)
        }
    }

    // MARK: - General

    private var generalPane: some View {
        VStack(alignment: .leading, spacing: 22) {
            hero(.general)

            GlassCard {
                GlassRow(title: "外观", divider: false) {
                    GlassSegmented(
                        items: AppearanceMode.allCases,
                        selection: Binding(
                            get: { settingsStore.settings.appearance },
                            set: { newValue in
                                settingsStore.settings.appearance = newValue
                                FerryAppearance.apply(newValue)
                            }
                        ),
                        title: { $0.displayName },
                        systemImage: { mode in
                            switch mode {
                            case .system: return "circle.lefthalf.filled"
                            case .light: return "sun.max.fill"
                            case .dark: return "moon.fill"
                            }
                        }
                    )
                    .frame(width: 300)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                GlassLabel("翻译")
                GlassCard {
                    GlassRow(title: "默认目标语言", caption: "自动：中文译英文，其他译中文") {
                        GlassPicker(
                            items: TargetLanguage.allCases,
                            selection: Binding(
                                get: { settingsStore.settings.defaultTargetLanguage },
                                set: { settingsStore.settings.defaultTargetLanguage = $0 }
                            ),
                            title: { $0.displayName }
                        )
                    }
                    GlassRow(title: "单词释义", caption: "查单词时显示音标、词性和例句", divider: false) {
                        GlassToggle(isOn: Binding(
                            get: { settingsStore.settings.wordLookupEnabled },
                            set: { settingsStore.settings.wordLookupEnabled = $0 }
                        ))
                    }
                }
            }

            speechSection

            VStack(alignment: .leading, spacing: 8) {
                GlassLabel("其他")
                GlassCard {
                    GlassRow(title: "桌面小窗默认置顶") {
                        GlassToggle(isOn: Binding(
                            get: { settingsStore.settings.desktopWidgetAlwaysOnTop },
                            set: { settingsStore.settings.desktopWidgetAlwaysOnTop = $0 }
                        ))
                    }
                    GlassRow(
                        title: "翻译记录",
                        caption: "\(settingsStore.recentRecords.count) 条 · 设置和 Key 只存在本机",
                        divider: false
                    ) {
                        Button("清空") {
                            withAnimation(FerryMotion.animation(FerryMotion.quick)) {
                                settingsStore.clearRecentRecords()
                            }
                        }
                        .buttonStyle(GlassButtonStyle(kind: .destructive))
                        .disabled(settingsStore.recentRecords.isEmpty)
                    }
                }
            }
        }
    }

    private func engineLabel(_ engine: SpeechEngine) -> String {
        switch engine {
        case .system: return "系统"
        case .bailian: return "百炼"
        case .openAI: return "OpenAI"
        }
    }

    private func engineCaption(_ engine: SpeechEngine) -> String {
        switch engine {
        case .system: return "离线、免费。可在系统设置里下载增强语音"
        case .bailian: return "复用百炼的 Key，自动缓存最近 30 条"
        case .openAI: return "复用自定义服务的地址和 Key，自动缓存最近 30 条"
        }
    }

    private var rateRow: some View {
        GlassRow(title: "语速") {
            HStack(spacing: 10) {
                Slider(
                    value: Binding(
                        get: { settingsStore.settings.speech.rate },
                        set: { settingsStore.settings.speech.rate = ($0 / 0.05).rounded() * 0.05 }
                    ),
                    in: 0.7...1.5
                )
                .controlSize(.small)
                .frame(width: 150)
                Text(String(format: "%.2f×", settingsStore.settings.speech.rate))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Stage.textSecondary)
                    .frame(width: 48, alignment: .trailing)
            }
        }
    }

    private var speechSection: some View {
        let speech = settingsStore.settings.speech

        return VStack(alignment: .leading, spacing: 8) {
            GlassLabel("朗读")
            GlassCard {
                VStack(alignment: .leading, spacing: 8) {
                    GlassSegmented(
                        items: SpeechEngine.allCases,
                        selection: Binding(
                            get: { settingsStore.settings.speech.engine },
                            set: { newValue in
                                speechService.stop()
                                speechService.clearError()
                                settingsStore.settings.speech.engine = newValue
                            }
                        ),
                        title: engineLabel
                    )
                    Text(engineCaption(speech.engine))
                        .font(.system(size: 11))
                        .foregroundStyle(Stage.textTertiary)
                        .padding(.leading, 2)
                        .contentTransition(.opacity)
                }
                .padding(12)
                Rectangle().fill(Stage.hairline).frame(height: 1)

                switch speech.engine {
                case .system:
                    GlassRow(title: "英语口音") {
                        GlassPicker(
                            items: EnglishAccent.allCases,
                            selection: Binding(
                                get: { settingsStore.settings.speech.englishAccent },
                                set: { settingsStore.settings.speech.englishAccent = $0 }
                            ),
                            title: { $0.displayName }
                        )
                    }
                    rateRow

                case .bailian:
                    GlassRow(title: "音色") {
                        GlassPicker(
                            items: SpeechSettings.bailianVoices,
                            selection: Binding(
                                get: { settingsStore.settings.speech.bailianVoice },
                                set: { settingsStore.settings.speech.bailianVoice = $0 }
                            ),
                            title: { $0 }
                        )
                    }
                    GlassRow(title: "TTS 模型") {
                        GlassField(
                            placeholder: "qwen3-tts-flash",
                            text: Binding(
                                get: { settingsStore.settings.speech.bailianModel },
                                set: { settingsStore.settings.speech.bailianModel = $0 }
                            )
                        )
                        .frame(width: 200)
                    }

                case .openAI:
                    GlassRow(title: "音色") {
                        GlassPicker(
                            items: SpeechSettings.openAIVoices,
                            selection: Binding(
                                get: { settingsStore.settings.speech.openAIVoice },
                                set: { settingsStore.settings.speech.openAIVoice = $0 }
                            ),
                            title: { $0 }
                        )
                    }
                    GlassRow(title: "TTS 模型") {
                        GlassField(
                            placeholder: "gpt-4o-mini-tts",
                            text: Binding(
                                get: { settingsStore.settings.speech.openAIModel },
                                set: { settingsStore.settings.speech.openAIModel = $0 }
                            )
                        )
                        .frame(width: 200)
                    }
                    rateRow
                }

                GlassRow(title: "试听", divider: false) {
                    HStack(spacing: 6) {
                        previewButton(
                            id: "settings-preview-en",
                            label: "English",
                            text: "Serendipity is the joy of discovering something wonderful by chance.",
                            hint: .en
                        )
                        previewButton(
                            id: "settings-preview-zh",
                            label: "中文",
                            text: "渡 Ferry，轻量优雅的桌面大模型翻译工具。",
                            hint: .zhCN
                        )
                    }
                }

                if let error = speechService.lastErrorMessage {
                    Rectangle().fill(Stage.hairline).frame(height: 1)
                    StatusLine(text: error, success: false)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func previewButton(id: String, label: String, text: String, hint: TargetLanguage) -> some View {
        let active = speechService.isActive(id: id)
        return Button {
            speechService.toggleSpeak(text: text, id: id, languageHint: hint)
        } label: {
            HStack(spacing: 5) {
                if speechService.isLoading(id: id) {
                    ProgressView().controlSize(.mini)
                } else {
                    Image(systemName: active ? "stop.fill" : "play.fill")
                        .font(.system(size: 9.5))
                }
                Text(label)
            }
        }
        .buttonStyle(GlassButtonStyle(kind: active ? .glow : .glass, hue: .violet))
    }

    private static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    }

    // MARK: - Actions

    private func config(for provider: ProviderKind) -> TranslationRequestConfig {
        TranslationRequestConfig(
            provider: provider,
            profile: settingsStore.profile(for: provider),
            apiKey: settingsStore.apiKey(for: provider),
            temperature: settingsStore.settings.temperature
        )
    }

    private func fetchModels(for provider: ProviderKind) {
        uiState.isFetchingModels = true
        let config = config(for: provider)
        Task {
            do {
                let models = try await translatorService.fetchModels(config: config)
                var updated = settingsStore.profile(for: provider)
                updated.fetchedModels = models
                settingsStore.updateProfile(updated, for: provider)
                uiState.modelFetchMessage[provider] = models.isEmpty
                    ? ("服务商没有返回对话模型，继续用内置列表", false)
                    : ("\(models.count) 个可用模型", true)
            } catch {
                uiState.modelFetchMessage[provider] = ("拉取失败：\(error.localizedDescription)", false)
            }
            uiState.isFetchingModels = false
        }
    }

    private func runConnectionTest(for provider: ProviderKind) {
        withAnimation(FerryMotion.animation(FerryMotion.quick)) {
            uiState.isTestingConnection = true
            uiState.testStatusMessage = nil
        }
        let config = config(for: provider)

        Task {
            do {
                let result = try await translatorService.testConnection(config: config)
                uiState.testStatusSuccess = true
                uiState.testStatusMessage = "Hello → \(result)"
            } catch {
                uiState.testStatusSuccess = false
                uiState.testStatusMessage = error.localizedDescription
            }
            uiState.isTestingConnection = false
        }
    }
}

// MARK: - Sidebar item

private struct SidebarItem: View {
    let pane: SettingsPane
    let selected: Bool
    let alert: Bool
    let action: () -> Void
    @ViewState private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                HueTile(systemName: pane.systemImage, hue: pane.hue, size: 24)
                    .shadow(color: selected ? pane.hue.bottom.opacity(0.6) : .clear, radius: 6)
                Text(pane.title)
                    .font(.system(size: 13, weight: selected ? .semibold : .medium))
                    .foregroundStyle(selected ? Color.primary : Stage.textSecondary)
                Spacer(minLength: 0)
                if alert {
                    Circle()
                        .fill(Stage.warn)
                        .frame(width: 7, height: 7)
                        .shadow(color: Stage.warn, radius: 3)
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 36)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(selected ? Stage.selectedFill : (hovering ? Stage.controlFill : .clear))
                    .shadow(color: selected ? Stage.cardShadow : .clear, radius: 3, y: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(selected ? Stage.selectedStroke : .clear, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleStyle())
        .onHover { hovering = $0 }
        .animation(FerryMotion.animation(FerryMotion.quick), value: hovering)
    }
}

// MARK: - Provider tile

private struct ProviderTile: View {
    let kind: ProviderKind
    let model: String
    let configured: Bool
    let selected: Bool
    let action: () -> Void
    @ViewState private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    HueTile(systemName: kind.symbol, hue: kind.stageHue, size: 30)
                        .shadow(color: kind.stageHue.bottom.opacity(selected ? 0.6 : 0), radius: 8)
                    Spacer()
                    if selected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 15))
                            .foregroundStyle(.white, FerryTheme.accent)
                            .transition(.scale.combined(with: .opacity))
                    } else {
                        Circle()
                            .fill(configured ? Stage.ok : Stage.controlHover)
                            .frame(width: 7, height: 7)
                            .padding(4)
                            .help(configured ? "已填 Key" : "未填 Key")
                    }
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(kind.shortName)
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(configured ? model : "未填 Key")
                        .font(.system(size: 10.5, design: configured ? .monospaced : .default))
                        .foregroundStyle(configured ? Stage.textSecondary : Stage.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(selected ? FerryTheme.accent.opacity(0.14) : (hovering ? Stage.glassFillHover : Stage.glassFill))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(
                        selected
                            ? AnyShapeStyle(StageHue.teal.gradient)
                            : AnyShapeStyle(Stage.glassStroke),
                        lineWidth: selected ? 1.5 : 1
                    )
            )
            .shadow(color: selected ? FerryTheme.accent.opacity(0.3) : .clear, radius: 12, y: 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleStyle())
        .onHover { hovering = $0 }
        .animation(FerryMotion.animation(FerryMotion.quick), value: hovering)
        .animation(FerryMotion.animation(FerryMotion.spring), value: selected)
    }
}

// MARK: - ⌘C ⌘C illustration

private struct DoubleCopyKeys: View {
    var body: some View {
        HStack(spacing: 6) {
            Keycap(text: "⌘")
            Keycap(text: "C")
            Text("×2")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(Stage.warn)
        }
    }
}

private struct Keycap: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 15, weight: .semibold, design: .rounded))
            .foregroundStyle(.primary)
            .frame(width: 36, height: 34)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Stage.selectedFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Stage.selectedStroke, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.2), radius: 0, y: 2)
    }
}

// MARK: - Searchable Model Picker

/// Shows the selected model; clicking opens a searchable popover (providers can return 100+ models).
struct ModelPickerButton: View {
    let models: [String]
    @Binding var selection: String
    @ViewState private var showing = false
    @ViewState private var query = ""

    private var filtered: [String] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return q.isEmpty ? models : models.filter { $0.lowercased().contains(q) }
    }

    var body: some View {
        Button {
            showing.toggle()
        } label: {
            GlassMenuLabel(text: selection, monospaced: true)
                .frame(maxWidth: 240)
        }
        .buttonStyle(.plain)
        .fixedSize()
        .popover(isPresented: $showing, arrowEdge: .bottom) {
            VStack(spacing: 8) {
                GlassField(placeholder: "搜索 \(models.count) 个模型", text: $query, monospaced: false)

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(filtered, id: \.self) { model in
                                ModelRow(model: model, selected: model == selection) {
                                    selection = model
                                    showing = false
                                }
                                .id(model)
                            }
                            if filtered.isEmpty {
                                Text("没有匹配的模型，可以填到「自定义模型」")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                                    .padding(.vertical, 16)
                            }
                        }
                    }
                    .onAppear { proxy.scrollTo(selection, anchor: .center) }
                }
            }
            .padding(10)
            .frame(width: 320, height: 340)
            .onDisappear { query = "" }
        }
    }
}

private struct ModelRow: View {
    let model: String
    let selected: Bool
    let action: () -> Void
    @ViewState private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack {
                Text(model)
                    .font(.system(size: 12.5, design: .monospaced))
                    .foregroundStyle(selected ? FerryTheme.accentText : .primary)
                Spacer()
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(FerryTheme.accentText)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(selected ? FerryTheme.accent.opacity(0.16) : Color.primary.opacity(hovering ? 0.07 : 0))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(FerryMotion.animation(FerryMotion.quick), value: hovering)
    }
}

#if DEBUG
#Preview("设置窗口") {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("FerryPreview", isDirectory: true)
    let store = SettingsStore(directory: dir)
    let monitor = GlobalCopyMonitor(settingsStore: store)
    let service = LLMTranslatorService()
    let speech = SpeechService(settingsStore: store)
    let uiState = SettingsUIState(initialProvider: store.settings.activeProvider)
    SettingsView(
        settingsStore: store,
        copyMonitor: monitor,
        translatorService: service,
        speechService: speech,
        uiState: uiState
    )
}
#endif
