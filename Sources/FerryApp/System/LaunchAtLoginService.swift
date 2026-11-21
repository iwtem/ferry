import AppKit
import FerryCore
import Observation
import ServiceManagement

/// Manages the macOS Launch at Login item via `SMAppService.mainApp` (macOS 13+).
@MainActor
@Observable
public final class LaunchAtLoginService {
    public private(set) var isEnabled: Bool = false
    public private(set) var requiresApproval: Bool = false
    public private(set) var lastErrorMessage: String? = nil

    public var isRunningFromAppBundle: Bool {
        Bundle.main.bundleURL.pathExtension.lowercased() == "app"
    }

    private var activeAppObserver: NSObjectProtocol?

    public init() {
        refreshStatus()
        activeAppObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshStatus()
            }
        }
    }

    public func stopObserving() {
        if let activeAppObserver {
            NotificationCenter.default.removeObserver(activeAppObserver)
            self.activeAppObserver = nil
        }
    }

    public func refreshStatus() {
        guard isRunningFromAppBundle else {
            isEnabled = false
            requiresApproval = false
            return
        }
        let status = SMAppService.mainApp.status
        isEnabled = (status == .enabled || status == .requiresApproval)
        requiresApproval = (status == .requiresApproval)
    }

    public func setEnabled(_ enabled: Bool) {
        lastErrorMessage = nil
        let l10n = L10n()

        guard isRunningFromAppBundle else {
            isEnabled = false
            requiresApproval = false
            lastErrorMessage = l10n.launchAtLoginRequiresAppBundle
            return
        }

        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            lastErrorMessage = l10n.launchAtLoginFailed(error.localizedDescription)
        }

        refreshStatus()
    }

    public func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
