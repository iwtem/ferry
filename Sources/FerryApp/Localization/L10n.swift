import FerryCore
import SwiftUI

private struct AppLanguageEnvironmentKey: EnvironmentKey {
    static let defaultValue: ResolvedAppLanguage = .en
}

public extension EnvironmentValues {
    var appLanguage: ResolvedAppLanguage {
        get { self[AppLanguageEnvironmentKey.self] }
        set { self[AppLanguageEnvironmentKey.self] = newValue }
    }
}

extension View {
    func ferryLocalized(_ language: ResolvedAppLanguage) -> some View {
        self
            .environment(\.appLanguage, language)
            .environment(\.locale, language.locale)
    }
}

/// Strongly-typed UI strings for Ferry in Simplified Chinese and English.
struct L10n: Sendable {
    let language: ResolvedAppLanguage

    init(_ language: ResolvedAppLanguage = FerryLocalization.resolved) {
        self.language = language
    }

    private func t(zh: String, en: String) -> String {
        switch language {
        case .zhHans: return zh
        case .en: return en
        }
    }

    // MARK: - Brand & Windows

    var brandName: String { t(zh: "渡 Ferry", en: "Ferry") }
    var settingsWindowTitle: String { t(zh: "渡 Ferry 设置", en: "Ferry Settings") }
    var miniWidgetTitle: String { t(zh: "渡 Ferry 小窗", en: "Ferry Mini") }
    var statusItemTooltip: String {
        t(zh: "渡 Ferry（左键快译，右键菜单）", en: "Ferry (Left-click: Quick Translate, Right-click: Menu)")
    }
    func statusItemUpdateTooltip(_ version: String) -> String {
        t(zh: "渡 Ferry（新版本 v\(version) 已就绪，点击更新）", en: "Ferry (v\(version) ready to install)")
    }

    // MARK: - Menus (AppKit)

    var menuSettings: String { t(zh: "设置…", en: "Settings…") }
    var menuQuitApp: String { t(zh: "退出 渡 Ferry", en: "Quit Ferry") }
    var menuEdit: String { t(zh: "编辑", en: "Edit") }
    var menuUndo: String { t(zh: "撤销", en: "Undo") }
    var menuRedo: String { t(zh: "重做", en: "Redo") }
    var menuCut: String { t(zh: "剪切", en: "Cut") }
    var menuCopy: String { t(zh: "拷贝", en: "Copy") }
    var menuPaste: String { t(zh: "粘贴", en: "Paste") }
    var menuSelectAll: String { t(zh: "全选", en: "Select All") }
    var menuWindow: String { t(zh: "窗口", en: "Window") }
    var menuCloseWindow: String { t(zh: "关闭窗口", en: "Close Window") }

    var statusQuickTranslate: String { t(zh: "菜单栏快译", en: "Quick Translate") }
    var statusScreenshotOCR: String { t(zh: "截图翻译", en: "Screenshot OCR") }
    var statusOpenMainWindow: String { t(zh: "打开大窗口", en: "Open Main Window") }
    var statusHideMiniWidget: String { t(zh: "隐藏桌面悬浮小窗", en: "Hide Mini Widget") }
    var statusShowMiniWidget: String { t(zh: "打开桌面悬浮小窗", en: "Show Mini Widget") }
    var statusCheckForUpdates: String { t(zh: "检查更新…", en: "Check for Updates…") }
    func statusRestartToUpdate(_ version: String) -> String {
        t(zh: "重启并更新到 v\(version)", en: "Restart to Update (v\(version))")
    }

    func statusScreenshotOCRWithShortcut(_ shortcut: String) -> String {
        t(zh: "截图翻译 (\(shortcut))", en: "Screenshot OCR (\(shortcut))")
    }

    // MARK: - Common Actions & Controls

