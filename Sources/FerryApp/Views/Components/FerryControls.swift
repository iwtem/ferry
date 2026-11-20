import AppKit
import SwiftUI

// Custom controls with hover / press / focus feedback, used by the settings page and the
// translation windows. All animations are short (≤ 0.2s) and respect Reduce Motion.

enum FerryMotion {
    static let quick = Animation.easeOut(duration: 0.15)
    static let spring = Animation.spring(response: 0.32, dampingFraction: 0.82)

    static func animation(_ animation: Animation) -> Animation? {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? nil : animation
    }
}

// MARK: - Buttons

struct FerryButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, subtle, destructive }
    var kind: Kind = .secondary
    var compact: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        FerryButtonBody(configuration: configuration, kind: kind, compact: compact)
    }
}

private struct FerryButtonBody: View {
    let configuration: ButtonStyle.Configuration
    let kind: FerryButtonStyle.Kind
    let compact: Bool
    @Environment(\.isEnabled) private var isEnabled
    @ViewState private var hovering = false

    var body: some View {
        configuration.label
            .font(.system(size: compact ? 12 : 13, weight: kind == .primary ? .semibold : .medium))
            .foregroundStyle(foreground)
            .padding(.horizontal, compact ? 10 : 14)
            .padding(.vertical, compact ? 4 : 6)
            .background(background)
            .overlay(
                RoundedRectangle(cornerRadius: compact ? 7 : 8, style: .continuous)
                    .strokeBorder(kind == .secondary ? Color.primary.opacity(hovering ? 0.16 : 0.1) : .clear)
            )
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(isEnabled ? 1 : 0.45)
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .onHover { hovering = $0 && isEnabled }
            .animation(FerryMotion.animation(FerryMotion.quick), value: hovering)
            .animation(FerryMotion.animation(FerryMotion.quick), value: configuration.isPressed)
    }

    private var foreground: Color {
        switch kind {
        case .primary: return .white
        case .secondary: return .primary
        case .subtle: return hovering ? FerryTheme.accentText : .secondary
        case .destructive: return .red
        }
    }

    @ViewBuilder
    private var background: some View {
        if kind == .primary {
            RoundedRectangle(cornerRadius: compact ? 7 : 8, style: .continuous)
                .fill(FerryTheme.accentGradient)
                .brightness(configuration.isPressed ? -0.06 : (hovering ? 0.04 : 0))
                .shadow(color: FerryTheme.iconBottom.opacity(hovering ? 0.35 : 0.2), radius: hovering ? 5 : 3, y: 1)
        } else {
            RoundedRectangle(cornerRadius: compact ? 7 : 8, style: .continuous)
                .fill(flatBackground)
        }
    }

    private var flatBackground: Color {
        switch kind {
        case .primary:
            return .clear
        case .secondary:
            return Color.primary.opacity(hovering ? 0.12 : 0.07)
        case .subtle:
            return hovering ? FerryTheme.accent.opacity(0.1) : .clear
        case .destructive:
            return Color.red.opacity(hovering ? 0.16 : 0.1)
        }
    }
}

/// A round icon button with hover fill and press feedback.
struct HoverIconButtonStyle: ButtonStyle {
    var isOn: Bool = false
    var size: CGFloat = 28

    func makeBody(configuration: Configuration) -> some View {
        HoverIconBody(configuration: configuration, isOn: isOn, size: size)
    }
}

private struct HoverIconBody: View {
    let configuration: ButtonStyle.Configuration
    let isOn: Bool
    let size: CGFloat
    @Environment(\.isEnabled) private var isEnabled
    @ViewState private var hovering = false

    var body: some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(isOn ? FerryTheme.accentText : (hovering ? Color.primary : Color.secondary))
            .frame(width: size, height: size - 2)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isOn ? FerryTheme.accent.opacity(0.14) : Color.primary.opacity(hovering ? 0.08 : 0))
            )
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .opacity(isEnabled ? 1 : 0.4)
            .contentShape(Rectangle())
            .onHover { hovering = $0 && isEnabled }
            .animation(FerryMotion.animation(FerryMotion.quick), value: hovering)
            .animation(FerryMotion.animation(FerryMotion.quick), value: configuration.isPressed)
            .animation(FerryMotion.animation(FerryMotion.quick), value: isOn)
    }
}

// MARK: - Panel surfaces

/// Card inside the small floating panels (menu bar popover, quick popup).
struct PanelCardSurface: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            )
    }
}

struct PressScaleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(FerryMotion.animation(FerryMotion.quick), value: configuration.isPressed)
    }
}

/// Inline status message that slides in.
struct StatusLine: View {
    let text: String
    let success: Bool

    var body: some View {
        Label(text, systemImage: success ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
            .font(.system(size: 12))
            .foregroundStyle(success ? Color.green : Color.red)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .transition(.opacity.combined(with: .move(edge: .top)))
    }
}

/// Clockwise arrow that spins while `active`.
struct SpinningRefreshIcon: View {
    let active: Bool
    @ViewState private var angle: Double = 0

    var body: some View {
        Image(systemName: "arrow.clockwise")
            .rotationEffect(.degrees(angle))
            .onChange(of: active, initial: true) { _, isActive in
                if isActive {
                    withAnimation(FerryMotion.animation(.linear(duration: 0.8).repeatForever(autoreverses: false))) {
                        angle = 360
                    }
                } else {
                    withAnimation(FerryMotion.animation(FerryMotion.quick)) {
                        angle = 0
                    }
                }
            }
    }
}

// MARK: - Window dragging

/// Transparent AppKit view that lets the user drag the window from empty areas of a SwiftUI
/// header. SwiftUI's hosting view swallows mouse-downs, so `isMovableByWindowBackground`
/// alone doesn't work for borderless panels.
struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class DragView: NSView {
        override var mouseDownCanMoveWindow: Bool { true }

        override func mouseDown(with event: NSEvent) {
            window?.performDrag(with: event)
        }

        override func resetCursorRects() {
            addCursorRect(bounds, cursor: .openHand)
        }
    }
}
