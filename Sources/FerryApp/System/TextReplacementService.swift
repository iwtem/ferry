import AppKit
import ApplicationServices
import Carbon.HIToolbox
import FerryCore
import Foundation

public enum TextReplacementError: LocalizedError, Equatable, Sendable {
    case accessibilityRequired
    case emptyText
    case noSelectionFound
    case pasteEventFailed

    public var errorDescription: String? {
        let lang = FerryLocalization.resolved
        switch self {
        case .accessibilityRequired:
            return FerryLocalization.text(
                zh: "一键替换原文需要授予「辅助功能」权限。",
                en: "Replacing text in another app requires Accessibility permission.",
                in: lang
            )
        case .emptyText:
            return FerryLocalization.text(
                zh: "没有可替换的译文内容。",
                en: "There is no output text to insert.",
                in: lang
            )
        case .noSelectionFound:
            return FerryLocalization.text(
                zh: "未检测到选中的文字，请先在输入框中选中内容再按快捷键。",
                en: "No selected text detected. Highlight text first before pressing the shortcut.",
                in: lang
            )
        case .pasteEventFailed:
            return FerryLocalization.text(
                zh: "无法向目标应用发送粘贴指令。",
                en: "Could not send paste command to the target app.",
                in: lang
            )
        }
    }
}

/// Captures selected text from the active app and replaces it back in place via clipboard-preserving ⌘C / ⌘V.
@MainActor
public final class TextReplacementService {
    public struct CapturedSelection {
        public let text: String
        public let sourceApp: NSRunningApplication?
        public let mouseLocation: NSPoint
    }

    private struct ClipboardSnapshot {
        let items: [[NSPasteboard.PasteboardType: Data]]

        static func capture(from pasteboard: NSPasteboard) -> ClipboardSnapshot {
            let captured: [[NSPasteboard.PasteboardType: Data]] = (pasteboard.pasteboardItems ?? []).compactMap { item in
                var map: [NSPasteboard.PasteboardType: Data] = [:]
                for type in item.types {
                    if let data = item.data(forType: type) {
                        map[type] = data
                    }
                }
                return map.isEmpty ? nil : map
            }
            return ClipboardSnapshot(items: captured)
        }

        func restore(to pasteboard: NSPasteboard) {
            pasteboard.clearContents()
            guard !items.isEmpty else { return }
            let restoredItems: [NSPasteboardItem] = items.map { map in
                let pbItem = NSPasteboardItem()
                for (type, data) in map {
                    pbItem.setData(data, forType: type)
                }
                return pbItem
            }
            pasteboard.writeObjects(restoredItems)
        }
    }

    public init() {}

    /// Reads the currently selected text from the frontmost app without permanently disturbing the user's clipboard.
    public func captureSelection(copyMonitor: GlobalCopyMonitor?) async throws -> CapturedSelection {
        let mouseLocation = NSEvent.mouseLocation
        let frontmost = NSWorkspace.shared.frontmostApplication
        let sourceApp = (frontmost?.processIdentifier == ProcessInfo.processInfo.processIdentifier) ? nil : frontmost

        guard AXIsProcessTrusted() else {
            throw TextReplacementError.accessibilityRequired
        }

        // Fast path: try Accessibility AXSelectedText directly (zero clipboard impact).
        if let axText = Self.readFocusedAXSelectedText(),
           !axText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return CapturedSelection(text: axText, sourceApp: sourceApp, mouseLocation: mouseLocation)
        }

        // Fallback for Electron / Chrome / Slack / VS Code: temporary clipboard-preserving ⌘C.
        let pasteboard = NSPasteboard.general
        let snapshot = ClipboardSnapshot.capture(from: pasteboard)
        let baselineChangeCount = pasteboard.changeCount

        copyMonitor?.isSuppressed = true
        defer { copyMonitor?.isSuppressed = false }

        guard Self.postCommandKey(virtualKey: CGKeyCode(kVK_ANSI_C)) else {
            throw TextReplacementError.noSelectionFound
        }

        // Poll up to 220ms for the frontmost app to update the pasteboard.
        var didUpdate = false
        for _ in 0..<11 {
            try? await Task.sleep(for: .milliseconds(20))
            if pasteboard.changeCount != baselineChangeCount {
                didUpdate = true
                break
            }
        }

        let capturedText = didUpdate
            ? pasteboard.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines)
            : nil

        // Always restore the user's original clipboard right away.
        snapshot.restore(to: pasteboard)

        guard let text = capturedText, !text.isEmpty else {
            throw TextReplacementError.noSelectionFound
        }

        return CapturedSelection(text: text, sourceApp: sourceApp, mouseLocation: mouseLocation)
    }

    /// Replaces the active selection in `targetApp` with `text` by pasting via ⌘V and restoring the user's clipboard.
    public func replaceSelection(with text: String, in targetApp: NSRunningApplication?) async throws {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw TextReplacementError.emptyText
        }
        guard AXIsProcessTrusted() else {
            throw TextReplacementError.accessibilityRequired
        }

        let pasteboard = NSPasteboard.general
        let snapshot = ClipboardSnapshot.capture(from: pasteboard)

        // Ensure target app has focus before sending ⌘V.
        if let targetApp,
           !targetApp.isTerminated,
           NSWorkspace.shared.frontmostApplication?.processIdentifier != targetApp.processIdentifier {
            targetApp.activate()
            try? await Task.sleep(for: .milliseconds(120))
        } else {
            // Brief yield so any closing floating panel finishes ordering out.
            try? await Task.sleep(for: .milliseconds(50))
        }

        pasteboard.clearContents()
        pasteboard.setString(trimmed, forType: .string)
        let pastedChangeCount = pasteboard.changeCount

        guard Self.postCommandKey(virtualKey: CGKeyCode(kVK_ANSI_V)) else {
            snapshot.restore(to: pasteboard)
            throw TextReplacementError.pasteEventFailed
        }

        // Wait briefly for the target app to consume the pasteboard, then restore if untouched.
        try? await Task.sleep(for: .milliseconds(220))
        if pasteboard.changeCount == pastedChangeCount {
            snapshot.restore(to: pasteboard)
        }
    }

    // MARK: - Accessibility & Synthetic Key Events

    private static func readFocusedAXSelectedText() -> String? {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
              let focusedElement = focusedRef
        else {
            return nil
        }
        // swiftlint:disable:next force_cast
        let axElement = focusedElement as! AXUIElement
        var selectedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axElement, kAXSelectedTextAttribute as CFString, &selectedRef) == .success,
              let selected = selectedRef as? String
        else {
            return nil
        }
        return selected
    }

    private static func postCommandKey(virtualKey: CGKeyCode) -> Bool {
        guard let source = CGEventSource(stateID: .combinedSessionState),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: virtualKey, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: virtualKey, keyDown: false)
        else {
            return false
        }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
        return true
    }
}
