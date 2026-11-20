import AppKit
import SwiftUI

// Ferry's window look ("stage"): a soft gradient lit by a colored glow, with frosted glass
// cards on top. Every token below has a light and a dark value and follows the effective
// appearance (system, or the override chosen in 设置 → 通用 → 外观).

// MARK: - Color helpers

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }

    static func adaptive(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: .adaptive(light: light, dark: dark))
    }
}

extension NSColor {
    static func adaptive(light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        }
    }

    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}

private func white(_ alpha: CGFloat) -> NSColor { NSColor(white: 1, alpha: alpha) }
private func black(_ alpha: CGFloat) -> NSColor { NSColor(white: 0, alpha: alpha) }

// MARK: - Hues

/// A two-stop color pair. Each settings pane and the main window has its own hue,
/// which tints the backdrop glow, the hero orb and primary buttons.
struct StageHue: Equatable {
    let top: Color
    let bottom: Color

    var gradient: LinearGradient {
        LinearGradient(colors: [top, bottom], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// 青碧, from the app icon.
    static let teal = StageHue(top: Color(hex: 0x3FD6C6), bottom: Color(hex: 0x0F97A8))
    /// The icon's coral jib, pushed toward sunset.
    static let coral = StageHue(top: Color(hex: 0xFFB36B), bottom: Color(hex: 0xF2545B))
    static let violet = StageHue(top: Color(hex: 0xB79CFF), bottom: Color(hex: 0x6A4BF5))
    static let amber = StageHue(top: Color(hex: 0xFFD36B), bottom: Color(hex: 0xF29A2E))
}

// MARK: - Tokens

enum Stage {
    static let inkTopNS = NSColor.adaptive(light: NSColor(hex: 0xF3F8FA), dark: NSColor(hex: 0x0C1A26))
    static let inkBottomNS = NSColor.adaptive(light: NSColor(hex: 0xEFECF8), dark: NSColor(hex: 0x15112B))
    static let inkTop = Color(nsColor: inkTopNS)
    static let inkBottom = Color(nsColor: inkBottomNS)
    /// Solid color behind the SwiftUI content, so resizing never flashes.
    static let windowColor = inkTopNS

    // Glass cards
    static let glassFill = Color.adaptive(light: white(0.66), dark: white(0.055))
    static let glassFillHover = Color.adaptive(light: white(0.86), dark: white(0.085))
    static let glassStroke = LinearGradient(
        colors: [
            Color.adaptive(light: black(0.06), dark: white(0.16)),
            Color.adaptive(light: black(0.09), dark: white(0.04))
        ],
        startPoint: .top,
        endPoint: .bottom
    )
    static let cardShadow = Color.adaptive(light: black(0.05), dark: .clear)

    // Controls
    static let controlFill = Color.adaptive(light: black(0.045), dark: white(0.08))
    static let controlHover = Color.adaptive(light: black(0.08), dark: white(0.14))
    static let controlStroke = Color.adaptive(light: black(0.08), dark: white(0.1))
    static let wellFill = Color.adaptive(light: black(0.04), dark: black(0.24))
    static let hairline = Color.adaptive(light: black(0.07), dark: white(0.07))

    // Selection (sidebar item, segmented pill)
    static let selectedFill = Color.adaptive(light: white(0.95), dark: white(0.12))
    static let selectedStroke = Color.adaptive(light: black(0.06), dark: white(0.12))
    static let sidebarFill = Color.adaptive(light: white(0.38), dark: black(0.22))

    // Text
    static let textSecondary = Color.adaptive(light: black(0.56), dark: white(0.6))
    static let textTertiary = Color.adaptive(light: black(0.38), dark: white(0.4))

    // Status
    static let ok = Color.adaptive(light: NSColor(hex: 0x12985F), dark: NSColor(hex: 0x4EE1A0))
    static let warn = Color.adaptive(light: NSColor(hex: 0xC2601A), dark: NSColor(hex: 0xFFB36B))
    static let danger = Color.adaptive(light: NSColor(hex: 0xD93025), dark: NSColor(hex: 0xFF8A80))
}

// MARK: - Backdrop

/// Soft gradient with two glows in the current hue. Cross-fades when the hue changes.
struct StageBackdrop: View {
    var hue: StageHue
    /// Floating panels draw over native vibrancy, so they skip the base gradient.
    var opaque: Bool = true
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let dark = colorScheme == .dark
        ZStack {
            if opaque {
                LinearGradient(colors: [Stage.inkTop, Stage.inkBottom], startPoint: .top, endPoint: .bottom)
            }
            RadialGradient(
                colors: [hue.bottom.opacity(dark ? 0.55 : 0.28), hue.bottom.opacity(0)],
                center: UnitPoint(x: 0.92, y: -0.05),
                startRadius: 0,
                endRadius: 560
            )
            RadialGradient(
                colors: [hue.top.opacity(dark ? 0.18 : 0.16), hue.top.opacity(0)],
                center: UnitPoint(x: 0.05, y: 1.05),
                startRadius: 0,
                endRadius: 480
            )
        }
        .ignoresSafeArea()
        .animation(FerryMotion.animation(.easeInOut(duration: 0.45)), value: hue)
    }
}

// MARK: - Orb

/// Glowing circular icon, the visual anchor of each screen.
struct HueOrb: View {
    let systemName: String
    let hue: StageHue
    var size: CGFloat = 56
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            Circle().fill(hue.gradient)
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.35), Color.white.opacity(0)],
                        startPoint: .top,
                        endPoint: .center
                    )
                )
                .padding(size * 0.06)
            Circle().strokeBorder(Color.white.opacity(0.28), lineWidth: 1)
            Image(systemName: systemName)
                .font(.system(size: size * 0.4, weight: .semibold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
        }
        .frame(width: size, height: size)
        .shadow(color: hue.bottom.opacity(colorScheme == .dark ? 0.55 : 0.4), radius: size * 0.32, y: size * 0.1)
    }
}

