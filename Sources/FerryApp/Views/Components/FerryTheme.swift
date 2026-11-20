import AppKit
import FerryCore
import SwiftUI

/// Brand colors and the logo mark, shared by every window.
/// Colors come straight from the 青碧 app icon: its background runs #3FD6C6 → #0F97A8.
enum FerryTheme {
    static let iconTop = Color(nsColor: NSColor(srgbRed: 0.247, green: 0.839, blue: 0.776, alpha: 1))    // #3FD6C6
    static let iconBottom = Color(nsColor: NSColor(srgbRed: 0.059, green: 0.592, blue: 0.659, alpha: 1)) // #0F97A8

    /// Main tint (toggles, focus rings, selected icons): the icon's mid-tone, #1FB3B5.
    static let accent = Color(nsColor: NSColor(srgbRed: 0.122, green: 0.702, blue: 0.710, alpha: 1))

    /// Teal for small text and thin glyphs: the icon's deeper end in light mode (readable on white),
    /// its brighter end in dark mode.
    static let accentText = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 0.247, green: 0.839, blue: 0.776, alpha: 1)
            : NSColor(srgbRed: 0.059, green: 0.592, blue: 0.659, alpha: 1)
    })

    /// Fill for primary buttons, matching the icon's top-to-bottom gradient.
    static let accentGradient = LinearGradient(
        colors: [
            Color(nsColor: NSColor(srgbRed: 0.18, green: 0.77, blue: 0.75, alpha: 1)),
            iconBottom
        ],
        startPoint: .top,
        endPoint: .bottom
    )

    /// Coral jib color from the icon, used sparingly for highlights.
    static let coral = Color(nsColor: NSColor(srgbRed: 1.0, green: 0.541, blue: 0.357, alpha: 1))
    /// Subtle fill for chips and secondary buttons.
    static let chipFill = Color.primary.opacity(0.06)
}

/// The sailboat mark (same drawing as the menu bar icon), tinted with the brand color.
struct FerryLogo: View {
    var height: CGFloat = 16
    var color: Color = FerryTheme.accent

    var body: some View {
        Image(nsImage: MenuBarIcon.make(height: height, accessibilityDescription: "渡 Ferry"))
            .renderingMode(.template)
            .foregroundStyle(color)
            .accessibilityLabel("渡 Ferry")
    }
}

/// Borderless icon button used in toolbars and headers.
struct IconButton: View {
    let systemName: String
    let help: String
    var isOn: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
        }
        .buttonStyle(HoverIconButtonStyle(isOn: isOn))
        .help(help)
        .accessibilityLabel(help)
    }
}

/// Applies the 外观 setting app-wide; every window, panel and menu follows `NSApp.appearance`.
@MainActor
enum FerryAppearance {
    static func apply(_ mode: AppearanceMode) {
        switch mode {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }
}