    var translate: String { t(zh: "翻译", en: "Translate") }
    var translateShortcutHelp: String { t(zh: "翻译 (⌘⏎)", en: "Translate (⌘⏎)") }
    func runActionLabel(for mode: TranslationMode) -> String {
        switch mode {
        case .translate: return t(zh: "翻译", en: "Translate")
        case .polish: return t(zh: "润色", en: "Polish")
        case .grammar: return t(zh: "纠错", en: "Fix")
        case .concise: return t(zh: "精简", en: "Rewrite")
        case .academic: return t(zh: "改写", en: "Rewrite")
        }
    }
    func runActionShortcutHelp(for mode: TranslationMode) -> String {
        "\(runActionLabel(for: mode)) (⌘⏎)"
    }
    var keepSourceLanguageLabel: String { t(zh: "保持原语言", en: "Same language") }
    var replaceSelectionButton: String { t(zh: "替换原文", en: "Replace") }
    var replaceSelectionTooltip: String {
        t(zh: "一键替换回原输入框 (⌘⏎)，并还原剪贴板", en: "Replace selection in original app (⌘⏎) & restore clipboard")
    }
    func replaceInAppTooltip(_ appName: String) -> String {
        t(zh: "一键替换回「\(appName)」(⌘⏎)", en: "Replace selection in \(appName) (⌘⏎)")
    }
    var openAccessibilitySettings: String { t(zh: "打开辅助功能设置", en: "Open Accessibility Settings") }
    var modePickerTooltip: String { t(zh: "切换翻译 / 写作润色模式", en: "Switch translation or writing mode") }
    var stop: String { t(zh: "停止", en: "Stop") }
    var clear: String { t(zh: "清空", en: "Clear") }
    var copy: String { t(zh: "复制", en: "Copy") }
    var copied: String { t(zh: "已复制", en: "Copied") }
    var settings: String { t(zh: "设置", en: "Settings") }
    var settingsShortcutHelp: String { t(zh: "设置 (⌘,)", en: "Settings (⌘,)") }
    var quitFerry: String { t(zh: "退出 Ferry", en: "Quit Ferry") }
    var openSettings: String { t(zh: "去设置", en: "Open Settings") }
    var openSettingsForAPIKey: String { t(zh: "打开设置配置 API Key", en: "Open Settings for API Key") }
    var show: String { t(zh: "显示", en: "Show") }
    var hide: String { t(zh: "隐藏", en: "Hide") }
    var toggleOn: String { t(zh: "开", en: "On") }
    var toggleOff: String { t(zh: "关", en: "Off") }

    // MARK: - Speech

    var speak: String { t(zh: "朗读", en: "Speak") }
    var speakSource: String { t(zh: "朗读原文", en: "Speak Source") }
    var speakTranslation: String { t(zh: "朗读译文", en: "Speak Translation") }
    var stopSpeaking: String { t(zh: "停止朗读", en: "Stop Speaking") }
    var synthesizingSpeech: String { t(zh: "正在合成语音…", en: "Synthesizing speech…") }
    var audioPlaybackFailed: String {
        t(zh: "音频播放器无法播放返回的音频格式。", en: "Unable to play the returned audio format.")
    }
    var audioDecodeFailed: String { t(zh: "音频解码失败", en: "Audio decoding failed.") }

    // MARK: - Translation Status & Placeholders

    var translatingEllipsis: String { t(zh: "翻译中…", en: "Translating…") }
    var translatingLongEllipsis: String { t(zh: "正在翻译…", en: "Translating…") }
    var recognizingOCREllipsis: String { t(zh: "正在识别截图文字…", en: "Recognizing text from screenshot…") }
    var screenshotOCRTooltip: String { t(zh: "截图 OCR 翻译", en: "Screenshot OCR Translate") }
    func screenshotOCRShortcutTooltip(_ shortcut: String) -> String {
        t(zh: "截图 OCR 翻译 (\(shortcut))", en: "Screenshot OCR (\(shortcut))")
    }
    var openScreenRecordingSettings: String { t(zh: "打开屏幕录制设置", en: "Open Screen Recording Settings") }
    var pasteAndTranslateTooltip: String { t(zh: "粘贴文字或截图并翻译", en: "Paste Text or Screenshot & Translate") }
    var generating: String { t(zh: "生成中", en: "Generating") }
    var translationPlaceholder: String { t(zh: "译文", en: "Translation") }
    var missingAPIKeyTitle: String { t(zh: "还没填 API Key", en: "API Key Required") }

    func providerTranslating(_ provider: ProviderKind) -> String {
        let name = provider.shortName(in: language)
        return t(zh: "\(name) 正在翻译…", en: "\(name) is translating…")
    }

    func translatedTo(_ target: TargetLanguage) -> String {
        let name = target.shortName(in: language)
        return t(zh: "译为\(name)", en: "→ \(name)")
    }

    func characterCount(_ count: Int) -> String {
        t(zh: "\(count) 字", en: count == 1 ? "1 char" : "\(count) chars")
    }