/// Small rounded-square icon used in the sidebar and rows.
struct HueTile: View {
    let systemName: String
    let hue: StageHue
    var size: CGFloat = 24

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size * 0.5, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(hue.gradient, in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.22), lineWidth: 0.5)
            )
    }
}

// MARK: - Glass containers

struct GlassCard<Content: View>: View {
    var cornerRadius: CGFloat = 14
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .glassSurface(cornerRadius: cornerRadius)
    }
}

/// Glass background for arbitrary views.
struct GlassSurface: ViewModifier {
    var cornerRadius: CGFloat = 14
    var fill: Color = Stage.glassFill

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(fill)
                    .shadow(color: Stage.cardShadow, radius: 8, y: 2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Stage.glassStroke, lineWidth: 1)
            )
    }
}

extension View {
    func glassSurface(cornerRadius: CGFloat = 14, fill: Color = Stage.glassFill) -> some View {
        modifier(GlassSurface(cornerRadius: cornerRadius, fill: fill))
    }
}

/// One row of a GlassCard: label on the left, control on the right.
struct GlassRow<Trailing: View>: View {
    let title: String
    var caption: String? = nil
    var divider: Bool = true
    @ViewBuilder var trailing: Trailing

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.primary)
                    if let caption {
                        Text(caption)
                            .font(.system(size: 11))
                            .foregroundStyle(Stage.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 8)
                trailing
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 48)
            .padding(.vertical, caption == nil ? 0 : 4)

            if divider {
                Rectangle().fill(Stage.hairline).frame(height: 1).padding(.leading, 16)
            }
        }
    }
}

/// Small section label above a card.
struct GlassLabel: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(Stage.textTertiary)
            .padding(.leading, 4)
    }
}

// MARK: - Hero

