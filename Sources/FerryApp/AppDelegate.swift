import AppKit
import FerryCore
import SwiftUI

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settingsStore = SettingsStore()
    private let translatorService = LLMTranslatorService()
    private let ocrService = OCRService()

    private lazy var copyMonitor = GlobalCopyMonitor(settingsStore: settingsStore)
    private lazy var speechService = SpeechService(settingsStore: settingsStore)
    private let launchAtLogin = LaunchAtLoginService()
    private let screenCaptureService = ScreenCaptureService()
    private let hotkeyService = GlobalHotkeyService()
    private let updateService = AppUpdateService()
    private lazy var popoverSession = TranslatorSession(settingsStore: settingsStore, translatorService: translatorService)
    private lazy var mainWindowSession = TranslatorSession(settingsStore: settingsStore, translatorService: translatorService)
    private lazy var quickPopupSession = TranslatorSession(settingsStore: settingsStore, translatorService: translatorService)
    private lazy var desktopWidgetSession = TranslatorSession(settingsStore: settingsStore, translatorService: translatorService)

    private var statusItem: NSStatusItem?
    private let menuBarPanel = MenuBarPanelController()
    private var mainWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private var languageObserver: NSObjectProtocol?
    private var ocrTask: Task<Void, Never>?

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
        setupGlobalHotkeys()
        observeLanguageChanges()
        updateService.start(settingsStore: settingsStore)

        // First launch: if no API key is configured yet, gently open the menu bar popover so user sees the app immediately
        if !settingsStore.hasActiveAPIKey {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                self?.openPopover()
            }
        }
    }

    public func applicationWillTerminate(_ notification: Notification) {
        if let languageObserver {
            NotificationCenter.default.removeObserver(languageObserver)
            self.languageObserver = nil
        }
        ocrTask?.cancel()
        ocrTask = nil
        copyMonitor.stopMonitoring()
        hotkeyService.stop()
        screenCaptureService.stopObserving()
        updateService.stop()
        speechService.stop()
        launchAtLogin.stopObserving()
    }

    private func observeLanguageChanges() {
        languageObserver = NotificationCenter.default.addObserver(
            forName: .ferryLanguageDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshLocalizedChrome()
            }
        }
    }

    private func refreshLocalizedChrome() {
        let l10n = L10n(settingsStore.resolvedLanguage)
        setupMainMenu()
        if let button = statusItem?.button {
            button.image = MenuBarIcon.make(accessibilityDescription: l10n.brandName)
            button.toolTip = l10n.statusItemTooltip
        }
        mainWindow?.title = l10n.brandName
        settingsWindow?.title = l10n.settingsWindowTitle
    }

    // MARK: - Standard Main Menu (enables Cmd+C/V/X/A/Z in LSUIElement app)

    private func setupMainMenu() {
        let l10n = L10n(settingsStore.resolvedLanguage)
        let mainMenu = NSMenu()

        // App menu
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu(title: "Ferry")
        appMenu.addItem(withTitle: l10n.menuSettings, action: #selector(openSettingsAction), keyEquivalent: ",")
        appMenu.addItem(withTitle: l10n.statusCheckForUpdates, action: #selector(checkForUpdatesAction), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: l10n.menuQuitApp, action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        // Edit menu (critical for Cmd+C / Cmd+V / Cmd+A / Cmd+Z in text fields!)
        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: l10n.menuEdit)
        editMenu.addItem(withTitle: l10n.menuUndo, action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: l10n.menuRedo, action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(withTitle: l10n.menuCut, action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: l10n.menuCopy, action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: l10n.menuPaste, action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: l10n.menuSelectAll, action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        // Window menu
        let windowMenuItem = NSMenuItem()
        let windowMenu = NSMenu(title: l10n.menuWindow)
        windowMenu.addItem(withTitle: l10n.menuCloseWindow, action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)

        NSApp.mainMenu = mainMenu
    }

    // MARK: - Menu Bar Status Item & Popover

    private func setupStatusItem() {
        let l10n = L10n(settingsStore.resolvedLanguage)
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.image = MenuBarIcon.make(accessibilityDescription: l10n.brandName)
            button.toolTip = l10n.statusItemTooltip
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
        let l10n = L10n(settingsStore.resolvedLanguage)
        let menu = NSMenu()
        menu.addItem(withTitle: l10n.statusQuickTranslate, action: #selector(openPopoverAction), keyEquivalent: "")
        let ocrTitle = settingsStore.settings.screenshotOCREnabled
            ? l10n.statusScreenshotOCRWithShortcut(settingsStore.settings.screenshotOCRShortcut.displayString)
            : l10n.statusScreenshotOCR
        menu.addItem(withTitle: ocrTitle, action: #selector(screenshotOCRAction), keyEquivalent: "")
        menu.addItem(withTitle: l10n.statusOpenMainWindow, action: #selector(openMainWindowAction), keyEquivalent: "")
        menu.addItem(
            withTitle: desktopWidgetController.isVisible ? l10n.statusHideMiniWidget : l10n.statusShowMiniWidget,
            action: #selector(toggleDesktopWidgetAction),
            keyEquivalent: ""
        )
        menu.addItem(NSMenuItem.separator())
        if case .readyToInstall(let release, _) = updateService.state {
            menu.addItem(
                withTitle: l10n.statusRestartToUpdate(release.version.description),
                action: #selector(installUpdateAction),
                keyEquivalent: ""
            )
        } else {
            menu.addItem(withTitle: l10n.statusCheckForUpdates, action: #selector(checkForUpdatesAction), keyEquivalent: "")
        }
        menu.addItem(withTitle: l10n.menuSettings, action: #selector(openSettingsAction), keyEquivalent: ",")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: l10n.menuQuitApp, action: #selector(quitAction), keyEquivalent: "q")

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
            updateService: updateService,
            onScreenshotOCR: { [weak self] in
                self?.triggerScreenshotOCR(destination: .quickPopup)
            },
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

    private func setupGlobalHotkeys() {
        hotkeyService.onScreenshotOCR = { [weak self] in
            self?.triggerScreenshotOCR(destination: .quickPopup)
        }
        hotkeyService.start(settingsStore: settingsStore)
    }

    private func handleDoubleCopy(text: String, near mouseLocation: NSPoint) {
        quickPopupSession.targetLanguage = settingsStore.settings.defaultTargetLanguage
        quickPopupSession.translate(text: text)
        showQuickPopup(near: mouseLocation)
    }

    private func showQuickPopup(near mouseLocation: NSPoint) {
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
                    onOpenScreenRecordingSettings: { [weak self] in
                        self?.screenCaptureService.openScreenRecordingSettings()
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

    // MARK: - Screenshot OCR Translation

    private enum ScreenshotOCRDestination {
        case quickPopup
        case mainWindow
    }

    private func triggerScreenshotOCR(destination: ScreenshotOCRDestination) {
        guard !screenCaptureService.isCapturing else { return }

        let wasPopoverOpen = menuBarPanel.isVisible
        if wasPopoverOpen {
            menuBarPanel.hide()
        }

        ocrTask?.cancel()
        ocrTask = Task { [weak self] in
            guard let self else { return }
            if wasPopoverOpen {
                try? await Task.sleep(for: .milliseconds(160))
                guard !Task.isCancelled else { return }
            }

            do {
                guard let capture = try await self.screenCaptureService.captureInteractiveRegion() else {
                    return // User pressed Esc to cancel
                }
                guard !Task.isCancelled else { return }

                switch destination {
                case .quickPopup:
                    self.quickPopupSession.targetLanguage = self.settingsStore.settings.defaultTargetLanguage
                    self.quickPopupSession.beginOCRRecognition()
                    self.showQuickPopup(near: capture.anchorPoint)
                    await self.performOCR(on: capture.cgImage, into: self.quickPopupSession)
                case .mainWindow:
                    self.openMainWindow()
                    self.mainWindowSession.beginOCRRecognition()
                    await self.performOCR(on: capture.cgImage, into: self.mainWindowSession)
                }
            } catch {
                guard !Task.isCancelled else { return }
                let session = destination == .mainWindow ? self.mainWindowSession : self.quickPopupSession
                session.failOCRRecognition(message: error.localizedDescription)
                if destination == .quickPopup {
                    self.showQuickPopup(near: NSEvent.mouseLocation)
                }
            }
        }
    }

    private func recognizeAndTranslate(image: CGImage, in destination: ScreenshotOCRDestination) {
        ocrTask?.cancel()
        ocrTask = Task { [weak self] in
            guard let self else { return }
            let session = destination == .mainWindow ? self.mainWindowSession : self.quickPopupSession
            session.beginOCRRecognition()
            await self.performOCR(on: image, into: session)
        }
    }

    private func performOCR(on cgImage: CGImage, into session: TranslatorSession) async {
        do {
            let recognized = try await ocrService.recognizeText(from: cgImage)
            guard !Task.isCancelled else { return }
            session.finishOCRRecognition(withText: recognized)
        } catch let ocrError as OCRError {
            guard !Task.isCancelled else { return }
            if ocrError == .noTextFound && !screenCaptureService.hasScreenRecordingPermission {
                session.failOCRRecognition(
                    message: OCRError.permissionDenied.localizedDescription,
                    needsScreenRecordingPermission: true
                )
            } else {
                session.failOCRRecognition(message: ocrError.localizedDescription)
            }
        } catch {
            guard !Task.isCancelled else { return }
            session.failOCRRecognition(message: error.localizedDescription)
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
        let onScreenshotOCR: () -> Void = { [weak self] in
            self?.triggerScreenshotOCR(destination: .mainWindow)
        }
        let onPasteImageOCR: (CGImage) -> Void = { [weak self] image in
            self?.recognizeAndTranslate(image: image, in: .mainWindow)
        }
        let onToggleDesktopWidget: () -> Void = { [weak self] in
            self?.toggleDesktopWidget()
        }
        let onOpenSettings: () -> Void = { [weak self] in
            self?.openSettingsWindow()
        }
        let onOpenScreenRecordingSettings: () -> Void = { [weak self] in
            self?.screenCaptureService.openScreenRecordingSettings()
        }

        let rootView = MainWindowView(
            session: mainWindowSession,
            settingsStore: settingsStore,
            copyMonitor: copyMonitor,
            speechService: speechService,
            updateService: updateService,
            uiState: mainWindowUIState,
            onScreenshotOCR: onScreenshotOCR,
            onPasteImageOCR: onPasteImageOCR,
            onToggleDesktopWidget: onToggleDesktopWidget,
            onOpenSettings: onOpenSettings,
            onOpenScreenRecordingSettings: onOpenScreenRecordingSettings
        )

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 940, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = L10n(settingsStore.resolvedLanguage).brandName
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
        let launchAtLogin = self.launchAtLogin
        let screenCaptureService = self.screenCaptureService
        let hotkeyService = self.hotkeyService
        let updateService = self.updateService
        let settingsUIState = self.settingsUIState

        let rootView = SettingsView(
            settingsStore: settingsStore,
            copyMonitor: copyMonitor,
            translatorService: translatorService,
            speechService: speechService,
            launchAtLogin: launchAtLogin,
            screenCaptureService: screenCaptureService,
            hotkeyService: hotkeyService,
            updateService: updateService,
            onTriggerScreenshotOCR: { [weak self] in
                self?.triggerScreenshotOCR(destination: .quickPopup)
            },
            uiState: settingsUIState
        )

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: SettingsView.windowSize),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = L10n(settingsStore.resolvedLanguage).settingsWindowTitle
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

    @objc private func screenshotOCRAction() {
        triggerScreenshotOCR(destination: .quickPopup)
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

    @objc private func checkForUpdatesAction() {
        settingsUIState.selectedPane = .general
        openSettingsWindow()
        updateService.checkForUpdates(userInitiated: true)
    }

    @objc private func installUpdateAction() {
        updateService.installAndRelaunch()
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