    // MARK: - Main Window

    var historyTooltip: String { t(zh: "翻译记录", en: "History") }
    var miniWidgetTooltip: String { t(zh: "桌面小窗", en: "Mini Widget") }
    var autoDetectLanguage: String { t(zh: "自动检测语言", en: "Auto-detect") }

    func detectedSourceLanguage(_ name: String) -> String {
        t(zh: "\(name)（自动检测）", en: "\(name) (Detected)")
    }

    var swapMainTooltip: String { t(zh: "把译文放回左侧，反向翻译", en: "Swap translation into source") }
    var mainInputPlaceholder: String { t(zh: "输入或粘贴文本，⌘⏎ 翻译", en: "Type or paste text, ⌘⏎ to translate") }
    var permissionNoticeText: String {
        t(zh: "划词翻译需要辅助功能权限", en: "Double ⌘C translation requires Accessibility permission")
    }
    var permissionNoticeAction: String { t(zh: "去开启", en: "Enable") }
    var historyHeader: String { t(zh: "记录", en: "HISTORY") }
    var historyEmpty: String { t(zh: "还没有记录", en: "No history yet") }
    var modelSettingsItem: String { t(zh: "模型设置…", en: "Model Settings…") }
    var switchProviderHelp: String { t(zh: "切换模型服务商", en: "Switch Model Provider") }
    var missingProviderKeyHelp: String {
        t(zh: "当前服务商还没有配置 API Key", en: "No API Key configured for the current provider")
    }

    // MARK: - Menu Bar Popover

    var openInMainWindowTooltip: String { t(zh: "在大窗口中打开", en: "Open in Main Window") }
    var popoverInputPlaceholder: String { t(zh: "输入文本，⏎ 翻译", en: "Type text, ⏎ to translate") }
    var shiftReturnHint: String { t(zh: "⇧⏎ 换行", en: "⇧⏎ New line") }
    var swapPopoverTooltip: String { t(zh: "把译文放回输入框，反向翻译", en: "Swap translation into input") }

    // MARK: - Quick Popup (Double ⌘C)

    var unpinTooltip: String { t(zh: "取消固定", en: "Unpin") }
    var pinPopupTooltip: String { t(zh: "钉住悬浮窗", en: "Pin Window") }
    var closeEscTooltip: String { t(zh: "关闭 (Esc)", en: "Close (Esc)") }
    var dragToMoveTooltip: String { t(zh: "拖动空白处可移动窗口", en: "Drag empty area to move") }
    var retranslateTooltip: String { t(zh: "重新翻译", en: "Retranslate") }
    var retranslateBypassCacheTooltip: String { t(zh: "跳过缓存，重新调用模型翻译", en: "Retranslate (bypass cache)") }
    var cachedResultBadge: String { t(zh: "已缓存", en: "Cached") }
    var cachedResultTooltip: String {
        t(zh: "命中本地 LRU 缓存，秒出结果且不消耗 Token", en: "Served instantly from local LRU cache (0 tokens used)")
    }

    // MARK: - Quick Model Switch & Dual-Model Compare

    var switchModelOnceTooltip: String {
        t(zh: "单次切换模型重译（不改默认设置）", en: "Retranslate once with another model")
    }
    var switchModelOnceHeader: String {
        t(zh: "单次切模型重译", en: "Retranslate Once With")
    }
    func retranslateWithModel(_ model: String) -> String {
        t(zh: "用 \(model) 重译", en: "Retranslate with \(model)")
    }
    var restoreDefaultModel: String {
        t(zh: "恢复默认模型", en: "Back to Default Model")
    }
    var compareModelsTooltip: String {
        t(zh: "双模型对比翻译", en: "Compare with a second model")
    }
    var closeCompareTooltip: String {
        t(zh: "关闭双模型对比", en: "Close model comparison")
    }
    func compareWithModelMenu(_ model: String) -> String {
        t(zh: "与 \(model) 双模型对比", en: "Compare with \(model)")
    }
    var compareMenuAction: String {
        t(zh: "双模型对比", en: "Compare Side-by-Side")
    }
    var compareNoAlternativeTooltip: String {
        t(zh: "请先在「设置 → 模型」中配置更多模型或服务商", en: "Configure another model or provider in Settings → Models")
    }
    var switchCompareModelTooltip: String {
        t(zh: "切换对比模型", en: "Switch comparison model")
    }
    var adoptComparisonButton: String {
        t(zh: "采用", en: "Use")
    }
    var adoptComparisonTooltip: String {
        t(zh: "采用此模型的译文作为主结果", en: "Use this model's result as primary")
    }
    var secondaryModelSectionLabel: String {
        t(zh: "对比与强模型重译", en: "COMPARE & STRONG MODEL")
    }
    var secondaryModelRowTitle: String {
        t(zh: "备选强模型", en: "Secondary Model")
    }
    var secondaryModelRowCaption: String {
        t(zh: "一键「双模型对比」或「强模型重译」时默认使用的模型", en: "Default second model for one-click comparison & retranslation")
    }
    var secondaryModelAuto: String {
        t(zh: "自动选择", en: "Auto")
    }
    func secondaryModelAutoCaption(_ suggested: String) -> String {
        t(zh: "自动：当前推荐 \(suggested)", en: "Auto: currently \(suggested)")
    }