struct StageHero<Accessory: View>: View {
    let systemName: String
    let hue: StageHue
    let title: String
    let tagline: String
    @ViewBuilder var accessory: Accessory

    var body: some View {
        HStack(spacing: 16) {
            HueOrb(systemName: systemName, hue: hue, size: 56)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                Text(tagline)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Stage.textSecondary)
            }
            Spacer(minLength: 8)
            accessory
        }
    }
}

extension StageHero where Accessory == EmptyView {
    init(systemName: String, hue: StageHue, title: String, tagline: String) {
        self.init(systemName: systemName, hue: hue, title: title, tagline: tagline) { EmptyView() }
    }
}

// MARK: - Buttons

struct GlassButtonStyle: ButtonStyle {
    enum Kind { case glass, glow, destructive }
    var kind: Kind = .glass
    var hue: StageHue = .teal
    var height: CGFloat = 28

    func makeBody(configuration: Configuration) -> some View {
        GlassButtonBody(configuration: configuration, kind: kind, hue: hue, height: height)
    }
}

private struct GlassButtonBody: View {
    let configuration: ButtonStyle.Configuration
    let kind: GlassButtonStyle.Kind
    let hue: StageHue
    let height: CGFloat
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorScheme) private var colorScheme
    @ViewState private var hovering = false

    var body: some View {
        configuration.label
            .font(.system(size: height < 26 ? 11.5 : 12.5, weight: kind == .glow ? .semibold : .medium))
            .foregroundStyle(foreground)
            .padding(.horizontal, height < 26 ? 9 : 12)
            .frame(minWidth: height, minHeight: height)
            .background(background)
            .overlay(
                RoundedRectangle(cornerRadius: height * 0.32, style: .continuous)
                    .strokeBorder(
                        kind == .glow ? Color.white.opacity(0.25) : (hovering ? Stage.controlStroke.opacity(1.6) : Stage.controlStroke),
                        lineWidth: 1
                    )
            )
            .shadow(
                color: kind == .glow ? hue.bottom.opacity((hovering ? 0.6 : 0.4) * (colorScheme == .dark ? 1 : 0.75)) : .clear,
                radius: hovering ? 10 : 7,
                y: 2
            )
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(isEnabled ? 1 : 0.4)
            .contentShape(RoundedRectangle(cornerRadius: height * 0.32, style: .continuous))
            .onHover { hovering = $0 && isEnabled }
            .animation(FerryMotion.animation(FerryMotion.quick), value: hovering)
            .animation(FerryMotion.animation(FerryMotion.quick), value: configuration.isPressed)
    }

    private var foreground: Color {
        switch kind {
        case .glass: return .primary
        case .glow: return .white
        case .destructive: return Stage.danger
        }
    }

    @ViewBuilder
    private var background: some View {
        let shape = RoundedRectangle(cornerRadius: height * 0.32, style: .continuous)
        switch kind {
        case .glow:
            shape.fill(hue.gradient).brightness(configuration.isPressed ? -0.06 : (hovering ? 0.05 : 0))
        case .glass:
            shape.fill(hovering ? Stage.controlHover : Stage.controlFill)
        case .destructive:
            shape.fill(Stage.danger.opacity(hovering ? 0.2 : 0.11))
        }
    }
}

/// Square glass icon button.
struct GlassIconButton: View {
    let systemName: String
    let help: String
    var isOn: Bool = false
    var size: CGFloat = 28
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size * 0.43, weight: .medium))
        }
        .buttonStyle(GlassIconStyle(isOn: isOn, size: size))
        .help(help)
        .accessibilityLabel(help)
    }
}

struct GlassIconStyle: ButtonStyle {
    var isOn: Bool = false
    var size: CGFloat = 28

    func makeBody(configuration: Configuration) -> some View {
        GlassIconBody(configuration: configuration, isOn: isOn, size: size)
    }
}

