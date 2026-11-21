import Foundation

/// Modifier keys used in global hotkeys (stored as a portable bitmask in settings).
public struct HotkeyModifiers: OptionSet, Codable, Equatable, Hashable, Sendable {
    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    public static let control = HotkeyModifiers(rawValue: 1 << 0)
    public static let option  = HotkeyModifiers(rawValue: 1 << 1)
    public static let shift   = HotkeyModifiers(rawValue: 1 << 2)
    public static let command = HotkeyModifiers(rawValue: 1 << 3)

    /// At least one non-Shift modifier is required so shortcuts never hijack normal typing.
    public var hasPrimaryModifier: Bool {
        contains(.command) || contains(.option) || contains(.control)
    }

    /// Standard macOS symbol order: ⌃ ⌥ ⇧ ⌘
    public var symbols: [String] {
        var result: [String] = []
        if contains(.control) { result.append("⌃") }
        if contains(.option)  { result.append("⌥") }
        if contains(.shift)   { result.append("⇧") }
        if contains(.command) { result.append("⌘") }
        return result
    }
}

/// Configurable global keyboard shortcut (virtual key code + modifiers).
public struct HotkeyShortcut: Codable, Equatable, Hashable, Sendable {
    public var keyCode: UInt32
    public var modifiers: HotkeyModifiers

    public init(keyCode: UInt32, modifiers: HotkeyModifiers) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// Default screenshot OCR shortcut: ⌥⇧S (virtual keyCode 1 = ANSI S).
    public static let defaultScreenshotOCR = HotkeyShortcut(
        keyCode: 1,
        modifiers: [.option, .shift]
    )

    public var isValid: Bool {
        modifiers.hasPrimaryModifier && Self.keyLabel(for: keyCode) != nil
    }

    public var keyLabel: String {
        Self.keyLabel(for: keyCode) ?? "Key \(keyCode)"
    }

    /// Keycap tokens in display order, e.g. `["⌥", "⇧", "S"]`.
    public var displayTokens: [String] {
        modifiers.symbols + [keyLabel]
    }

    /// Compact representation, e.g. `"⌥⇧S"`.
    public var displayString: String {
        displayTokens.joined()
    }

    /// Maps standard macOS virtual key codes (HIToolbox Events.h) to concise keycap labels.
    public static func keyLabel(for keyCode: UInt32) -> String? {
        keyLabels[keyCode]
    }

    private static let keyLabels: [UInt32: String] = [
        // ANSI letters
        0: "A", 11: "B", 8: "C", 2: "D", 14: "E", 3: "F", 5: "G",
        4: "H", 34: "I", 38: "J", 40: "K", 37: "L", 46: "M", 45: "N",
        31: "O", 35: "P", 12: "Q", 15: "R", 1: "S", 17: "T", 32: "U",
        9: "V", 13: "W", 7: "X", 16: "Y", 6: "Z",
        // ANSI numbers
        29: "0", 18: "1", 19: "2", 20: "3", 21: "4",
        23: "5", 22: "6", 26: "7", 28: "8", 25: "9",
        // Punctuation & symbols
        27: "-", 24: "=", 33: "[", 30: "]", 42: "\\",
        41: ";", 39: "'", 43: ",", 47: ".", 44: "/", 50: "`",
        // Common non-character keys
        49: "Space", 36: "↩", 48: "⇥", 51: "⌫",
        123: "←", 124: "→", 125: "↓", 126: "↑",
        // Function keys
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
        98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12"
    ]
}