    // MARK: - Desktop Mini Widget

    var widgetPinnedTooltip: String { t(zh: "当前置顶，点击改为贴近桌面", en: "Pinned on top — click to unpin") }
    var widgetUnpinnedTooltip: String { t(zh: "点击置顶浮窗", en: "Keep on top") }
    var expandMainWindowTooltip: String { t(zh: "展开大窗口", en: "Open in Main Window") }
    var hideMiniWidgetTooltip: String { t(zh: "隐藏桌面小窗", en: "Hide Mini Widget") }
    var widgetInputPlaceholder: String {
        t(zh: "输入内容按 Enter 快速翻译…", en: "Type and press Enter to translate…")
    }
    var widgetEmptyOutput: String { t(zh: "译文将实时显示在这里", en: "Translation appears here") }

    // MARK: - Settings Panes

    func settingsPaneTitle(_ pane: SettingsPane) -> String {
        switch pane {
        case .models: return t(zh: "模型", en: "Models")
        case .shortcut: return t(zh: "快捷键", en: "Shortcuts")
        case .general: return t(zh: "通用", en: "General")
        }
    }

    func settingsPaneTagline(_ pane: SettingsPane) -> String {
        switch pane {
        case .models: return t(zh: "选一个服务商，填好 Key 就能翻译", en: "Pick a provider and add your API key to start")
        case .shortcut: return t(zh: "双击 ⌘C 划词，或快捷键截图 OCR 翻译", en: "Double ⌘C selection or screenshot OCR translation")
        case .general: return t(zh: "外观、语言、朗读与数据", en: "Appearance, language, speech & data")
        }
    }

    // MARK: - Settings: Models

    func providerConnectionLabel(_ provider: ProviderKind) -> String {
        let name = provider.shortName(in: language)
        return t(zh: "\(name) 连接", en: "\(name.uppercased()) CONNECTION")
    }

    var endpointURL: String { t(zh: "接口地址", en: "Endpoint URL") }
    var restoreDefaultURLHelp: String { t(zh: "恢复默认地址", en: "Restore Default URL") }
    var model: String { t(zh: "模型", en: "Model") }
    var overriddenByCustomModel: String { t(zh: "已被自定义模型覆盖", en: "Overridden by custom model") }
    var fetchModelsHelp: String { t(zh: "从服务商拉取模型列表", en: "Fetch model list from provider") }
    var customModel: String { t(zh: "自定义模型", en: "Custom Model") }
    var customModelPlaceholder: String { t(zh: "可选，填写模型 ID", en: "Optional model ID") }
    var builtInModelListFooter: String {
        t(zh: "内置推荐列表 · 填好 Key 后点 ↻ 拉取全部模型", en: "Built-in list · Enter key and click ↻ to fetch all models")
    }

    func availableModelsCount(_ count: Int) -> String {
        t(zh: "\(count) 个可用模型", en: count == 1 ? "1 model available" : "\(count) models available")
    }

    var noChatModelsReturned: String {
        t(zh: "服务商没有返回对话模型，继续用内置列表", en: "No chat models returned; keeping built-in list")
    }

    func fetchModelsFailed(_ error: String) -> String {
        t(zh: "拉取失败：\(error)", en: "Fetch failed: \(error)")
    }

