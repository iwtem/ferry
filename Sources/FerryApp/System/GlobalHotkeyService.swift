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
    public var registrationFailed: Bool = false

    private var eventHandlerRef: EventHandlerRef?
    private var screenshotHotKeyRef: EventHotKeyRef?
    private var activeShortcut: HotkeyShortcut?
    private var isEnabled: Bool = false
    private var isPaused: Bool = false
    private var settingsObserver: NSObjectProtocol?
    private weak var settingsStore: SettingsStore?

    private static let hotKeySignature: OSType = 0x46525259 // 'FRRY'
    private static let screenshotHotKeyID: UInt32 = 1

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
        unregisterScreenshotHotKey()
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
        }
    }

    /// Temporarily unregisters active hotkeys while the user records a new shortcut in Settings,
    /// so pressing the current shortcut is captured by the recorder instead of triggering capture.
    public func setPaused(_ paused: Bool) {
        guard isPaused != paused else { return }
        isPaused = paused
        applyRegistration()
    }

    public func sync(with settings: AppSettings) {
        isEnabled = settings.screenshotOCREnabled
        activeShortcut = settings.screenshotOCRShortcut
        applyRegistration()
    }

    private func applyRegistration() {
        unregisterScreenshotHotKey()
        registrationFailed = false

        guard isEnabled, !isPaused, let shortcut = activeShortcut, shortcut.isValid else {
            return
        }

        let hotKeyID = EventHotKeyID(signature: Self.hotKeySignature, id: Self.screenshotHotKeyID)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            shortcut.keyCode,
            Self.carbonModifiers(for: shortcut.modifiers),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )

        if status == noErr, let ref {
            screenshotHotKeyRef = ref
            registrationFailed = false
        } else {
            screenshotHotKeyRef = nil
            registrationFailed = true
        }
    }

    private func unregisterScreenshotHotKey() {
        if let ref = screenshotHotKeyRef {
            UnregisterEventHotKey(ref)
            screenshotHotKeyRef = nil
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
        if id == Self.screenshotHotKeyID {
            onScreenshotOCR?()
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
