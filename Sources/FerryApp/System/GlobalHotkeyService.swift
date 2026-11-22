import AppKit
import Carbon.HIToolbox
import FerryCore
import Foundation
import Observation

/// Registers global macOS hotkeys via Carbon `RegisterEventHotKey` (works without Accessibility permission).
@MainActor
@Observable
public final class GlobalHotkeyService {
    public var onQuickTranslate: (() -> Void)?
    public var onMainWindow: (() -> Void)?
    public var onScreenshotOCR: (() -> Void)?
    public var onSelectionTranslate: (() -> Void)?

    /// Actions whose Carbon hotkey registration failed (typically because another app already claimed the combo).
    public private(set) var failedActions: Set<GlobalHotkeyAction> = []
    /// Enabled actions that share the exact same key combination inside Ferry.
    public private(set) var duplicateActions: Set<GlobalHotkeyAction> = []

    public var quickTranslateRegistrationFailed: Bool { failedActions.contains(.quickTranslate) }
    public var mainWindowRegistrationFailed: Bool { failedActions.contains(.mainWindow) }
    public var screenshotRegistrationFailed: Bool { failedActions.contains(.screenshotOCR) }
    public var selectionRegistrationFailed: Bool { failedActions.contains(.selectionTranslate) }

    public var registrationFailed: Bool {
        !failedActions.isEmpty
    }

    public func hasConflict(for action: GlobalHotkeyAction) -> Bool {
        failedActions.contains(action) || duplicateActions.contains(action)
    }

    private var eventHandlerRef: EventHandlerRef?
    private var hotKeyRefs: [GlobalHotkeyAction: EventHotKeyRef] = [:]
    private var configuredHotkeys: [GlobalHotkeyAction: (enabled: Bool, shortcut: HotkeyShortcut)] = [:]

    private var isPaused: Bool = false
    private var settingsObserver: NSObjectProtocol?
    private weak var settingsStore: SettingsStore?

    private static let hotKeySignature: OSType = 0x46525259 // 'FRRY'

    public init() {}

    public func start(settingsStore: SettingsStore) {
        self.settingsStore = settingsStore
        installHandlerIfNeeded()
        sync(with: settingsStore.settings)

        if let settingsObserver {
            NotificationCenter.default.removeObserver(settingsObserver)
        }
        settingsObserver = NotificationCenter.default.addObserver(
            forName: .ferryHotkeySettingsDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let store = self.settingsStore else { return }
                self.sync(with: store.settings)
            }
        }
    }

    public func stop() {
        if let settingsObserver {
            NotificationCenter.default.removeObserver(settingsObserver)
            self.settingsObserver = nil
        }
        unregisterAllHotKeys()
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
        }
    }

    /// Temporarily unregisters active hotkeys while the user records a new shortcut in Settings,
    /// so pressing the current shortcut is captured by the recorder instead of firing an action.
    public func setPaused(_ paused: Bool) {
        guard isPaused != paused else { return }
        isPaused = paused
        applyRegistrations()
    }

    public func sync(with settings: AppSettings) {
        var next: [GlobalHotkeyAction: (enabled: Bool, shortcut: HotkeyShortcut)] = [:]
        for action in GlobalHotkeyAction.allCases {
            next[action] = (
                enabled: settings.isHotkeyEnabled(action),
                shortcut: settings.hotkeyShortcut(for: action)
            )
        }
        configuredHotkeys = next
        duplicateActions = settings.conflictingHotkeyActions()
        applyRegistrations()
    }

    private func applyRegistrations() {
        unregisterAllHotKeys()
        var failed: Set<GlobalHotkeyAction> = []

        guard !isPaused else {
            failedActions = []
            return
        }

        var claimedShortcuts = Set<HotkeyShortcut>()
        for action in GlobalHotkeyAction.allCases {
            guard let entry = configuredHotkeys[action], entry.enabled, entry.shortcut.isValid else {
                continue
            }
            // Avoid double-registering an identical shortcut within Ferry.
            if !claimedShortcuts.insert(entry.shortcut).inserted {
                failed.insert(action)
                continue
            }
            if let ref = register(shortcut: entry.shortcut, id: action.carbonID) {
                hotKeyRefs[action] = ref
            } else {
                failed.insert(action)
            }
        }
        failedActions = failed
    }

    private func register(shortcut: HotkeyShortcut, id: UInt32) -> EventHotKeyRef? {
        let hotKeyID = EventHotKeyID(signature: Self.hotKeySignature, id: id)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            shortcut.keyCode,
            Self.carbonModifiers(for: shortcut.modifiers),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        return status == noErr ? ref : nil
    }

    private func unregisterAllHotKeys() {
        for (_, ref) in hotKeyRefs {
            UnregisterEventHotKey(ref)
        }
        hotKeyRefs.removeAll()
    }

    private func installHandlerIfNeeded() {
        guard eventHandlerRef == nil else { return }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let userData = Unmanaged.passUnretained(self).toOpaque()
        let callback: EventHandlerUPP = { _, eventRef, userData in
            guard let eventRef, let userData else { return noErr }
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                eventRef,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )
            guard status == noErr, hotKeyID.signature == GlobalHotkeyService.hotKeySignature else {
                return noErr
            }
            let service = Unmanaged<GlobalHotkeyService>.fromOpaque(userData).takeUnretainedValue()
            let pressedID = hotKeyID.id
            MainActor.assumeIsolated {
                service.handleHotKey(id: pressedID)
            }
            return noErr
        }

        var handlerRef: EventHandlerRef?
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            callback,
            1,
            &eventType,
            userData,
            &handlerRef
        )
        if status == noErr {
            eventHandlerRef = handlerRef
        }
    }

    private func handleHotKey(id: UInt32) {
        guard !isPaused else { return }
        guard let action = GlobalHotkeyAction.allCases.first(where: { $0.carbonID == id }) else { return }
        switch action {
        case .quickTranslate:
            onQuickTranslate?()
        case .mainWindow:
            onMainWindow?()
        case .screenshotOCR:
            onScreenshotOCR?()
        case .selectionTranslate:
            onSelectionTranslate?()
        }
    }

    private static func carbonModifiers(for modifiers: HotkeyModifiers) -> UInt32 {
        var mask: UInt32 = 0
        if modifiers.contains(.command) { mask |= UInt32(cmdKey) }
        if modifiers.contains(.option)  { mask |= UInt32(optionKey) }
        if modifiers.contains(.control) { mask |= UInt32(controlKey) }
        if modifiers.contains(.shift)   { mask |= UInt32(shiftKey) }
        return mask
    }
}
