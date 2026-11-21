import AppKit
import ApplicationServices
import Carbon.HIToolbox
import Foundation
import FerryCore
import Observation

@MainActor
@Observable
public final class GlobalCopyMonitor {
    public var isAccessibilityTrusted: Bool = false
    public var isSuppressed: Bool = false
    public var onDoubleCopy: ((String, NSPoint, NSRunningApplication?) -> Void)?

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var isMonitoringActive: Bool = false
    private var detector = DoubleCopyDetector()
    private let settingsStore: SettingsStore
    private var pendingReadTask: Task<Void, Never>?
    private var activeAppObserver: NSObjectProtocol?
    private var axChangeObserver: NSObjectProtocol?
    private var deferredRefreshTask: Task<Void, Never>?

    public init(settingsStore: SettingsStore) {
        self.settingsStore = settingsStore
        self.isAccessibilityTrusted = Self.checkAccessibilityTrust(prompt: false)
        installPermissionObservers()
    }

    public static func checkAccessibilityTrust(prompt: Bool) -> Bool {
        if prompt {
            let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
            return AXIsProcessTrustedWithOptions(options)
        }
        return AXIsProcessTrusted()
    }

    public func requestAccessibilityPermission() {
        let wasTrusted = isAccessibilityTrusted
        let trusted = Self.checkAccessibilityTrust(prompt: true)
        isAccessibilityTrusted = trusted
        if trusted && isMonitoringActive && (!wasTrusted || globalMonitor == nil) {
            installMonitors(includeGlobal: true)
        }
    }

    public func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    public func refreshPermissionStatus() {
        let wasTrusted = isAccessibilityTrusted
        let trusted = Self.checkAccessibilityTrust(prompt: false)
        isAccessibilityTrusted = trusted

        if trusted {
            if isMonitoringActive && (!wasTrusted || globalMonitor == nil) {
                installMonitors(includeGlobal: true)
            }
        } else if let globalMonitor {
            // Remove inactive global monitor so it is recreated cleanly once permission is granted
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
    }

    public func startMonitoring() {
        isMonitoringActive = true
        let trusted = Self.checkAccessibilityTrust(prompt: false)
        isAccessibilityTrusted = trusted
        installMonitors(includeGlobal: trusted)
    }

    public func stopMonitoring() {
        isMonitoringActive = false
        removeMonitors()
        pendingReadTask?.cancel()
        pendingReadTask = nil
        deferredRefreshTask?.cancel()
        deferredRefreshTask = nil
    }

    private func installMonitors(includeGlobal: Bool) {
        removeMonitors()

        if includeGlobal {
            globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
                Task { @MainActor [weak self] in
                    self?.handleKeyEvent(event)
                }
            }
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKeyEvent(event)
            return event
        }
    }

    private func removeMonitors() {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
    }

    private func installPermissionObservers() {
        activeAppObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshPermissionStatus()
            }
        }

        axChangeObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.accessibility.api"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.schedulePermissionRefresh()
            }
        }
    }

    private func schedulePermissionRefresh() {
        refreshPermissionStatus()
        deferredRefreshTask?.cancel()
        deferredRefreshTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            self?.refreshPermissionStatus()
        }
    }

    private func handleKeyEvent(_ event: NSEvent) {
        guard settingsStore.settings.doubleCopyEnabled, !isSuppressed else { return }
        guard !event.isARepeat else { return }
        guard event.keyCode == UInt16(kVK_ANSI_C) else { return }

        // Require Command modifier without Option, Control, or Shift
        let relevantFlags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        guard relevantFlags == .command else { return }

        detector.maxInterval = Double(settingsStore.settings.doubleCopyIntervalMs) / 1000.0
        let now = ProcessInfo.processInfo.systemUptime
        guard detector.registerPress(at: now) else { return }

        let mouseLocation = NSEvent.mouseLocation
        let frontmost = NSWorkspace.shared.frontmostApplication
        let sourceApp = (frontmost?.processIdentifier == ProcessInfo.processInfo.processIdentifier) ? nil : frontmost

        pendingReadTask?.cancel()
        pendingReadTask = Task { [weak self] in
            // Wait briefly for the frontmost app to finish writing the copied string to NSPasteboard
            try? await Task.sleep(for: .milliseconds(90))
            guard !Task.isCancelled else { return }
            guard let text = NSPasteboard.general.string(forType: .string)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                  !text.isEmpty
            else {
                return
            }
            self?.onDoubleCopy?(text, mouseLocation, sourceApp)
        }
    }
}
