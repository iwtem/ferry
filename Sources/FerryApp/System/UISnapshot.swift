#if DEBUG
import AppKit
import FerryCore
import SwiftUI

/// Debug-only: renders the main UI surfaces to PNG files without showing windows.
/// Uses a throwaway settings directory filled with sample data, never the user's real settings.
///
///     swift run Ferry --ui-snapshot /path/to/output
@MainActor
enum UISnapshot {
    static func runIfRequested() {
        let args = CommandLine.arguments
        guard let flagIndex = args.firstIndex(of: "--ui-snapshot"), args.count > flagIndex + 1 else { return }
        let outputDir = URL(fileURLWithPath: args[flagIndex + 1], isDirectory: true)
        try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)

        let sandbox = FileManager.default.temporaryDirectory.appendingPathComponent("ferry-ui-snapshot-\(UUID().uuidString)")
        let store = SettingsStore(directory: sandbox)
        if let langFlag = args.firstIndex(of: "--lang"), args.count > langFlag + 1 {
            switch args[langFlag + 1].lowercased() {
            case "en", "english":
                store.settings.language = .en
            case "zh", "zh-hans", "zh-cn":
                store.settings.language = .zhHans
            default:
                store.settings.language = .system
            }
        }
        store.setAPIKey("sk-sample-key-for-snapshot", for: .deepseek)
        var profile = store.profile(for: .deepseek)
        profile.fetchedModels = ["deepseek-chat", "deepseek-reasoner"]
        store.updateProfile(profile, for: .deepseek)
        let service = LLMTranslatorService()
        let copyMonitor = GlobalCopyMonitor(settingsStore: store)
        let speechService = SpeechService(settingsStore: store)

        let sampleSource = "Translation is the communication of the meaning of a source-language text by means of an equivalent target-language text."
        let sampleResult = "翻译是通过意义相当的目标语言文本，传达源语言文本含义的过程。"
        for (i, s) in [("The quick brown fox jumps over the lazy dog.", "敏捷的棕色狐狸跳过了那只懒狗。"),
                       ("渡口的船夫每天都在等待新的旅客。", "The ferryman at the crossing waits for new travelers every day.")].enumerated() {
            store.recordTranslation(TranslationRecord(
                sourceText: s.0, translatedText: s.1,
                targetLanguage: .auto, resolvedLanguage: i == 0 ? .zhCN : .en, provider: .deepseek, model: "deepseek-chat"
            ))
            let key = TranslationCacheKey(
                sourceText: s.0,
                resolvedTarget: i == 0 ? .zhCN : .en,
                mode: .translate,
                provider: .deepseek,
                model: "deepseek-chat",
                endpoint: ProviderKind.deepseek.defaultBaseURL,
                wordLookup: false
            )
            store.cacheTranslation(s.1, for: key)
        }

        func session(cached: Bool = false, comparing: Bool = false) -> TranslatorSession {
            let session = TranslatorSession(settingsStore: store, translatorService: service)
            session.sourceText = sampleSource
            session.translatedText = sampleResult
            session.resolvedLanguage = .zhCN
            session.isFromCache = cached
            session.activeResultModel = ModelChoice(provider: .deepseek, model: "deepseek-chat")
            if comparing {
                session.isComparing = true
                session.comparisonModel = ModelChoice(provider: .deepseek, model: "deepseek-reasoner")
                session.comparisonText = "翻译是指通过语义对等的目标语言文本，准确传达源语言文本含义的过程。"
                session.isComparisonFromCache = false
            }
            return session
        }

        let mainState = MainWindowUIState()
        mainState.showHistory = true

