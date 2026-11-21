import AppKit
import SwiftUI

public final class KeyableFloatingPanel: NSPanel {
    public var onEscape: (() -> Void)?

    public override var canBecomeKey: Bool { true }
    public override var canBecomeMain: Bool { false }

    public override func cancelOperation(_ sender: Any?) {
        onEscape?()
    }

    public override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Escape
            onEscape?()
            return
        }
        super.keyDown(with: event)
    }
}

@MainActor
public final class QuickPopupController {
    private var panel: KeyableFloatingPanel?
    private var globalClickMonitor: Any?
    private var localClickMonitor: Any?
    public var isPinned: Bool = false

    public init() {}

    public func show<Content: View>(
        near mousePoint: NSPoint,
        size: NSSize = NSSize(width: 404, height: 300),
        @ViewBuilder content: () -> Content
    ) {
        let hostingView = NSHostingView(rootView: content())
        hostingView.translatesAutoresizingMaskIntoConstraints = false

        let targetPanel: KeyableFloatingPanel
        if let existing = panel {
            targetPanel = existing
            targetPanel.contentView = hostingView
        } else {
            let newPanel = KeyableFloatingPanel(
                contentRect: NSRect(origin: .zero, size: size),
                styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            newPanel.isFloatingPanel = true
            newPanel.level = .floating
            newPanel.backgroundColor = .clear
            newPanel.isOpaque = false
            newPanel.hasShadow = true
            newPanel.isMovableByWindowBackground = true
            newPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
            newPanel.hidesOnDeactivate = false
            newPanel.contentView = hostingView
            newPanel.onEscape = { [weak self] in
                self?.hide()
            }
            panel = newPanel
            targetPanel = newPanel
        }

        if !isPinned || !targetPanel.isVisible {
            let frame = Self.clampedFrame(near: mousePoint, size: size)
            targetPanel.setFrame(frame, display: true)
        }
        targetPanel.orderFrontRegardless()
        installDismissMonitors()
    }

    public func hide() {
        removeDismissMonitors()
        isPinned = false
        panel?.orderOut(nil)
    }

    private func installDismissMonitors() {
        removeDismissMonitors()

        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.dismissIfClickedOutside()
            }
        }

        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            self?.dismissIfClickedOutside()
            return event
        }
    }

    private func removeDismissMonitors() {
        if let globalClickMonitor {
            NSEvent.removeMonitor(globalClickMonitor)
            self.globalClickMonitor = nil
        }
        if let localClickMonitor {
            NSEvent.removeMonitor(localClickMonitor)
            self.localClickMonitor = nil
        }
    }

    private func dismissIfClickedOutside() {
        guard !isPinned, let panel, panel.isVisible else { return }
        let clickPoint = NSEvent.mouseLocation
        if !panel.frame.contains(clickPoint) {
            hide()
        }
    }

    private static func clampedFrame(near mousePoint: NSPoint, size: NSSize) -> NSRect {
        let targetScreen = NSScreen.screens.first(where: { $0.frame.contains(mousePoint) }) ?? NSScreen.main
        let visible = targetScreen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let padding: CGFloat = 14

        // Prefer slightly to the right and below cursor; flip if near screen edge
        var x = mousePoint.x + 14
        var y = mousePoint.y - size.height - 14

        if x + size.width + padding > visible.maxX {
            x = mousePoint.x - size.width - 14
        }
        if x < visible.minX + padding {
            x = visible.minX + padding
        }
        if x + size.width > visible.maxX - padding {
            x = visible.maxX - size.width - padding
        }

        if y < visible.minY + padding {
            y = mousePoint.y + 18
        }
        if y + size.height > visible.maxY - padding {
            y = visible.maxY - size.height - padding
        }
        if y < visible.minY + padding {
            y = visible.minY + padding
        }

        return NSRect(x: x, y: y, width: size.width, height: size.height)
    }
}

/// Arrow-less dropdown panel under the menu bar icon (replaces NSPopover).
/// Closes on Esc, on a click outside, or when another app becomes active.
@MainActor
public final class MenuBarPanelController {
    private var panel: KeyableFloatingPanel?
    private var hostingView: NSHostingView<AnyView>?
    private var globalClickMonitor: Any?
    private var resignObserver: NSObjectProtocol?
    /// When the panel last closed. A click on the menu bar icon first closes the panel
    /// (mouse-down counts as an outside click), then fires the icon's action on mouse-up;
    /// without this the same click would reopen it.
    private var lastHide = Date.distantPast
    public var onHide: (() -> Void)?

    public var isVisible: Bool { panel?.isVisible ?? false }

    public init() {}

    /// Click on the menu bar icon: close if open (or just closed by this click), else open.
    public func toggle(below button: NSStatusBarButton, content: () -> AnyView) {
        if isVisible {
            hide()
        } else if Date().timeIntervalSince(lastHide) > 0.3 {
            show(below: button, content: content())
        }
    }

    /// Keeps the top edge pinned under the menu bar while the content grows or shrinks.
    public func resize(toHeight height: CGFloat) {
        guard let panel, height > 0, abs(panel.frame.height - height) > 0.5 else { return }
        var frame = panel.frame
        frame.origin.y = frame.maxY - height
        frame.size.height = height
        panel.setFrame(frame, display: true)
        panel.invalidateShadow()
    }

