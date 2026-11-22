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
    private let textReplacementService = TextReplacementService()
    private lazy var popoverSession = TranslatorSession(settingsStore: settingsStore, translatorService: translatorService)
    private lazy var mainWindowSession = TranslatorSession(settingsStore: settingsStore, translatorService: translatorService)
    private lazy var quickPopupSession = TranslatorSession(settingsStore: settingsStore, translatorService: translatorService)
    private lazy var desktopWidgetSession = TranslatorSession(settingsStore: settingsStore, translatorService: translatorService)

    private var statusItem: NSStatusItem?
    private var statusUpdateDot: NSView?
    private let menuBarPanel = MenuBarPanelController()
    private var mainWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private var languageObserver: NSObjectProtocol?
    private var ocrTask: Task<Void, Never>?
    private var selectionTask: Task<Void, Never>?
    private var quickPopupSourceApp: NSRunningApplication?

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
        updateService.onStateChange = { [weak self] _ in
            self?.refreshStatusUpdateBadge()
        }
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
        selectionTask?.cancel()
        selectionTask = nil
        copyMonitor.stopMonitoring()
        hotkeyService.stop()
        screenCaptureService.stopObserving()
        updateService.stop()
        speechService.stop()
        launchAtLogin.stopObserving()
        settingsStore.flushTranslationCache()
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
        }
        refreshStatusUpdateBadge()
        mainWindow?.title = l10n.brandName
        settingsWindow?.title = l10n.settingsWindowTitle
    }

    private func refreshStatusUpdateBadge() {
        guard let button = statusItem?.button else { return }
        let l10n = L10n(settingsStore.resolvedLanguage)
        let showDot = updateService.shouldShowStatusBadge

        if showDot, let version = updateService.state.release?.version.description {
            button.toolTip = l10n.statusItemUpdateTooltip(version)
        } else {
            button.toolTip = l10n.statusItemTooltip
        }

        if showDot {
            if statusUpdateDot == nil {
                let dot = NSView(frame: NSRect(x: button.bounds.width - 8, y: 3, width: 6, height: 6))
                dot.wantsLayer = true
                dot.layer?.cornerRadius = 3
                dot.layer?.backgroundColor = NSColor(srgbRed: 1.0, green: 0.443, blue: 0.349, alpha: 1.0).cgColor
                dot.autoresizingMask = [.minXMargin, .maxYMargin]
                button.addSubview(dot)
                statusUpdateDot = dot
            }
            statusUpdateDot?.isHidden = false
        } else {
            statusUpdateDot?.isHidden = true
        }
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
        let quickTitle = settingsStore.settings.quickTranslateShortcutEnabled
            ? l10n.statusQuickTranslateWithShortcut(settingsStore.settings.quickTranslateShortcut.displayString)
            : l10n.statusQuickTranslate
        menu.addItem(withTitle: quickTitle, action: #selector(openPopoverAction), keyEquivalent: "")
        let ocrTitle = settingsStore.settings.screenshotOCREnabled
            ? l10n.statusScreenshotOCRWithShortcut(settingsStore.settings.screenshotOCRShortcut.displayString)
            : l10n.statusScreenshotOCR
        menu.addItem(withTitle: ocrTitle, action: #selector(screenshotOCRAction), keyEquivalent: "")
        let mainTitle = settingsStore.settings.mainWindowShortcutEnabled
            ? l10n.statusOpenMainWindowWithShortcut(settingsStore.settings.mainWindowShortcut.displayString)
            : l10n.statusOpenMainWindow
        menu.addItem(withTitle: mainTitle, action: #selector(openMainWindowAction), keyEquivalent: "")
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

    private func togglePopover(ignoreDebounce: Bool = false) {
        guard let button = statusItem?.button else { return }
        menuBarPanel.toggle(below: button, ignoreDebounce: ignoreDebounce) { self.makeMenuBarContent() }
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
        copyMonitor.onDoubleCopy = { [weak self] copiedText, mouseLocation, sourceApp in
            self?.handleDoubleCopy(text: copiedText, near: mouseLocation, sourceApp: sourceApp)
        }
        copyMonitor.startMonitoring()
    }

    private func setupGlobalHotkeys() {
        hotkeyService.onQuickTranslate = { [weak self] in
            self?.togglePopover(ignoreDebounce: true)
        }
        hotkeyService.onMainWindow = { [weak self] in
            self?.toggleMainWindow()
        }
        hotkeyService.onScreenshotOCR = { [weak self] in
            self?.triggerScreenshotOCR(destination: .quickPopup)
        }
        hotkeyService.onSelectionTranslate = { [weak self] in
            self?.triggerSelectionTranslate()
        }
        hotkeyService.start(settingsStore: settingsStore)
    }

    private func handleDoubleCopy(text: String, near mouseLocation: NSPoint, sourceApp: NSRunningApplication?) {
        quickPopupSourceApp = sourceApp
        quickPopupUIState.sourceAppName = sourceApp?.localizedName
        quickPopupSession.targetLanguage = settingsStore.settings.defaultTargetLanguage
        quickPopupSession.translate(text: text)
        showQuickPopup(near: mouseLocation)
    }

    private func triggerSelectionTranslate() {
        if menuBarPanel.isVisible {
            menuBarPanel.hide()
        }

        selectionTask?.cancel()
        selectionTask = Task { [weak self] in
            guard let self else { return }
            do {
                let captured = try await self.textReplacementService.captureSelection(copyMonitor: self.copyMonitor)
                guard !Task.isCancelled else { return }
                self.quickPopupSourceApp = captured.sourceApp
                self.quickPopupUIState.sourceAppName = captured.sourceApp?.localizedName
                self.quickPopupSession.targetLanguage = self.settingsStore.settings.defaultTargetLanguage
                self.quickPopupSession.translate(text: captured.text)
                self.showQuickPopup(near: captured.mouseLocation)
            } catch let replaceError as TextReplacementError {
                guard !Task.isCancelled else { return }
                self.quickPopupSourceApp = nil
                self.quickPopupUIState.sourceAppName = nil
                if replaceError == .accessibilityRequired {
                    self.quickPopupSession.failWithAccessibilityError(replaceError.localizedDescription)
                } else {
                    self.quickPopupSession.failOCRRecognition(message: replaceError.localizedDescription)
                }
                self.showQuickPopup(near: NSEvent.mouseLocation)
            } catch {
                guard !Task.isCancelled else { return }
                self.quickPopupSession.failOCRRecognition(message: error.localizedDescription)
                self.showQuickPopup(near: NSEvent.mouseLocation)
            }
        }
    }

    private func replaceInSourceApp() {
        let output = quickPopupSession.translatedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !output.isEmpty else { return }
        let targetApp = quickPopupSourceApp

        speechService.stop()
        quickPopupUIState.isPinned = false
        quickPopupController.hide()

        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.textReplacementService.replaceSelection(with: output, in: targetApp)
            } catch let replaceError as TextReplacementError {
                if replaceError == .accessibilityRequired {
                    self.quickPopupSession.failWithAccessibilityError(replaceError.localizedDescription)
                } else {
                    self.quickPopupSession.failOCRRecognition(message: replaceError.localizedDescription)
                }
                self.showQuickPopup(near: NSEvent.mouseLocation)
            } catch {
                self.quickPopupSession.failOCRRecognition(message: error.localizedDescription)
                self.showQuickPopup(near: NSEvent.mouseLocation)
            }
        }
    }

    private func showQuickPopup(near mouseLocation: NSPoint) {
        quickPopupUIState.isPinned = quickPopupController.isPinned
        quickPopupUIState.showFullSource = false

        let initialSize = NSSize(
            width: QuickPopupView.width,
            height: quickPopupSession.isComparing ? QuickPopupView.compareHeight : QuickPopupView.standardHeight
        )
        quickPopupController.show(near: mouseLocation, size: initialSize) { [weak self] in
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
                    onOpenAccessibilitySettings: { [weak self] in
                        self?.copyMonitor.openAccessibilitySettings()
                    },
                    onReplaceInSourceApp: { [weak self] in
                        self?.replaceInSourceApp()
                    },
                    onHeightChange: { [weak self] height in
                        self?.quickPopupController.resize(toHeight: height)
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
                    self.quickPopupSourceApp = nil
                    self.quickPopupUIState.sourceAppName = nil
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

    private func toggleMainWindow() {
        if menuBarPanel.isVisible {
            menuBarPanel.hide()
        }
        if let existing = mainWindow, existing.isVisible, existing.isKeyWindow, NSApp.isActive {
            existing.orderOut(nil)
            return
        }
        openMainWindow()
    }

    private func openMainWindow() {
        copyMonitor.refreshPermissionStatus()

        if let existing = mainWindow {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            mainWindowUIState.focusTrigger += 1
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

        let window = AlignedChromeWindow(
            contentRect: NSRect(x: 0, y: 0, width: 940, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.headerHeight = MainWindowView.headerHeight
        window.title = L10n(settingsStore.resolvedLanguage).brandName
        window.minSize = NSSize(width: 760, height: 460)
        Self.applyStageChrome(to: window)
        window.isReleasedWhenClosed = false
        let hostingController = NSHostingController(rootView: rootView)
        hostingController.safeAreaRegions = []
        window.contentViewController = hostingController
        window.center()
        window.alignTrafficLights()

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

/// Custom NSWindow that aligns the macOS traffic light buttons cleanly on the vertical centerline
/// of Ferry's custom header bar (while keeping them strictly within the native titlebar bounds).
@MainActor
private final class AlignedChromeWindow: NSWindow {
    var headerHeight: CGFloat = 44
    private let leadingOffset: CGFloat = 14
    private var chromeObservers: [NSObjectProtocol] = []

    override init(
        contentRect: NSRect,
        styleMask style: NSWindow.StyleMask,
        backing backingStoreType: NSWindow.BackingStoreType,
        defer flag: Bool
    ) {
        super.init(contentRect: contentRect, styleMask: style, backing: backingStoreType, defer: flag)
        installChromeObservers()
    }

    private func installChromeObservers() {
        let names: [Notification.Name] = [
            NSWindow.didResizeNotification,
            NSWindow.didBecomeKeyNotification,
            NSWindow.didResignKeyNotification,
            NSWindow.didExitFullScreenNotification
        ]
        chromeObservers = names.map { name in
            NotificationCenter.default.addObserver(forName: name, object: self, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.alignTrafficLights()
                }
            }
        }
    }

    override func layoutIfNeeded() {
        super.layoutIfNeeded()
        alignTrafficLights()
    }

    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        super.setFrame(frameRect, display: flag)
        alignTrafficLights()
    }

    func alignTrafficLights() {
        let buttons: [NSButton] = [
            standardWindowButton(.closeButton),
            standardWindowButton(.miniaturizeButton),
            standardWindowButton(.zoomButton)
        ].compactMap { $0 }

        guard buttons.count == 3, let titlebar = buttons[0].superview else { return }

        let titlebarHeight = titlebar.bounds.height
        guard titlebarHeight > 0 else { return }

        // Preserve native horizontal spacing between buttons while aligning the left edge cleanly.
        let nativeStep = max(buttons[1].frame.origin.x - buttons[0].frame.origin.x, 20)
        let targetCenterFromTop = headerHeight * 0.5

        for (index, button) in buttons.enumerated() {
            var frame = button.frame
            let desiredY = titlebarHeight - targetCenterFromTop - (frame.height * 0.5)
            // Keep strictly inside NSTitlebarView bounds so buttons are never clipped on any macOS version.
            frame.origin.y = max(2, min(desiredY, titlebarHeight - frame.height - 2)).rounded()
            frame.origin.x = (leadingOffset + CGFloat(index) * nativeStep).rounded()
            if button.frame != frame {
                button.setFrameOrigin(frame.origin)
            }
        }
    }
}