    var testingConnection: String { t(zh: "测试中", en: "Testing…") }
    var testConnection: String { t(zh: "测试连接", en: "Test Connection") }
    var keyConfigured: String { t(zh: "已填 Key", en: "Key configured") }
    var keyMissing: String { t(zh: "未填 Key", en: "No key") }

    func searchModelsPlaceholder(_ count: Int) -> String {
        t(zh: "搜索 \(count) 个模型", en: "Search \(count) models")
    }

    var noMatchingModels: String {
        t(zh: "没有匹配的模型，可以填到「自定义模型」", en: "No matching models. Enter an ID in Custom Model.")
    }

    // MARK: - Settings: Shortcut

    var doubleCopySectionLabel: String { t(zh: "划词翻译", en: "SELECTION TRANSLATION") }
    var doubleCopyToggle: String { t(zh: "双击 ⌘C 翻译", en: "Double ⌘C to Translate") }
    var doubleCopyInterval: String { t(zh: "按键间隔", en: "Double-Press Interval") }
    var doubleCopyIntervalCaption: String { t(zh: "按得慢就调大一点", en: "Increase if you press slowly") }

    var selectionReplaceSectionLabel: String { t(zh: "划词润色与原地替换", en: "REWRITE & REPLACE IN PLACE") }
    var selectionShortcutToggle: String { t(zh: "选区翻译/润色快捷键", en: "Selection Translate / Polish Shortcut") }
    var selectionShortcutToggleCaption: String {
        t(zh: "在任意输入框选中文字按快捷键，不污染剪贴板并支持一键替换回原文", en: "Capture selected text without overwriting clipboard, then replace in place")
    }
    var resetDefaultSelectionShortcutHelp: String { t(zh: "恢复默认 (⌥⇧R)", en: "Reset to Default (⌥⇧R)") }

    var screenshotOCRSectionLabel: String { t(zh: "截图 OCR 翻译", en: "SCREENSHOT OCR") }
    var screenshotOCRToggle: String { t(zh: "截图翻译快捷键", en: "Screenshot OCR Shortcut") }
    var screenshotOCRToggleCaption: String {
        t(zh: "使用 macOS 原生 Vision 离线识别屏幕文字，零额外费用", en: "Offline Apple Vision OCR for images, PDFs & unselectable text")
    }
    var screenshotOCRHotkeyRow: String { t(zh: "全局快捷键", en: "Global Shortcut") }
    var screenshotOCRHotkeyCaption: String {
        t(zh: "点击按钮后按下组合键（需含 ⌘ / ⌥ / ⌃），按 Esc 取消", en: "Click and press a key combo with ⌘, ⌥ or ⌃ (Esc to cancel)")
    }
    var shortcutRecordingPrompt: String { t(zh: "请按下快捷键…", en: "Press shortcut…") }
    var resetDefaultShortcutHelp: String { t(zh: "恢复默认 (⌥⇧S)", en: "Reset to Default (⌥⇧S)") }
    var tryScreenshotOCR: String { t(zh: "立即截图测试", en: "Try Screenshot OCR") }
    var shortcutConflictWarning: String {
        t(zh: "该快捷键可能已被其他应用占用，请尝试更换组合键。", en: "Shortcut may be in use by another app. Try another key combination.")
    }

    var systemPermissionsLabel: String { t(zh: "系统权限", en: "PERMISSIONS") }
    var accessibilityTitle: String { t(zh: "辅助功能", en: "Accessibility") }
    var accessibilityGrantedCaption: String {
        t(zh: "可以在任意应用里划词", en: "Ready to capture double ⌘C in any app")
    }
    var accessibilityDeniedCaption: String {
        t(zh: "授权后才能识别双击 ⌘C", en: "Grant access to detect double ⌘C globally")
    }
    var screenRecordingTitle: String { t(zh: "屏幕录制", en: "Screen Recording") }
    var screenRecordingGrantedCaption: String {
        t(zh: "可以框选屏幕任意区域并识别文字", en: "Ready to capture and recognize text from any screen region")
    }
    var screenRecordingDeniedCaption: String {
        t(zh: "用于截取屏幕窗口内容进行本地 OCR 识别", en: "Required to capture app windows for on-device Vision OCR")
    }
    var screenRecordingTroubleshootTip: String {
        t(
            zh: "开启「屏幕录制」权限后，如果截图仍看不到窗口内容，请退出并重新打开 Ferry。",
            en: "After enabling Screen Recording, quit and reopen Ferry if app windows still don't appear in captures."
        )
    }
    var grantedPill: String { t(zh: "已授权", en: "Granted") }
    var notGrantedPill: String { t(zh: "未授权", en: "Not Granted") }
    var recheckPermissionHelp: String { t(zh: "重新检测", en: "Re-check") }
    var openSystemSettings: String { t(zh: "打开系统设置", en: "Open System Settings") }
    var requestAccess: String { t(zh: "请求授权", en: "Request Access") }
    var accessibilityTroubleshootTip: String {
        t(
            zh: "已勾选仍显示未授权？在列表里删掉 Ferry，再重新添加。",
            en: "Still not granted after enabling? Remove Ferry from the list and add it again."
        )
    }
    var clipboardPrivacyNote: String {
        t(
            zh: "只在识别到双击 ⌘C 时读取一次剪贴板，不记录其他按键。",
            en: "Reads the clipboard once on double ⌘C only. No other keystrokes are recorded."
        )
    }

