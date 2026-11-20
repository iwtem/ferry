import AppKit
import FerryCore
import SwiftUI

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settingsStore = SettingsStore()
    private let translatorService = LLMTranslatorService()

    private lazy var copyMonitor = GlobalCopyMonitor(settingsStore: settingsStore)
    private lazy var speechService = SpeechService(settingsStore: settingsStore)
    private lazy var popoverSession = TranslatorSession(settingsStore: settingsStore, translatorService: translatorService)
    private lazy var mainWindowSession = TranslatorSession(settingsStore: settingsStore, translatorService: translatorService)
    private lazy var quickPopupSession = TranslatorSession(settingsStore: settingsStore, translatorService: translatorService)
    private lazy var desktopWidgetSession = TranslatorSession(settingsStore: settingsStore, translatorService: translatorService)

    private var statusItem: NSStatusItem?
    private let menuBarPanel = MenuBarPanelController()
    private var mainWindow: NSWindow?
    private var settingsWindow: NSWindow?

    private let quickPopupController = QuickPopupController()
    private let desktopWidgetController = DesktopMiniWidgetController()
    private let mainWindowUIState = MainWindowUIState()
    private let quickPopupUIState = QuickPopupUIState()
    private lazy var settingsUIState = SettingsUIState(initialProvider: settingsStore.settings.activeProvider)

    public func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        UISnapshot.runIfRequested()
        #endif
        // Hide Dock icon; live cleanly in the macOS menu bar
        NSApp.setActivationPolicy(.accessory)
        FerryAppearance.apply(settingsStore.settings.appearance)
        menuBarPanel.onHide = { [weak self] in self?.speechService.stop() }
        setupMainMenu()
        setupStatusItem()
        setupGlobalCopyMonitor()

        // First launch: if no API key is configured yet, gently open the menu bar popover so user sees the app immediately
        if !settingsStore.hasActiveAPIKey {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                self?.openPopover()
            }
        }
    }

    public func applicationWillTerminate(_ notification: Notification) {
        copyMonitor.stopMonitoring()
        speechService.stop()
    }

    // MARK: - Standard Main Menu (enables Cmd+C/V/X/A/Z in LSUIElement app)

    private func setupMainMenu() {
        let mainMenu = NSMenu()

        // App menu
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu(title: "Ferry")
        appMenu.addItem(withTitle: "设置…", action: #selector(openSettingsAction), keyEquivalent: ",")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "退出 渡 Ferry",action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        // Edit menu (critical for Cmd+C / Cmd+V / Cmd+A / Cmd+Z in text fields!)
        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "编辑")
        editMenu.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "重做", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "拷贝", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        // Window menu
        let windowMenuItem = NSMenuItem()
        let windowMenu = NSMenu(title: "窗口")
        windowMenu.addItem(withTitle: "关闭窗口", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)

        NSApp.mainMenu = mainMenu
    }

    // MARK: - Menu Bar Status Item & Popover

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.image = MenuBarIcon.make(accessibilityDescription: "渡 Ferry")
            button.toolTip = "渡 Ferry（左键快译，右键菜单）"
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        statusItem = item
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else {
            togglePopover()
            return
        }
        if event.type == .rightMouseUp {
            showStatusContextMenu(from: sender)
        } else {
            togglePopover()
        }
    }

    private func showStatusContextMenu(from button: NSStatusBarButton) {
        let menu = NSMenu()
        menu.addItem(withTitle: "菜单栏快译", action: #selector(openPopoverAction), keyEquivalent: "")
        menu.addItem(withTitle: "打开大窗口", action: #selector(openMainWindowAction), keyEquivalent: "")
        menu.addItem(
            withTitle: desktopWidgetController.isVisible ? "隐藏桌面悬浮小窗" : "打开桌面悬浮小窗",
            action: #selector(toggleDesktopWidgetAction),
            keyEquivalent: ""
        )
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "设置…", action: #selector(openSettingsAction), keyEquivalent: ",")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "退出 渡 Ferry",action: #selector(quitAction), keyEquivalent: "q")

        for item in menu.items {
            item.target = self
        }

        statusItem?.menu = menu
        button.performClick(nil)
        statusItem?.menu = nil
    }

    private func togglePopover() {
        guard let button = statusItem?.button else { return }
        menuBarPanel.toggle(below: button) { self.makeMenuBarContent() }
    }

    private func openPopover() {
        guard let button = statusItem?.button else { return }
        menuBarPanel.show(below: button, content: makeMenuBarContent())
    }

    private func makeMenuBarContent() -> AnyView {
        copyMonitor.refreshPermissionStatus()
        return AnyView(MenuBarPopoverView(
            session: popoverSession,
            settingsStore: settingsStore,
            speechService: speechService,
            onOpenMainWindow: { [weak self] in
                guard let self else { return }
                self.menuBarPanel.hide()
                if !self.popoverSession.sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    self.mainWindowSession.loadFrom(self.popoverSession)
                }
                self.openMainWindow()
            },
            onToggleDesktopWidget: { [weak self] in
                self?.menuBarPanel.hide()
                self?.toggleDesktopWidget()
            },
            onOpenSettings: { [weak self] in
                self?.menuBarPanel.hide()
                self?.openSettingsWindow()
            },
            onQuit: {
                NSApp.terminate(nil)
            },
            onHeightChange: { [weak self] height in
                self?.menuBarPanel.resize(toHeight: height)
            }
        ))
    }

    // MARK: - Double Cmd+C Global Monitor & Floating Popup

    private func setupGlobalCopyMonitor() {
        copyMonitor.onDoubleCopy = { [weak self] copiedText, mouseLocation in
            self?.handleDoubleCopy(text: copiedText, near: mouseLocation)
        }
        copyMonitor.startMonitoring()
    }

    private func handleDoubleCopy(text: String, near mouseLocation: NSPoint) {
        quickPopupSession.targetLanguage = settingsStore.settings.defaultTargetLanguage
        quickPopupSession.translate(text: text)
        quickPopupUIState.isPinned = quickPopupController.isPinned
        quickPopupUIState.showFullSource = false

        quickPopupController.show(near: mouseLocation) { [weak self] in
            guard let self else { return AnyView(EmptyView()) }
            return AnyView(
                QuickPopupView(
                    session: self.quickPopupSession,
                    settingsStore: self.settingsStore,
                    speechService: self.speechService,
                    uiState: self.quickPopupUIState,
                    onTogglePin: { [weak self] pinned in
                        self?.quickPopupController.isPinned = pinned
                    },
                    onOpenInMainWindow: { [weak self] in
                        guard let self else { return }
                        self.speechService.stop()
                        self.mainWindowSession.loadFrom(self.quickPopupSession)
                        self.quickPopupUIState.isPinned = false
                        self.quickPopupController.hide()
                        self.openMainWindow()
                    },
                    onOpenSettings: { [weak self] in
                        self?.speechService.stop()
                        self?.quickPopupUIState.isPinned = false
                        self?.quickPopupController.hide()
                        self?.openSettingsWindow()
                    },
                    onClose: { [weak self] in
                        self?.speechService.stop()
                        self?.quickPopupUIState.isPinned = false
                        self?.quickPopupController.hide()
                    }
                )
            )
        }
    }

    // MARK: - Desktop Floating Mini Widget

    private func toggleDesktopWidget() {
        desktopWidgetController.toggle(alwaysOnTop: settingsStore.settings.desktopWidgetAlwaysOnTop) { [weak self] in
            guard let self else { return AnyView(EmptyView()) }
            return AnyView(
                DesktopMiniWidgetView(
                    session: self.desktopWidgetSession,
                    settingsStore: self.settingsStore,
                    speechService: self.speechService,
                    onToggleAlwaysOnTop: { [weak self] onTop in
                        self?.desktopWidgetController.setAlwaysOnTop(onTop)
                    },
                    onOpenInMainWindow: { [weak self] in
                        guard let self else { return }
                        if !self.desktopWidgetSession.sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            self.mainWindowSession.loadFrom(self.desktopWidgetSession)
                        }
                        self.openMainWindow()
                    },
                    onOpenSettings: { [weak self] in
                        self?.openSettingsWindow()
                    },
                    onClose: { [weak self] in
                        self?.speechService.stop()
                        self?.desktopWidgetController.hide()
                    }
                )
            )
        }
    }

    // MARK: - Standalone Large Window & Settings Window

    private func openMainWindow() {
        copyMonitor.refreshPermissionStatus()

        if let existing = mainWindow {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let mainWindowSession = self.mainWindowSession
        let settingsStore = self.settingsStore
        let copyMonitor = self.copyMonitor
        let speechService = self.speechService
        let mainWindowUIState = self.mainWindowUIState
        let onToggleDesktopWidget: () -> Void = { [weak self] in
            self?.toggleDesktopWidget()
        }
        let onOpenSettings: () -> Void = { [weak self] in
            self?.openSettingsWindow()
        }

        let rootView = MainWindowView(
            session: mainWindowSession,
            settingsStore: settingsStore,
            copyMonitor: copyMonitor,
            speechService: speechService,
            uiState: mainWindowUIState,
            onToggleDesktopWidget: onToggleDesktopWidget,
            onOpenSettings: onOpenSettings
        )

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 940, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "渡 Ferry"
        window.minSize = NSSize(width: 760, height: 460)
        Self.applyStageChrome(to: window)
        window.isReleasedWhenClosed = false
        let hostingController = NSHostingController(rootView: rootView)
        hostingController.safeAreaRegions = []
        window.contentViewController = hostingController
        window.center()

        mainWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func openSettingsWindow() {
        copyMonitor.refreshPermissionStatus()

        if let existing = settingsWindow {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let settingsStore = self.settingsStore
        let copyMonitor = self.copyMonitor
        let translatorService = self.translatorService
        let speechService = self.speechService
        let settingsUIState = self.settingsUIState

        let rootView = SettingsView(
            settingsStore: settingsStore,
            copyMonitor: copyMonitor,
            translatorService: translatorService,
            speechService: speechService,
            uiState: settingsUIState
        )

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: SettingsView.windowSize),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "渡 Ferry 设置"
        Self.applyStageChrome(to: window)
        window.isReleasedWhenClosed = false
        let hostingController = NSHostingController(rootView: rootView)
        hostingController.safeAreaRegions = []
        window.contentViewController = hostingController
        window.setContentSize(SettingsView.windowSize)
        window.center()

        settingsWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - ObjC Actions

    @objc private func openPopoverAction() {
        openPopover()
    }

    @objc private func openMainWindowAction() {
        openMainWindow()
    }

    @objc private func toggleDesktopWidgetAction() {
        toggleDesktopWidget()
    }

    @objc private func openSettingsAction() {
        openSettingsWindow()
    }

    @objc private func quitAction() {
        NSApp.terminate(nil)
    }

    /// Content runs under a transparent title bar (traffic lights float over the app's own header).
    /// The window follows the app-wide appearance (see FerryAppearance).
    private static func applyStageChrome(to window: NSWindow) {
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.backgroundColor = Stage.windowColor
        window.isMovableByWindowBackground = true
    }
}
