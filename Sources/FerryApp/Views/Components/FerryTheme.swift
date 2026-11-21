import AppKit
import FerryCore
import SwiftUI

/// Brand colors and the logo mark, shared by every window.
/// Colors come from Ferry's vibrant 青碧 lagoon palette: #1BD8BE → #0AA3B4.
enum FerryTheme {
    static let iconTop = Color(nsColor: NSColor(srgbRed: 0.106, green: 0.847, blue: 0.745, alpha: 1))    // #1BD8BE
    static let iconBottom = Color(nsColor: NSColor(srgbRed: 0.039, green: 0.639, blue: 0.706, alpha: 1)) // #0AA3B4

    /// Main tint (toggles, focus rings, selected states): crisp lagoon teal #0EB5B6.
    static let accent = Color(nsColor: NSColor(srgbRed: 0.055, green: 0.710, blue: 0.714, alpha: 1))

    /// Teal for small text and thin glyphs: deeper end in light mode (readable on white),
    /// brighter luminous mint in dark mode.
    static let accentText = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 0.169, green: 0.890, blue: 0.800, alpha: 1) // #2BE3CC
            : NSColor(srgbRed: 0.039, green: 0.561, blue: 0.627, alpha: 1) // #0A8FA0
    })

    /// Fill for primary buttons, matching the brand's clean top-to-bottom gradient.
    static let accentGradient = LinearGradient(
        colors: [
            Color(nsColor: NSColor(srgbRed: 0.106, green: 0.847, blue: 0.745, alpha: 1)),
            iconBottom
        ],
        startPoint: .top,
        endPoint: .bottom
    )

    /// Pop coral jib accent from the app icon, used sparingly for energetic highlights.
    static let coral = Color(nsColor: NSColor(srgbRed: 1.0, green: 0.443, blue: 0.349, alpha: 1))
    /// Subtle fill for chips and secondary buttons.
    static let chipFill = Color.primary.opacity(0.06)
}

/// The sailboat mark (same drawing as the menu bar icon), tinted with the brand color.
struct FerryLogo: View {
    var height: CGFloat = 16
    var color: Color = FerryTheme.accent
    @Environment(\.appLanguage) private var appLanguage

    var body: some View {
        let name = L10n(appLanguage).brandName
        Image(nsImage: MenuBarIcon.make(height: height, accessibilityDescription: name))
            .renderingMode(.template)
            .foregroundStyle(color)
            .accessibilityLabel(name)
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
