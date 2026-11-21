import AppKit
import Carbon.HIToolbox
import FerryCore
import Foundation
import Observation

/// Registers global macOS hotkeys via Carbon `RegisterEventHotKey` (works without Accessibility permission).
@MainActor
@Observable
public final class GlobalHotkeyService {
    public var onScreenshotOCR: (() -> Void)?
    public var onSelectionTranslate: (() -> Void)?

    public var screenshotRegistrationFailed: Bool = false
    public var selectionRegistrationFailed: Bool = false

    public var registrationFailed: Bool {
        screenshotRegistrationFailed || selectionRegistrationFailed
    }

    private var eventHandlerRef: EventHandlerRef?
    private var screenshotHotKeyRef: EventHotKeyRef?
    private var selectionHotKeyRef: EventHotKeyRef?

    private var screenshotEnabled: Bool = false
    private var screenshotShortcut: HotkeyShortcut?
    private var selectionEnabled: Bool = false
    private var selectionShortcut: HotkeyShortcut?

    private var isPaused: Bool = false
    private var settingsObserver: NSObjectProtocol?
    private weak var settingsStore: SettingsStore?

    private static let hotKeySignature: OSType = 0x46525259 // 'FRRY'
    private static let screenshotHotKeyID: UInt32 = 1
    private static let selectionHotKeyID: UInt32 = 2

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
        screenshotEnabled = settings.screenshotOCREnabled
        screenshotShortcut = settings.screenshotOCRShortcut
        selectionEnabled = settings.selectionShortcutEnabled
        selectionShortcut = settings.selectionShortcut
        applyRegistrations()
    }

    private func applyRegistrations() {
        unregisterAllHotKeys()
        screenshotRegistrationFailed = false
        selectionRegistrationFailed = false

        guard !isPaused else { return }

        if screenshotEnabled, let shortcut = screenshotShortcut, shortcut.isValid {
            if let ref = register(shortcut: shortcut, id: Self.screenshotHotKeyID) {
                screenshotHotKeyRef = ref
            } else {
                screenshotRegistrationFailed = true
            }
        }

        if selectionEnabled, let shortcut = selectionShortcut, shortcut.isValid {
            if let ref = register(shortcut: shortcut, id: Self.selectionHotKeyID) {
                selectionHotKeyRef = ref
            } else {
                selectionRegistrationFailed = true
            }
        }
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
        if let ref = screenshotHotKeyRef {
            UnregisterEventHotKey(ref)
            screenshotHotKeyRef = nil
        }
        if let ref = selectionHotKeyRef {
            UnregisterEventHotKey(ref)
            selectionHotKeyRef = nil
        }
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
        switch id {
        case Self.screenshotHotKeyID:
            onScreenshotOCR?()
        case Self.selectionHotKeyID:
            onSelectionTranslate?()
        default:
            break
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