    // MARK: - Settings: General

    var appearance: String { t(zh: "外观", en: "Appearance") }
    var interfaceLanguage: String { t(zh: "语言", en: "Language") }

    func systemLanguageCaption(_ resolved: ResolvedAppLanguage) -> String {
        t(zh: "当前：\(resolved.nativeName)", en: "Active: \(resolved.nativeName)")
    }

    var launchAtLogin: String { t(zh: "开机自动启动", en: "Launch at Login") }
    var launchAtLoginCaption: String {
        t(zh: "登录 macOS 时自动在菜单栏启动", en: "Start automatically in the menu bar when you log in")
    }
    var launchAtLoginNeedsApprovalCaption: String {
        t(zh: "请在「系统设置 → 登录项」中允许 Ferry", en: "Allow Ferry in System Settings → Login Items")
    }
    var openLoginItems: String { t(zh: "登录项设置", en: "Login Items") }
    var launchAtLoginRequiresAppBundle: String {
        t(zh: "请从 Ferry.app 运行后再开启开机自动启动。", en: "Run Ferry from Ferry.app to enable Launch at Login.")
    }
    func launchAtLoginFailed(_ error: String) -> String {
        t(zh: "设置开机启动失败：\(error)", en: "Failed to update Launch at Login: \(error)")
    }

    var translationSectionLabel: String { t(zh: "翻译", en: "TRANSLATION") }
    var defaultTargetLanguage: String { t(zh: "默认目标语言", en: "Default Target Language") }
    var defaultTargetLanguageCaption: String {
        t(zh: "自动：中文译英文，其他译中文", en: "Auto: Chinese → English, others → Chinese")
    }
    var wordLookup: String { t(zh: "单词释义", en: "Word Lookup") }
    var wordLookupCaption: String {
        t(zh: "查单词时显示音标、词性和例句", en: "Show phonetics, part of speech & example for words")
    }
    var pdfLineBreakFix: String { t(zh: "PDF / 论文断行修复", en: "PDF Line-Break Cleanup") }
    var pdfLineBreakFixCaption: String {
        t(zh: "自动合并复制来的多余硬回车与连字符断词 (algo-\\nrithm)", en: "Auto-join wrapped PDF lines and de-hyphenate split words")
    }
    var translationCache: String { t(zh: "翻译结果缓存", en: "Translation Cache") }
    var translationCacheToggleCaption: String {
        t(zh: "重复查询相同词句直接命中本地 LRU 缓存，秒出结果并节省 Token", en: "Return instant results for repeated lookups via local LRU cache, saving tokens")
    }

    var speechSectionLabel: String { t(zh: "朗读", en: "SPEECH") }

    func speechEngineLabel(_ engine: SpeechEngine) -> String {
        switch engine {
        case .system: return t(zh: "系统", en: "System")
        case .bailian: return t(zh: "百炼", en: "Bailian")
        case .openAI: return "OpenAI"
        }
    }

    func speechEngineCaption(_ engine: SpeechEngine) -> String {
        switch engine {
        case .system:
            return t(zh: "离线、免费。可在系统设置里下载增强语音", en: "Offline & free. Download enhanced voices in System Settings.")
        case .bailian:
            return t(zh: "复用百炼的 Key，自动缓存最近 30 条", en: "Uses your Bailian API Key. Caches the last 30 clips.")
        case .openAI:
            return t(zh: "复用自定义服务的地址和 Key，自动缓存最近 30 条", en: "Uses your Custom endpoint & API Key. Caches the last 30 clips.")
        }
    }