private struct GlassIconBody: View {
    let configuration: ButtonStyle.Configuration
    let isOn: Bool
    let size: CGFloat
    @Environment(\.isEnabled) private var isEnabled
    @ViewState private var hovering = false

    var body: some View {
        configuration.label
            .foregroundStyle(isOn ? FerryTheme.accentText : (hovering ? Color.primary : Stage.textSecondary))
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                    .fill(isOn ? FerryTheme.accent.opacity(0.2) : (hovering ? Stage.controlHover : Stage.controlFill))
            )
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                    .strokeBorder(isOn ? FerryTheme.accent.opacity(0.35) : Stage.controlStroke, lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .opacity(isEnabled ? 1 : 0.35)
            .contentShape(Rectangle())
            .onHover { hovering = $0 && isEnabled }
            .animation(FerryMotion.animation(FerryMotion.quick), value: hovering)
            .animation(FerryMotion.animation(FerryMotion.quick), value: configuration.isPressed)
            .animation(FerryMotion.animation(FerryMotion.quick), value: isOn)
    }
}

/// Borderless icon button: no chrome until hovered. For dense toolbars inside cards.
struct GhostIconStyle: ButtonStyle {
    var isOn: Bool = false
    var size: CGFloat = 26

    func makeBody(configuration: Configuration) -> some View {
        GhostIconBody(configuration: configuration, isOn: isOn, size: size)
    }
}

private struct GhostIconBody: View {
    let configuration: ButtonStyle.Configuration
    let isOn: Bool
    let size: CGFloat
    @Environment(\.isEnabled) private var isEnabled
    @ViewState private var hovering = false

    var body: some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(isOn ? FerryTheme.accentText : (hovering ? Color.primary : Stage.textSecondary))
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                    .fill(isOn ? FerryTheme.accent.opacity(0.16) : (hovering ? Stage.controlFill : .clear))
            )
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .opacity(isEnabled ? 1 : 0.35)
            .contentShape(Rectangle())
            .onHover { hovering = $0 && isEnabled }
            .animation(FerryMotion.animation(FerryMotion.quick), value: hovering)
            .animation(FerryMotion.animation(FerryMotion.quick), value: configuration.isPressed)
    }
}

// MARK: - Inputs

/// Recessed text field with a hue focus ring; optionally secure with a reveal toggle.
struct GlassField: View {
    let placeholder: String
    @Binding var text: String
    var secure: Bool = false
    var monospaced: Bool = true

    @FocusState private var focused: Bool
    @ViewState private var revealed = false

    var body: some View {
        HStack(spacing: 6) {
            Group {
                if secure && !revealed {
                    SecureField("", text: $text, prompt: prompt)
                } else {
                    TextField("", text: $text, prompt: prompt)
                }
            }
            .textFieldStyle(.plain)
            .font(monospaced ? .system(size: 12, design: .monospaced) : .system(size: 12.5))
            .foregroundStyle(.primary)
            .focused($focused)

            if secure {
                Button {
                    revealed.toggle()
                } label: {
                    Image(systemName: revealed ? "eye.slash" : "eye")
                        .font(.system(size: 11))
                        .foregroundStyle(Stage.textTertiary)
                        .contentTransition(.symbolEffect(.replace))
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(revealed ? "隐藏" : "显示")
            }
        }
        .padding(.leading, 10)
        .padding(.trailing, secure ? 5 : 10)
        .frame(height: 28)
        .background(Stage.wellFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(focused ? FerryTheme.accent : Stage.controlStroke, lineWidth: focused ? 1.5 : 1)
        )
        .animation(FerryMotion.animation(FerryMotion.quick), value: focused)
    }

    private var prompt: Text {
        Text(placeholder).foregroundStyle(Stage.textTertiary)
    }
}

/// Label for a `Menu` that looks like a glass pop-up button.
struct GlassMenuLabel: View {
    let text: String
    var monospaced: Bool = false
    var systemImage: String? = nil
    var height: CGFloat = 28