        for (appearanceName, appearance) in [("light", NSAppearance.Name.aqua), ("dark", NSAppearance.Name.darkAqua)] {
            render(
                MainWindowView(session: session(cached: true), settingsStore: store, copyMonitor: copyMonitor, speechService: speechService, uiState: mainState,
                               onToggleDesktopWidget: {}, onOpenSettings: {}),
                size: NSSize(width: 980, height: 560), appearance: appearance,
                to: outputDir.appendingPathComponent("main-\(appearanceName).png")
            )
            let compareMainState = MainWindowUIState()
            compareMainState.showHistory = false
            render(
                MainWindowView(session: session(cached: true, comparing: true), settingsStore: store, copyMonitor: copyMonitor, speechService: speechService, uiState: compareMainState,
                               onToggleDesktopWidget: {}, onOpenSettings: {}),
                size: NSSize(width: 940, height: 600), appearance: appearance,
                to: outputDir.appendingPathComponent("main-compare-\(appearanceName).png")
            )
            render(
                MenuBarPopoverView(session: session(cached: true), settingsStore: store, speechService: speechService,
                                   onOpenMainWindow: {}, onToggleDesktopWidget: {}, onOpenSettings: {}, onQuit: {}),
                size: nil, appearance: appearance,
                to: outputDir.appendingPathComponent("popover-\(appearanceName).png")
            )
            render(
                MenuBarPopoverView(session: session(cached: true, comparing: true), settingsStore: store, speechService: speechService,
                                   onOpenMainWindow: {}, onToggleDesktopWidget: {}, onOpenSettings: {}, onQuit: {}),
                size: nil, appearance: appearance,
                to: outputDir.appendingPathComponent("popover-compare-\(appearanceName).png")
            )
            render(
                MenuBarPopoverView(session: TranslatorSession(settingsStore: store, translatorService: service), settingsStore: store,
                                   speechService: speechService,
                                   onOpenMainWindow: {}, onToggleDesktopWidget: {}, onOpenSettings: {}, onQuit: {}),
                size: nil, appearance: appearance,
                to: outputDir.appendingPathComponent("popover-empty-\(appearanceName).png")
            )
            let popupState = QuickPopupUIState()
            popupState.sourceAppName = "Safari"
            render(
                QuickPopupView(session: session(cached: true), settingsStore: store, speechService: speechService, uiState: popupState,
                               onTogglePin: { _ in }, onOpenInMainWindow: {}, onOpenSettings: {},
                               onReplaceInSourceApp: {}, onClose: {}),
                size: nil, appearance: appearance,
                to: outputDir.appendingPathComponent("popup-\(appearanceName).png")
            )
            render(
                QuickPopupView(session: session(cached: true, comparing: true), settingsStore: store, speechService: speechService, uiState: popupState,
                               onTogglePin: { _ in }, onOpenInMainWindow: {}, onOpenSettings: {},
                               onReplaceInSourceApp: {}, onClose: {}),
                size: nil, appearance: appearance,
                to: outputDir.appendingPathComponent("popup-compare-\(appearanceName).png")
            )
            render(
                DesktopMiniWidgetView(session: session(cached: true), settingsStore: store, speechService: speechService,
                                      onToggleAlwaysOnTop: { _ in }, onOpenInMainWindow: {}, onOpenSettings: {}, onClose: {}),
                size: nil, appearance: appearance,
                to: outputDir.appendingPathComponent("widget-\(appearanceName).png")
            )
            for pane in SettingsPane.allCases {
                let state = SettingsUIState(initialProvider: .deepseek)
                state.selectedPane = pane
                render(
                    SettingsView(settingsStore: store, copyMonitor: copyMonitor, translatorService: service, speechService: speechService, uiState: state),
                    size: nil, appearance: appearance,
                    to: outputDir.appendingPathComponent("settings-\(pane.rawValue)-\(appearanceName).png")
                )
            }
        }

        try? FileManager.default.removeItem(at: sandbox)
        print("UI snapshots written to \(outputDir.path)")
        exit(0)
    }

    private static func render<V: View>(_ view: V, size: NSSize?, appearance: NSAppearance.Name, to url: URL) {
        let hosting = NSHostingView(rootView: view)
        let fitting = size ?? hosting.fittingSize
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: fitting),
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        window.appearance = NSAppearance(named: appearance)
        window.backgroundColor = .windowBackgroundColor
        window.contentView = hosting
        hosting.frame = NSRect(origin: .zero, size: fitting)
        hosting.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.6))
        hosting.layoutSubtreeIfNeeded()

        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}
#endif