    var englishAccent: String { t(zh: "英语口音", en: "English Accent") }
    var speechRate: String { t(zh: "语速", en: "Speed") }
    var voice: String { t(zh: "音色", en: "Voice") }
    var ttsModel: String { t(zh: "TTS 模型", en: "TTS Model") }
    var previewSpeech: String { t(zh: "试听", en: "Preview") }

    var otherSectionLabel: String { t(zh: "其他", en: "OTHER") }
    var widgetAlwaysOnTop: String { t(zh: "桌面小窗默认置顶", en: "Keep Mini Widget on Top") }
    var translationHistory: String { t(zh: "翻译记录", en: "Translation History") }

    func translationHistoryCaption(_ count: Int) -> String {
        t(
            zh: "\(count) 条 · 设置和 Key 只存在本机",
            en: "\(count) \(count == 1 ? "item" : "items") · Settings and keys stay on this Mac"
        )
    }

    var translationCacheStorage: String { t(zh: "翻译缓存", en: "Translation Cache") }

    func translationCacheCaption(count: Int, capacity: Int, hits: Int) -> String {
        if hits > 0 {
            return t(
                zh: "\(count) / \(capacity) 条 · 本次已节省 \(hits) 次请求",
                en: "\(count) / \(capacity) cached · \(hits) \(hits == 1 ? "request" : "requests") saved this session"
            )
        }
        return t(
            zh: "\(count) / \(capacity) 条 · 超出上限自动淘汰最久未用记录",
            en: "\(count) / \(capacity) cached · Least-recently-used entries evict automatically"
        )
    }

    // MARK: - Software Updates

    var updatesSectionLabel: String { t(zh: "软件更新", en: "SOFTWARE UPDATES") }
    var checkForUpdates: String { t(zh: "检查更新", en: "Check for Updates") }
    var checkingForUpdates: String { t(zh: "检查中…", en: "Checking…") }
    var downloadUpdate: String { t(zh: "下载更新", en: "Download") }
    var restartToUpdate: String { t(zh: "重启更新", en: "Restart & Update") }
    var installingUpdate: String { t(zh: "正在安装…", en: "Installing…") }
    var viewReleaseNotes: String { t(zh: "更新日志", en: "Release Notes") }
    var skipThisVersion: String { t(zh: "跳过此版本", en: "Skip") }
    var autoCheckUpdates: String { t(zh: "自动检查更新", en: "Automatically Check for Updates") }
    var autoCheckUpdatesCaption: String {
        t(zh: "启动时、休眠唤醒及后台 ETag 静默检查新版本", en: "Check on launch, wake, and periodically via ETag")
    }
    var realtimeUpdatePush: String { t(zh: "实时更新推送", en: "Real-Time Update Push") }
    var realtimeUpdatePushConnectedCaption: String {
        t(zh: "SSE 推送已连接 · 发布新版本后秒级自动接收", en: "Live push connected · receive new releases in seconds")
    }
    var realtimeUpdatePushIdleCaption: String {
        t(zh: "通过轻量 SSE 订阅新版本通知，无需等待轮询", en: "Receive instant release alerts via lightweight SSE")
    }
    var autoDownloadUpdates: String { t(zh: "自动后台下载", en: "Download Updates Automatically") }
    var autoDownloadUpdatesCaption: String {
        t(zh: "发现新版本时静默下载并校验，确认后一键重启生效", en: "Silently download and verify updates for one-click restart")
    }
    func currentVersionLabel(_ version: String) -> String {
        t(zh: "当前版本 v\(version)", en: "Current Version v\(version)")
    }
    func upToDateMessage(_ version: String) -> String {
        t(zh: "已是最新版本 (v\(version))", en: "You're up to date (v\(version))")
    }
    func updateAvailableTitle(_ version: String) -> String {
        t(zh: "发现新版本 v\(version)", en: "Version v\(version) available")
    }
    func updateReadyTitle(_ version: String) -> String {
        t(zh: "新版本 v\(version) 已就绪", en: "v\(version) ready to install")
    }
    func downloadingUpdateProgress(_ version: String, percent: Int) -> String {
        t(zh: "正在下载 v\(version) (\(percent)%)", en: "Downloading v\(version) (\(percent)%)")
    }
}