    public func show(below button: NSStatusBarButton, content: AnyView) {
        let panel = self.panel ?? makePanel()
        if let hostingView {
            hostingView.rootView = content
        } else {
            let view = NSHostingView(rootView: content)
            panel.contentView = view
            hostingView = view
        }

        let size = hostingView?.fittingSize ?? NSSize(width: 368, height: 440)
        panel.setFrame(frame(for: size, below: button), display: true)
        panel.makeKeyAndOrderFront(nil)
        panel.invalidateShadow()
        NSApp.activate(ignoringOtherApps: true)
        installMonitors(anchor: button)

        DispatchQueue.main.async { [weak panel] in
            guard let panel, let textView = Self.firstTextView(in: panel.contentView) else { return }
            panel.makeFirstResponder(textView)
        }
    }

    public func hide() {
        guard let panel, panel.isVisible else { return }
        removeMonitors()
        panel.orderOut(nil)
        lastHide = Date()
        onHide?()
    }

    private func makePanel() -> KeyableFloatingPanel {
        let newPanel = KeyableFloatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: 368, height: 440),
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        newPanel.isFloatingPanel = true
        newPanel.level = .popUpMenu
        newPanel.backgroundColor = .clear
        newPanel.isOpaque = false
        newPanel.hasShadow = true
        newPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        newPanel.hidesOnDeactivate = false
        newPanel.onEscape = { [weak self] in self?.hide() }
        panel = newPanel
        return newPanel
    }

    /// Centered under the status item, 6pt below the menu bar, kept on screen.
    private func frame(for size: NSSize, below button: NSStatusBarButton) -> NSRect {
        guard let buttonWindow = button.window else {
            return NSRect(origin: .zero, size: size)
        }
        let anchor = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let screen = buttonWindow.screen ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        var x = anchor.midX - size.width / 2
        x = min(max(x, visible.minX + 8), visible.maxX - size.width - 8)
        let y = min(anchor.minY, visible.maxY) - size.height - 6
        return NSRect(x: x, y: y, width: size.width, height: size.height)
    }

    private func installMonitors(anchor button: NSStatusBarButton) {
        removeMonitors()
        // Clicks in other apps. Clicks on our own status item are handled by its toggle.
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor [weak self] in self?.hide() }
        }
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.hide() }
        }
    }

    private func removeMonitors() {
        if let globalClickMonitor {
            NSEvent.removeMonitor(globalClickMonitor)
            self.globalClickMonitor = nil
        }
        if let resignObserver {
            NotificationCenter.default.removeObserver(resignObserver)
            self.resignObserver = nil
        }
    }

    private static func firstTextView(in view: NSView?) -> NSTextView? {
        guard let view else { return nil }
        if let textView = view as? NSTextView, textView.isEditable { return textView }
        for subview in view.subviews {
            if let found = firstTextView(in: subview) { return found }
        }
        return nil
    }
}

@MainActor
public final class DesktopMiniWidgetController {
    private var panel: KeyableFloatingPanel?
    private let frameOriginXKey = "Ferry.DesktopWidgetOriginX"
    private let frameOriginYKey = "Ferry.DesktopWidgetOriginY"
    private var moveObserver: NSObjectProtocol?

    public var isVisible: Bool {
        panel?.isVisible ?? false
    }

    public init() {}

    public func toggle<Content: View>(
        alwaysOnTop: Bool,
        @ViewBuilder content: () -> Content
    ) {
        if isVisible {
            hide()
        } else {
            show(alwaysOnTop: alwaysOnTop, content: content)
        }
    }

    public func show<Content: View>(
        alwaysOnTop: Bool,
        @ViewBuilder content: () -> Content
    ) {
        let size = NSSize(width: 320, height: 270)
        let hostingView = NSHostingView(rootView: content())

        if let existing = panel {
            existing.contentView = hostingView
            existing.level = alwaysOnTop ? .floating : .normal
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let origin = savedOrigin(for: size)
        let newPanel = KeyableFloatingPanel(
            contentRect: NSRect(origin: origin, size: size),
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        newPanel.isFloatingPanel = true
        newPanel.level = alwaysOnTop ? .floating : .normal
        newPanel.backgroundColor = .clear
        newPanel.isOpaque = false
        newPanel.hasShadow = true
        newPanel.isMovableByWindowBackground = true
        newPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        newPanel.hidesOnDeactivate = false
        newPanel.contentView = hostingView
        newPanel.onEscape = { [weak self] in
            self?.hide()
        }

        moveObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: newPanel,
            queue: .main
        ) { [weak self, weak newPanel] _ in
            Task { @MainActor [weak self, weak newPanel] in
                guard let origin = newPanel?.frame.origin else { return }
                self?.saveOrigin(origin)
            }
        }

        panel = newPanel
        newPanel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    public func setAlwaysOnTop(_ alwaysOnTop: Bool) {
        panel?.level = alwaysOnTop ? .floating : .normal
    }

    public func hide() {
        panel?.orderOut(nil)
    }

    private func savedOrigin(for size: NSSize) -> NSPoint {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: frameOriginXKey) != nil,
           defaults.object(forKey: frameOriginYKey) != nil {
            let saved = NSPoint(
                x: defaults.double(forKey: frameOriginXKey),
                y: defaults.double(forKey: frameOriginYKey)
            )
            // Ensure saved point is visible on at least one connected screen
            if NSScreen.screens.contains(where: { $0.visibleFrame.intersects(NSRect(origin: saved, size: size)) }) {
                return saved
            }
        }

        let visible = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        return NSPoint(
            x: visible.maxX - size.width - 28,
            y: visible.maxY - size.height - 40
        )
    }

    private func saveOrigin(_ origin: NSPoint) {
        UserDefaults.standard.set(origin.x, forKey: frameOriginXKey)
        UserDefaults.standard.set(origin.y, forKey: frameOriginYKey)
    }
}
