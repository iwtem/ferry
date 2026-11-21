import AppKit
import FerryCore
import Observation
import SwiftUI

public enum SettingsPane: String, CaseIterable, Identifiable, Sendable {
    case models
    case shortcut
    case general

    public var id: String { rawValue }

    func title(in language: ResolvedAppLanguage) -> String {
        L10n(language).settingsPaneTitle(self)
    }

    func tagline(in language: ResolvedAppLanguage) -> String {
        L10n(language).settingsPaneTagline(self)
    }

    var hue: StageHue {
        switch self {
        case .models: return .teal
        case .shortcut: return .coral
        case .general: return .azure
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
    public var launchAtLogin: LaunchAtLoginService
    public var screenCaptureService: ScreenCaptureService
    public var hotkeyService: GlobalHotkeyService
    public var updateService: AppUpdateService
    public var onTriggerScreenshotOCR: () -> Void
    @Bindable public var uiState: SettingsUIState

    public static let windowSize = CGSize(width: 780, height: 600)

    public init(
        settingsStore: SettingsStore,
        copyMonitor: GlobalCopyMonitor,
        translatorService: LLMTranslatorService,
        speechService: SpeechService,
        launchAtLogin: LaunchAtLoginService = LaunchAtLoginService(),
        screenCaptureService: ScreenCaptureService = ScreenCaptureService(),
        hotkeyService: GlobalHotkeyService = GlobalHotkeyService(),
        updateService: AppUpdateService = AppUpdateService(),
        onTriggerScreenshotOCR: @escaping () -> Void = {},
        uiState: SettingsUIState
    ) {
        self.settingsStore = settingsStore
        self.copyMonitor = copyMonitor
        self.translatorService = translatorService
        self.speechService = speechService
        self.launchAtLogin = launchAtLogin
        self.screenCaptureService = screenCaptureService
        self.hotkeyService = hotkeyService
        self.updateService = updateService
        self.onTriggerScreenshotOCR = onTriggerScreenshotOCR
        self.uiState = uiState
    }

    private var needsPermissionAttention: Bool {
        (settingsStore.settings.doubleCopyEnabled && !copyMonitor.isAccessibilityTrusted)
            || (settingsStore.settings.screenshotOCREnabled && !screenCaptureService.hasScreenRecordingPermission)
    }

    private var lang: ResolvedAppLanguage { settingsStore.resolvedLanguage }
    private var l10n: L10n { L10n(lang) }

    public var body: some View {
        HStack(spacing: 0) {
            sidebar
            detailPane
        }
        .frame(width: Self.windowSize.width, height: Self.windowSize.height)
        .background(StageBackdrop(hue: uiState.selectedPane.hue))
        .tint(FerryTheme.accent)
        .ferryLocalized(lang)
        .onAppear {
            copyMonitor.refreshPermissionStatus()
            screenCaptureService.refreshPermissionStatus()
            launchAtLogin.refreshStatus()
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
                Text(l10n.brandName)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
            }
            .padding(.leading, 8)
            .padding(.bottom, 14)

            ForEach(SettingsPane.allCases) { pane in
                SidebarItem(
                    pane: pane,
                    selected: uiState.selectedPane == pane,
                    alert: (pane == .shortcut && needsPermissionAttention)
                        || (pane == .general && updateService.state.isReadyToInstall)
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
        StageHero(
            title: pane.title(in: lang),
            tagline: pane.tagline(in: lang)
        ) {
            SettingsPaneBadge(pane: pane, size: 46, filled: true)
        }
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
                GlassLabel(l10n.providerConnectionLabel(provider))
                GlassCard {
                    GlassRow(title: "API Key") {
                        GlassField(placeholder: "sk-…", text: apiKeyBinding(for: provider), secure: true)
                            .frame(width: 320)
                    }

                    GlassRow(title: l10n.endpointURL) {
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
                                GlassIconButton(systemName: "arrow.uturn.backward", help: l10n.restoreDefaultURLHelp) {
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

                    GlassRow(title: l10n.model, caption: hasCustomModel ? l10n.overriddenByCustomModel : nil) {
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
                            .help(l10n.fetchModelsHelp)
                        }
                    }

                    GlassRow(title: l10n.customModel, divider: false) {
                        GlassField(
                            placeholder: l10n.customModelPlaceholder,
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
                        Text(uiState.isTestingConnection ? l10n.testingConnection : l10n.testConnection)
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
            return l10n.builtInModelListFooter
        }
        return l10n.availableModelsCount(profile.fetchedModels.count)
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
        let doubleCopyEnabled = settingsStore.settings.doubleCopyEnabled
        let screenshotEnabled = settingsStore.settings.screenshotOCREnabled
        let shortcut = settingsStore.settings.screenshotOCRShortcut
        let trusted = copyMonitor.isAccessibilityTrusted
        let screenGranted = screenCaptureService.hasScreenRecordingPermission

        return VStack(alignment: .leading, spacing: 22) {
            StageHero(
                title: SettingsPane.shortcut.title(in: lang),
                tagline: SettingsPane.shortcut.tagline(in: lang),
                icon: {
                    SettingsPaneBadge(pane: .shortcut, size: 46, filled: true)
                },
                accessory: {
                    DoubleCopyKeys()
                }
            )
            .background(WindowDragArea())

            VStack(alignment: .leading, spacing: 8) {
                GlassLabel(l10n.doubleCopySectionLabel)
                GlassCard {
                    GlassRow(title: l10n.doubleCopyToggle) {
                        GlassToggle(isOn: Binding(
                            get: { settingsStore.settings.doubleCopyEnabled },
                            set: { newValue in
                                withAnimation(FerryMotion.animation(FerryMotion.quick)) {
                                    settingsStore.settings.doubleCopyEnabled = newValue
                                }
                            }
                        ))
                    }
                    GlassRow(title: l10n.doubleCopyInterval, caption: l10n.doubleCopyIntervalCaption, divider: false) {
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
                        .disabled(!doubleCopyEnabled)
                        .opacity(doubleCopyEnabled ? 1 : 0.4)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                GlassLabel(l10n.screenshotOCRSectionLabel)
                GlassCard {
                    GlassRow(title: l10n.screenshotOCRToggle, caption: l10n.screenshotOCRToggleCaption) {
                        GlassToggle(isOn: Binding(
                            get: { settingsStore.settings.screenshotOCREnabled },
                            set: { newValue in
                                withAnimation(FerryMotion.animation(FerryMotion.quick)) {
                                    settingsStore.settings.screenshotOCREnabled = newValue
                                }
                            }
                        ))
                    }

                    GlassRow(title: l10n.screenshotOCRHotkeyRow, caption: l10n.screenshotOCRHotkeyCaption) {
                        HStack(spacing: 6) {
                            ShortcutRecorderButton(
                                shortcut: Binding(
                                    get: { settingsStore.settings.screenshotOCRShortcut },
                                    set: { settingsStore.settings.screenshotOCRShortcut = $0 }
                                ),
                                onRecordingChange: { recording in
                                    hotkeyService.setPaused(recording)
                                }
                            )
                            if shortcut != .defaultScreenshotOCR {
                                GlassIconButton(systemName: "arrow.uturn.backward", help: l10n.resetDefaultShortcutHelp) {
                                    settingsStore.settings.screenshotOCRShortcut = .defaultScreenshotOCR
                                }
                            }
                        }
                        .disabled(!screenshotEnabled)
                        .opacity(screenshotEnabled ? 1 : 0.4)
                    }

                    GlassRow(title: l10n.tryScreenshotOCR, divider: false) {
                        Button {
                            onTriggerScreenshotOCR()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "text.viewfinder")
                                    .font(.system(size: 11.5, weight: .semibold))
                                Text(l10n.statusScreenshotOCR)
                            }
                        }
                        .buttonStyle(GlassButtonStyle(kind: .glow, hue: .coral))
                    }

                    if hotkeyService.registrationFailed && screenshotEnabled {
                        Rectangle().fill(Stage.hairline).frame(height: 1)
                        StatusLine(text: l10n.shortcutConflictWarning, success: false)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                GlassLabel(l10n.systemPermissionsLabel)
                GlassCard {
                    HStack(spacing: 12) {
                        HueTile(
                            systemName: trusted ? "checkmark.shield.fill" : "exclamationmark.shield.fill",
                            hue: trusted ? .teal : .amber,
                            size: 32
                        )
                        .contentTransition(.symbolEffect(.replace))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(l10n.accessibilityTitle)
                                .font(.system(size: 13, weight: .medium))
                            Text(trusted ? l10n.accessibilityGrantedCaption : l10n.accessibilityDeniedCaption)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        StatusPill(
                            text: trusted ? l10n.grantedPill : l10n.notGrantedPill,
                            color: trusted ? Stage.ok : Stage.warn
                        )
                        GlassIconButton(systemName: "arrow.clockwise", help: l10n.recheckPermissionHelp) {
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
                                Button(l10n.openSystemSettings) {
                                    copyMonitor.openAccessibilitySettings()
                                }
                                .buttonStyle(GlassButtonStyle(kind: .glow, hue: .coral))
                                Button(l10n.requestAccess) {
                                    copyMonitor.requestAccessibilityPermission()
                                }
                                .buttonStyle(GlassButtonStyle())
                            }
                            Text(l10n.accessibilityTroubleshootTip)
                                .font(.system(size: 11))
                                .foregroundStyle(Stage.textTertiary)
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Rectangle().fill(Stage.hairline).frame(height: 1)

                    HStack(spacing: 12) {
                        HueTile(
                            systemName: screenGranted ? "checkmark.shield.fill" : "rectangle.dashed.badge.record",
                            hue: screenGranted ? .teal : .amber,
                            size: 32
                        )
                        .contentTransition(.symbolEffect(.replace))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(l10n.screenRecordingTitle)
                                .font(.system(size: 13, weight: .medium))
                            Text(screenGranted ? l10n.screenRecordingGrantedCaption : l10n.screenRecordingDeniedCaption)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        StatusPill(
                            text: screenGranted ? l10n.grantedPill : l10n.notGrantedPill,
                            color: screenGranted ? Stage.ok : Stage.warn
                        )
                        GlassIconButton(systemName: "arrow.clockwise", help: l10n.recheckPermissionHelp) {
                            withAnimation(FerryMotion.animation(FerryMotion.spring)) {
                                screenCaptureService.refreshPermissionStatus()
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)

                    if !screenGranted {
                        Rectangle().fill(Stage.hairline).frame(height: 1)
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 8) {
                                Button(l10n.openSystemSettings) {
                                    screenCaptureService.openScreenRecordingSettings()
                                }
                                .buttonStyle(GlassButtonStyle(kind: .glow, hue: .coral))
                                Button(l10n.requestAccess) {
                                    screenCaptureService.requestScreenRecordingPermission()
                                }
                                .buttonStyle(GlassButtonStyle())
                            }
                            Text(l10n.screenRecordingTroubleshootTip)
                                .font(.system(size: 11))
                                .foregroundStyle(Stage.textTertiary)
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                Text(l10n.clipboardPrivacyNote)
                    .font(.system(size: 11))
                    .foregroundStyle(Stage.textTertiary)
                    .padding(.horizontal, 4)
            }
            .animation(FerryMotion.animation(FerryMotion.spring), value: trusted)
            .animation(FerryMotion.animation(FerryMotion.spring), value: screenGranted)
        }
    }

    // MARK: - General

    private var generalPane: some View {
        VStack(alignment: .leading, spacing: 22) {
            hero(.general)

            GlassCard {
                GlassRow(title: l10n.appearance) {
                    GlassSegmented(
                        items: AppearanceMode.allCases,
                        selection: Binding(
                            get: { settingsStore.settings.appearance },
                            set: { newValue in
                                settingsStore.settings.appearance = newValue
                                FerryAppearance.apply(newValue)
                            }
                        ),
                        title: { $0.displayName(in: lang) },
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

                GlassRow(
                    title: l10n.interfaceLanguage,
                    caption: settingsStore.settings.language == .system ? l10n.systemLanguageCaption(lang) : nil
                ) {
                    GlassSegmented(
                        items: AppLanguage.allCases,
                        selection: Binding(
                            get: { settingsStore.settings.language },
                            set: { settingsStore.settings.language = $0 }
                        ),
                        title: { $0.displayName(in: lang) }
                    )
                    .frame(width: 300)
                }

                GlassRow(
                    title: l10n.launchAtLogin,
                    caption: launchAtLogin.requiresApproval
                        ? l10n.launchAtLoginNeedsApprovalCaption
                        : l10n.launchAtLoginCaption,
                    divider: false
                ) {
                    HStack(spacing: 8) {
                        if launchAtLogin.requiresApproval {
                            Button(l10n.openLoginItems) {
                                launchAtLogin.openLoginItemsSettings()
                            }
                            .buttonStyle(GlassButtonStyle(kind: .glass, height: 24))
                        }
                        GlassToggle(isOn: Binding(
                            get: { launchAtLogin.isEnabled },
                            set: { launchAtLogin.setEnabled($0) }
                        ))
                    }
                }

                if let error = launchAtLogin.lastErrorMessage {
                    Rectangle().fill(Stage.hairline).frame(height: 1)
                    StatusLine(text: error, success: false)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                GlassLabel(l10n.translationSectionLabel)
                GlassCard {
                    GlassRow(title: l10n.defaultTargetLanguage, caption: l10n.defaultTargetLanguageCaption) {
                        GlassPicker(
                            items: TargetLanguage.allCases,
                            selection: Binding(
                                get: { settingsStore.settings.defaultTargetLanguage },
                                set: { settingsStore.settings.defaultTargetLanguage = $0 }
                            ),
                            title: { $0.displayName(in: lang) }
                        )
                    }
                    GlassRow(title: l10n.wordLookup, caption: l10n.wordLookupCaption, divider: false) {
                        GlassToggle(isOn: Binding(
                            get: { settingsStore.settings.wordLookupEnabled },
                            set: { settingsStore.settings.wordLookupEnabled = $0 }
                        ))
                    }
                }
            }

            speechSection

            updatesSection

            VStack(alignment: .leading, spacing: 8) {
                GlassLabel(l10n.otherSectionLabel)
                GlassCard {
                    GlassRow(title: l10n.widgetAlwaysOnTop) {
                        GlassToggle(isOn: Binding(
                            get: { settingsStore.settings.desktopWidgetAlwaysOnTop },
                            set: { settingsStore.settings.desktopWidgetAlwaysOnTop = $0 }
                        ))
                    }
                    GlassRow(
                        title: l10n.translationHistory,
                        caption: l10n.translationHistoryCaption(settingsStore.recentRecords.count),
                        divider: false
                    ) {
                        Button(l10n.clear) {
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
        l10n.speechEngineLabel(engine)
    }

    private func engineCaption(_ engine: SpeechEngine) -> String {
        l10n.speechEngineCaption(engine)
    }

    private var rateRow: some View {
        GlassRow(title: l10n.speechRate) {
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

    private var updatesSection: some View {
        let autoCheck = settingsStore.settings.autoCheckForUpdates

        return VStack(alignment: .leading, spacing: 8) {
            GlassLabel(l10n.updatesSectionLabel)
            GlassCard {
                GlassRow(
                    title: l10n.currentVersionLabel(updateService.currentVersionString),
                    caption: updateStatusCaption
                ) {
                    updatePrimaryActionControl
                }

                if case .downloading(_, let progress) = updateService.state {
                    VStack(alignment: .leading, spacing: 6) {
                        ProgressView(value: progress)
                            .progressViewStyle(.linear)
                            .controlSize(.small)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 10)
                }

                if let release = updateService.state.release, !release.releaseNotes.isEmpty {
                    Rectangle().fill(Stage.hairline).frame(height: 1)
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(release.name)
                                .font(.system(size: 12, weight: .semibold))
                            Spacer()
                            Button(l10n.viewReleaseNotes) {
                                updateService.openReleasePage()
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(FerryTheme.accentText)

                            if !updateService.state.isBusy {
                                Button(l10n.skipThisVersion) {
                                    updateService.skipCurrentUpdate()
                                }
                                .buttonStyle(.plain)
                                .font(.system(size: 11))
                                .foregroundStyle(Stage.textSecondary)
                                .padding(.leading, 8)
                            }
                        }
                        Text(release.releaseNotes)
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                            .lineLimit(5)
                            .textSelection(.enabled)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                if case .failed(let errorMessage) = updateService.state {
                    Rectangle().fill(Stage.hairline).frame(height: 1)
                    StatusLine(text: errorMessage, success: false)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                GlassRow(title: l10n.autoCheckUpdates, caption: l10n.autoCheckUpdatesCaption) {
                    GlassToggle(isOn: Binding(
                        get: { settingsStore.settings.autoCheckForUpdates },
                        set: { settingsStore.settings.autoCheckForUpdates = $0 }
                    ))
                }

                GlassRow(
                    title: l10n.autoDownloadUpdates,
                    caption: l10n.autoDownloadUpdatesCaption,
                    divider: false
                ) {
                    GlassToggle(isOn: Binding(
                        get: { settingsStore.settings.autoDownloadUpdates },
                        set: { settingsStore.settings.autoDownloadUpdates = $0 }
                    ))
                    .disabled(!autoCheck)
                    .opacity(autoCheck ? 1 : 0.4)
                }
            }
        }
    }

    private var updateStatusCaption: String? {
        switch updateService.state {
        case .idle:
            return nil
        case .checking:
            return l10n.checkingForUpdates
        case .upToDate(let current):
            return l10n.upToDateMessage(current)
        case .available(let release):
            return l10n.updateAvailableTitle(release.version.description)
        case .downloading(let release, let progress):
            return l10n.downloadingUpdateProgress(release.version.description, percent: Int((progress * 100).rounded()))
        case .readyToInstall(let release, _):
            return l10n.updateReadyTitle(release.version.description)
        case .installing:
            return l10n.installingUpdate
        case .failed:
            return nil
        }
    }

    @ViewBuilder
    private var updatePrimaryActionControl: some View {
        switch updateService.state {
        case .checking:
            HStack(spacing: 6) {
                ProgressView().controlSize(.mini)
                Text(l10n.checkingForUpdates)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        case .available:
            Button(l10n.downloadUpdate) {
                updateService.downloadUpdate()
            }
            .buttonStyle(GlassButtonStyle(kind: .glow, hue: .teal))
        case .downloading(_, let progress):
            Text("\(Int((progress * 100).rounded()))%")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Stage.textSecondary)
        case .readyToInstall:
            Button(l10n.restartToUpdate) {
                updateService.installAndRelaunch()
            }
            .buttonStyle(GlassButtonStyle(kind: .glow, hue: .teal))
        case .installing:
            HStack(spacing: 6) {
                ProgressView().controlSize(.mini)
                Text(l10n.installingUpdate)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        case .idle, .upToDate, .failed:
            Button(l10n.checkForUpdates) {
                updateService.checkForUpdates(userInitiated: true)
            }
            .buttonStyle(GlassButtonStyle(kind: .glass))
        }
    }

    private var speechSection: some View {
        let speech = settingsStore.settings.speech

        return VStack(alignment: .leading, spacing: 8) {
            GlassLabel(l10n.speechSectionLabel)
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
                    GlassRow(title: l10n.englishAccent) {
                        GlassPicker(
                            items: EnglishAccent.allCases,
                            selection: Binding(
                                get: { settingsStore.settings.speech.englishAccent },
                                set: { settingsStore.settings.speech.englishAccent = $0 }
                            ),
                            title: { $0.displayName(in: lang) }
                        )
                    }
                    rateRow

                case .bailian:
                    GlassRow(title: l10n.voice) {
                        GlassPicker(
                            items: SpeechSettings.bailianVoices,
                            selection: Binding(
                                get: { settingsStore.settings.speech.bailianVoice },
                                set: { settingsStore.settings.speech.bailianVoice = $0 }
                            ),
                            title: { $0 }
                        )
                    }
                    GlassRow(title: l10n.ttsModel) {
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
                    GlassRow(title: l10n.voice) {
                        GlassPicker(
                            items: SpeechSettings.openAIVoices,
                            selection: Binding(
                                get: { settingsStore.settings.speech.openAIVoice },
                                set: { settingsStore.settings.speech.openAIVoice = $0 }
                            ),
                            title: { $0 }
                        )
                    }
                    GlassRow(title: l10n.ttsModel) {
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

                GlassRow(title: l10n.previewSpeech, divider: false) {
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
        .buttonStyle(GlassButtonStyle(kind: active ? .glow : .glass, hue: .azure))
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
                let l10n = L10n(settingsStore.resolvedLanguage)
                uiState.modelFetchMessage[provider] = models.isEmpty
                    ? (l10n.noChatModelsReturned, false)
                    : (l10n.availableModelsCount(models.count), true)
            } catch {
                let l10n = L10n(settingsStore.resolvedLanguage)
                uiState.modelFetchMessage[provider] = (l10n.fetchModelsFailed(error.localizedDescription), false)
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
    @Environment(\.appLanguage) private var appLanguage

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                SettingsPaneBadge(pane: pane, size: 26, filled: selected)
                Text(pane.title(in: appLanguage))
                    .font(.system(size: 13, weight: selected ? .semibold : .medium))
                    .foregroundStyle(selected ? Color.primary : Stage.textSecondary)
                Spacer(minLength: 0)
                if alert {
                    Circle()
                        .fill(Stage.warn)
                        .frame(width: 7, height: 7)
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 36)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(selected ? Stage.selectedFill : (hovering ? Stage.controlFill : .clear))
                    .shadow(color: selected ? Stage.cardShadow : .clear, radius: 4, y: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
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
    @Environment(\.appLanguage) private var appLanguage
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let l10n = L10n(appLanguage)
        let dark = colorScheme == .dark
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    ProviderBrandBadge(kind: kind, size: 36)
                    Spacer()
                    if selected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(.white, FerryTheme.accent)
                            .transition(.scale.combined(with: .opacity))
                    } else {
                        Circle()
                            .fill(configured ? Stage.ok : Stage.controlHover)
                            .frame(width: 7, height: 7)
                            .padding(4)
                            .help(configured ? l10n.keyConfigured : l10n.keyMissing)
                    }
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(kind.shortName(in: appLanguage))
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(configured ? model : l10n.keyMissing)
                        .font(.system(size: 10.5, design: configured ? .monospaced : .default))
                        .foregroundStyle(configured ? Stage.textSecondary : Stage.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .padding(13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(selected ? Stage.selectedFill : (hovering ? Stage.glassFillHover : Stage.glassFill))
                    if selected {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(FerryTheme.accent.opacity(dark ? 0.12 : 0.045))
                    }
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(
                        selected
                            ? AnyShapeStyle(FerryTheme.accent)
                            : AnyShapeStyle(Stage.glassStroke),
                        lineWidth: selected ? 1.5 : 1
                    )
            )
            .shadow(
                color: selected
                    ? (dark ? FerryTheme.accent.opacity(0.18) : Color.black.opacity(0.06))
                    : Stage.cardShadow,
                radius: selected ? 10 : 6,
                y: selected ? 3 : 2
            )
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

// MARK: - Shortcut Recorder

@MainActor
private final class LocalKeyMonitorBox {
    nonisolated(unsafe) private var monitor: Any?

    func install(_ handler: @escaping (NSEvent) -> NSEvent?) {
        remove()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: handler)
    }

    func remove() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }

    deinit {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}

/// Click-to-record global hotkey button. Captures one key-down with a primary modifier (⌘/⌥/⌃);
/// pressing Esc cancels recording without changing the stored shortcut.
private struct ShortcutRecorderButton: View {
    @Binding var shortcut: HotkeyShortcut
    var onRecordingChange: (Bool) -> Void = { _ in }

    @ViewState private var isRecording = false
    @ViewState private var hovering = false
    @ViewState private var monitorBox = LocalKeyMonitorBox()
    @Environment(\.appLanguage) private var appLanguage

    var body: some View {
        let l10n = L10n(appLanguage)
        Button {
            if isRecording {
                stopRecording()
            } else {
                startRecording()
            }
        } label: {
            HStack(spacing: 4) {
                if isRecording {
                    Circle()
                        .fill(Stage.warn)
                        .frame(width: 6, height: 6)
                    Text(l10n.shortcutRecordingPrompt)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Stage.warn)
                } else {
                    ForEach(Array(shortcut.displayTokens.enumerated()), id: \.offset) { _, token in
                        Text(token)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Stage.selectedFill, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .strokeBorder(Stage.selectedStroke, lineWidth: 0.75)
                            )
                    }
                }
            }
            .padding(.horizontal, 10)
            .frame(minWidth: 112, minHeight: 28)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isRecording ? Stage.warn.opacity(0.12) : (hovering ? Stage.controlHover : Stage.controlFill))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(isRecording ? Stage.warn : Stage.controlStroke, lineWidth: isRecording ? 1.25 : 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .onDisappear { stopRecording() }
        .animation(FerryMotion.animation(FerryMotion.quick), value: isRecording)
        .animation(FerryMotion.animation(FerryMotion.quick), value: hovering)
    }

    private func startRecording() {
        stopRecording()
        isRecording = true
        onRecordingChange(true)

        monitorBox.install { event in
            // Escape cancels recording
            if event.keyCode == 53 {
                stopRecording()
                return nil
            }

            let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
            var modifiers: HotkeyModifiers = []
            if flags.contains(.command) { modifiers.insert(.command) }
            if flags.contains(.option)  { modifiers.insert(.option) }
            if flags.contains(.control) { modifiers.insert(.control) }
            if flags.contains(.shift)   { modifiers.insert(.shift) }

            let candidate = HotkeyShortcut(keyCode: UInt32(event.keyCode), modifiers: modifiers)
            if candidate.isValid {
                shortcut = candidate
                stopRecording()
                return nil
            }
            NSSound.beep()
            return nil
        }
    }

    private func stopRecording() {
        monitorBox.remove()
        if isRecording {
            isRecording = false
            onRecordingChange(false)
        }
    }
}

// MARK: - Searchable Model Picker

/// Shows the selected model; clicking opens a searchable popover (providers can return 100+ models).
struct ModelPickerButton: View {
    let models: [String]
    @Binding var selection: String
    @ViewState private var showing = false
    @ViewState private var query = ""
    @Environment(\.appLanguage) private var appLanguage

    private var filtered: [String] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return q.isEmpty ? models : models.filter { $0.lowercased().contains(q) }
    }

    var body: some View {
        let l10n = L10n(appLanguage)
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
                GlassField(placeholder: l10n.searchModelsPlaceholder(models.count), text: $query, monospaced: false)

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
                                Text(l10n.noMatchingModels)
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
            .ferryLocalized(appLanguage)
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