    var body: some View {
        HStack(spacing: 6) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Stage.textSecondary)
            }
            Text(text)
                .font(monospaced ? .system(size: 12, design: .monospaced) : .system(size: 12.5, weight: .medium))
                .lineLimit(1)
                .truncationMode(.middle)
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 8.5, weight: .bold))
                .foregroundStyle(Stage.textTertiary)
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 10)
        .frame(height: height)
        .background(Stage.controlFill, in: RoundedRectangle(cornerRadius: height * 0.3, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: height * 0.3, style: .continuous)
                .strokeBorder(Stage.controlStroke, lineWidth: 1)
        )
        .contentShape(Rectangle())
    }
}

/// Pop-up menu with a glass label.
struct GlassPicker<Item: Hashable>: View {
    let items: [Item]
    @Binding var selection: Item
    let title: (Item) -> String
    var monospaced: Bool = false

    var body: some View {
        Menu {
            ForEach(items, id: \.self) { item in
                Button {
                    selection = item
                } label: {
                    if item == selection {
                        Label(title(item), systemImage: "checkmark")
                    } else {
                        Text(title(item))
                    }
                }
            }
        } label: {
            GlassMenuLabel(text: title(selection), monospaced: monospaced)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}

/// Segmented control: a recessed track with a sliding pill.
struct GlassSegmented<Item: Hashable>: View {
    let items: [Item]
    @Binding var selection: Item
    let title: (Item) -> String
    var systemImage: ((Item) -> String)? = nil
    @Namespace private var pill

    var body: some View {
        HStack(spacing: 2) {
            ForEach(items, id: \.self) { item in
                let selected = item == selection
                Button {
                    withAnimation(FerryMotion.animation(FerryMotion.spring)) {
                        selection = item
                    }
                } label: {
                    HStack(spacing: 5) {
                        if let systemImage {
                            Image(systemName: systemImage(item))
                                .font(.system(size: 11, weight: .medium))
                        }
                        Text(title(item))
                    }
                    .font(.system(size: 12, weight: selected ? .semibold : .medium))
                    .foregroundStyle(selected ? Color.primary : Stage.textSecondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 26)
                    .background {
                        if selected {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(Stage.selectedFill)
                                .shadow(color: Stage.cardShadow, radius: 2, y: 1)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        .strokeBorder(Stage.selectedStroke, lineWidth: 1)
                                )
                                .matchedGeometryEffect(id: "pill", in: pill)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Stage.wellFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

/// Switch with a glowing teal track when on.
struct GlassToggle: View {
    @Binding var isOn: Bool
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button {
            withAnimation(FerryMotion.animation(FerryMotion.spring)) {
                isOn.toggle()
            }
        } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule()
                    .fill(isOn ? AnyShapeStyle(StageHue.teal.gradient) : AnyShapeStyle(Stage.controlHover))
                    .overlay(Capsule().strokeBorder(isOn ? Color.white.opacity(0.25) : Stage.controlStroke, lineWidth: 1))
                Circle()
                    .fill(.white)
                    .frame(width: 18, height: 18)
                    .padding(2)
                    .shadow(color: .black.opacity(0.25), radius: 1.5, y: 1)
            }
            .frame(width: 38, height: 22)
            .shadow(color: isOn ? StageHue.teal.bottom.opacity(0.45) : .clear, radius: 6)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.4)
        .accessibilityAddTraits(.isToggle)
        .accessibilityValue(isOn ? "开" : "关")
    }
}

/// Status pill: a colored dot and a short word.
struct StatusPill: View {
    let text: String
    let color: Color

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 6, height: 6)
                .shadow(color: color.opacity(0.8), radius: 3)
            Text(text)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(color)
        }
        .padding(.horizontal, 8)
        .frame(height: 20)
        .background(color.opacity(0.14), in: Capsule())
    }
}
