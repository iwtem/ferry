import FerryCore
import SwiftUI

// MARK: - Provider brand marks

/// Authentic DeepSeek whale mark (24×24 viewBox, optically centered).
struct DeepSeekMark: Shape {
    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width / 24.4, rect.height / 24.4)
        // Raw bounds: x ∈ [-0.23, 24.02] (center 11.89), y ∈ [2.97, 20.79] (center 11.88)
        let ox = rect.midX - 11.89 * scale
        let oy = rect.midY - 11.88 * scale

        @inline(__always)
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: ox + x * scale, y: oy + y * scale)
        }

        var p = Path()
        // Outer whale silhouette
        p.move(to: pt(23.748, 4.482))
        p.addCurve(to: pt(23.236, 4.716), control1: pt(23.494, 4.358), control2: pt(23.384, 4.595))
        p.addCurve(to: pt(23.099, 4.852), control1: pt(23.185, 4.755), control2: pt(23.142, 4.806))
        p.addCurve(to: pt(21.726, 5.478), control1: pt(22.727, 5.249), control2: pt(22.293, 5.509))
        p.addCurve(to: pt(19.563, 6.326), control1: pt(20.897, 5.432), control2: pt(20.189, 5.692))
        p.addCurve(to: pt(18.316, 4.778), control1: pt(19.43, 5.544), control2: pt(18.988, 5.078))
        p.addCurve(to: pt(17.361, 4.128), control1: pt(17.964, 4.622), control2: pt(17.608, 4.467))
        p.addCurve(to: pt(17.056, 3.354), control1: pt(17.189, 3.887), control2: pt(17.142, 3.618))
        p.addCurve(to: pt(16.763, 3.004), control1: pt(17.001, 3.194), control2: pt(16.946, 3.031))
        p.addCurve(to: pt(16.407, 3.28), control1: pt(16.563, 2.973), control2: pt(16.485, 3.14))
        p.addCurve(to: pt(15.985, 5.12), control1: pt(16.094, 3.852), control2: pt(15.973, 4.482))
        p.addCurve(to: pt(17.823, 8.513), control1: pt(16.012, 6.556), control2: pt(16.618, 7.7))
        p.addCurve(to: pt(17.952, 8.836), control1: pt(17.96, 8.606), control2: pt(17.995, 8.7))
        p.addCurve(to: pt(17.686, 9.669), control1: pt(17.87, 9.116), control2: pt(17.772, 9.388))
        p.addCurve(to: pt(17.357, 9.809), control1: pt(17.631, 9.848), control2: pt(17.549, 9.886))
        p.addCurve(to: pt(15.621, 8.629), control1: pt(16.708, 9.53), control2: pt(16.119, 9.13))
        p.addCurve(to: pt(13.024, 6.171), control1: pt(14.764, 7.801), control2: pt(13.99, 6.887))
        p.addCurve(to: pt(12.335, 5.7), control1: pt(12.8, 6.006), control2: pt(12.57, 5.849))
        p.addCurve(to: pt(12.723, 3.864), control1: pt(11.35, 4.743), control2: pt(12.465, 3.957))
        p.addCurve(to: pt(11.944, 3.436), control1: pt(12.993, 3.766), control2: pt(12.816, 3.432))
        p.addCurve(to: pt(9.257, 4.12), control1: pt(11.072, 3.44), control2: pt(10.274, 3.731))
        p.addCurve(to: pt(8.792, 4.257), control1: pt(9.106, 4.178), control2: pt(8.95, 4.224))
        p.addCurve(to: pt(5.909, 4.155), control1: pt(7.842, 4.078), control2: pt(6.87, 4.044))
        p.addCurve(to: pt(1.412, 6.778), control1: pt(4.024, 4.365), control2: pt(2.519, 5.257))
        p.addCurve(to: pt(0.152, 12.85), control1: pt(0.082, 8.606), control2: pt(-0.231, 10.684))
        p.addCurve(to: pt(3.512, 18.503), control1: pt(0.555, 15.134), control2: pt(1.721, 17.025))
        p.addCurve(to: pt(9.95, 20.643), control1: pt(5.37, 20.036), control2: pt(7.509, 20.787))
        p.addCurve(to: pt(14.944, 18.783), control1: pt(11.432, 20.558), control2: pt(13.083, 20.359))
        p.addCurve(to: pt(16.724, 19.18), control1: pt(15.414, 19.017), control2: pt(15.906, 19.11))
        p.addCurve(to: pt(18.429, 19.052), control1: pt(17.354, 19.239), control2: pt(17.96, 19.15))
        p.addCurve(to: pt(18.848, 18.091), control1: pt(19.164, 18.896), control2: pt(19.113, 18.215))
        p.addCurve(to: pt(16.735, 17.165), control1: pt(16.693, 17.087), control2: pt(17.166, 17.496))
        p.addCurve(to: pt(20.127, 10.162), control1: pt(17.831, 15.869), control2: pt(19.481, 14.523))
        p.addCurve(to: pt(20.127, 9.317), control1: pt(20.177, 9.815), control2: pt(20.134, 9.597))
        p.addCurve(to: pt(20.357, 9.061), control1: pt(20.123, 9.147), control2: pt(20.162, 9.08))
        p.addCurve(to: pt(21.902, 8.586), control1: pt(20.898, 9.005), control2: pt(21.423, 8.844))
        p.addCurve(to: pt(23.995, 5.069), control1: pt(23.298, 7.823), control2: pt(23.862, 6.571))
        p.addCurve(to: pt(23.748, 4.481), control1: pt(24.015, 4.839), control2: pt(23.991, 4.602))
        p.closeSubpath()

        // Belly & fin cutout
        p.move(to: pt(11.581, 18))
        p.addCurve(to: pt(8.061, 15.84), control1: pt(9.492, 16.358), control2: pt(8.479, 15.817))
        p.addCurve(to: pt(7.826, 16.603), control1: pt(7.669, 15.864), control2: pt(7.74, 16.311))
        p.addCurve(to: pt(8.197, 17.342), control1: pt(7.916, 16.891), control2: pt(8.033, 17.089))
        p.addCurve(to: pt(8.084, 17.945), control1: pt(8.311, 17.509), control2: pt(8.389, 17.758))
        p.addCurve(to: pt(6.187, 17.778), control1: pt(7.411, 18.361), control2: pt(6.242, 17.805))
        p.addCurve(to: pt(2.886, 14.471), control1: pt(4.826, 16.976), control2: pt(3.687, 15.918))
        p.addCurve(to: pt(1.588, 9.989), control1: pt(2.112, 13.078), control2: pt(1.662, 11.584))
        p.addCurve(to: pt(2.065, 9.397), control1: pt(1.568, 9.603), control2: pt(1.681, 9.467))
        p.addCurve(to: pt(3.594, 9.358), control1: pt(2.569, 9.301), control2: pt(3.086, 9.287))
        p.addCurve(to: pt(9.062, 12.132), control1: pt(5.726, 9.67), control2: pt(7.54, 10.623))
        p.addCurve(to: pt(11.264, 15.023), control1: pt(9.93, 12.992), control2: pt(10.587, 14.019))
        p.addCurve(to: pt(13.744, 17.937), control1: pt(11.984, 16.089), control2: pt(12.758, 17.105))
        p.addCurve(to: pt(14.635, 18.614), control1: pt(14.092, 18.229), control2: pt(14.369, 18.451))
        p.addCurve(to: pt(11.581, 18), control1: pt(13.833, 18.704), control2: pt(12.495, 18.724))
        p.closeSubpath()

        // Eye cutout
        p.move(to: pt(12.581, 11.56))
        p.addCurve(to: pt(12.713, 11.307), control1: pt(12.581, 11.459), control2: pt(12.63, 11.365))
        p.addCurve(to: pt(12.996, 11.273), control1: pt(12.796, 11.25), control2: pt(12.902, 11.237))
        p.addCurve(to: pt(13.196, 11.561), control1: pt(13.117, 11.317), control2: pt(13.198, 11.432))
        p.addCurve(to: pt(13.105, 11.779), control1: pt(13.196, 11.643), control2: pt(13.164, 11.722))
        p.addCurve(to: pt(12.886, 11.868), control1: pt(13.047, 11.837), control2: pt(12.968, 11.869))
        p.addCurve(to: pt(12.669, 11.778), control1: pt(12.805, 11.868), control2: pt(12.726, 11.836))
        p.addCurve(to: pt(12.582, 11.56), control1: pt(12.612, 11.72), control2: pt(12.581, 11.641))
        p.closeSubpath()

        // Cheek contour cutout
        p.move(to: pt(15.691, 13.156))
        p.addCurve(to: pt(15.101, 13.316), control1: pt(15.491, 13.237), control2: pt(15.292, 13.307))
        p.addCurve(to: pt(14.303, 13.062), control1: pt(14.814, 13.326), control2: pt(14.532, 13.236))
        p.addCurve(to: pt(13.751, 12.304), control1: pt(14.029, 12.832), control2: pt(13.833, 12.704))
        p.addCurve(to: pt(13.767, 11.716), control1: pt(13.723, 12.109), control2: pt(13.728, 11.91))
        p.addCurve(to: pt(13.528, 10.989), control1: pt(13.837, 11.389), control2: pt(13.759, 11.179))
        p.addCurve(to: pt(12.84, 10.79), control1: pt(13.341, 10.833), control2: pt(13.102, 10.79))
        p.addCurve(to: pt(12.586, 10.712), control1: pt(12.75, 10.785), control2: pt(12.663, 10.758))
        p.addCurve(to: pt(12.472, 10.354), control1: pt(12.476, 10.658), control2: pt(12.386, 10.522))
        p.addCurve(to: pt(12.664, 10.144), control1: pt(12.5, 10.3), control2: pt(12.632, 10.168))
        p.addCurve(to: pt(13.81, 10.16), control1: pt(13.02, 9.942), control2: pt(13.431, 10.008))
        p.addCurve(to: pt(14.811, 10.942), control1: pt(14.162, 10.304), control2: pt(14.428, 10.568))
        p.addCurve(to: pt(15.496, 11.856), control1: pt(15.202, 11.393), control2: pt(15.273, 11.518))
        p.addCurve(to: pt(15.941, 12.704), control1: pt(15.672, 12.121), control2: pt(15.832, 12.393))
        p.addCurve(to: pt(15.691, 13.156), control1: pt(16.008, 12.899), control2: pt(15.922, 13.058))
        p.closeSubpath()

        return p
    }
}

/// Authentic Alibaba Cloud Bailian (百炼 / DashScope) multi-faceted geometric prism mark.
struct BailianMark: View {
    var body: some View {
        Canvas { context, size in
            let scale = min(size.width / 24.0, size.height / 24.2)
            // Raw bounds: x ∈ [1.00, 22.35] (center 11.67), y ∈ [0.00, 24.09] (center 12.04)
            let ox = size.width * 0.5 - 11.67 * scale
            let oy = size.height * 0.5 - 12.04 * scale

            @inline(__always)
            func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                CGPoint(x: ox + x * scale, y: oy + y * scale)
            }

            func fill(_ hex: UInt32, _ build: (inout Path) -> Void) {
                var p = Path()
                build(&p)
                context.fill(p, with: .color(Color(hex: hex)))
            }

            // Inner cobalt triangle
            fill(0x1C54E3) { p in
                p.move(to: pt(6.336, 8.919))
                p.addLine(to: pt(6.336, 15.081))
                p.addLine(to: pt(11.671, 11.998))
                p.addLine(to: pt(6.337, 8.92))
                p.closeSubpath()
            }

            // Upper-right lavender facet
            fill(0xAA9AFF) { p in
                p.move(to: pt(21.394, 5.288))
                p.addCurve(to: pt(21.384, 5.282), control1: pt(21.394, 5.288), control2: pt(21.388, 5.282))
                p.addLine(to: pt(17.01, 2.754))
                p.addLine(to: pt(6.336, 8.92))
                p.addLine(to: pt(11.671, 12.002))
                p.addLine(to: pt(21.372, 6.402))
                p.addLine(to: pt(21.388, 6.392))
                p.addCurve(to: pt(21.709, 5.844), control1: pt(21.585, 6.28), control2: pt(21.707, 6.071))
                p.addCurve(to: pt(21.394, 5.292), control1: pt(21.71, 5.617), control2: pt(21.59, 5.406))
                p.addLine(to: pt(21.394, 5.289))
                p.closeSubpath()
            }

            // Right mint-cyan facet
            fill(0x00EAD1) { p in
                p.move(to: pt(21.71, 12.465))
                p.addCurve(to: pt(21.394, 12.55), control1: pt(21.599, 12.465), control2: pt(21.49, 12.494))
                p.addCurve(to: pt(21.385, 12.553), control1: pt(21.394, 12.55), control2: pt(21.388, 12.55))
                p.addLine(to: pt(17.01, 15.081))
                p.addLine(to: pt(22.06, 17.996))
                p.addLine(to: pt(22.066, 17.996))
                p.addCurve(to: pt(22.346, 16.956), control1: pt(22.25, 17.68), control2: pt(22.347, 17.321))
                p.addLine(to: pt(22.346, 13.101))
                p.addCurve(to: pt(21.71, 12.465), control1: pt(22.345, 12.75), control2: pt(22.061, 12.466))
                p.closeSubpath()
            }

            // Bottom teal facet
            fill(0x00CEC9) { p in
                p.move(to: pt(22.06, 17.996))
                p.addLine(to: pt(17.01, 15.081))
                p.addLine(to: pt(6.34, 21.242))
                p.addLine(to: pt(10.61, 23.707))
                p.addCurve(to: pt(10.632, 23.719), control1: pt(10.61, 23.707), control2: pt(10.626, 23.713))
                p.addCurve(to: pt(12.725, 23.719), control1: pt(11.28, 24.091), control2: pt(12.077, 24.091))
                p.addCurve(to: pt(12.747, 23.707), control1: pt(12.731, 23.716), control2: pt(12.741, 23.713))
                p.addLine(to: pt(21.285, 18.777))
                p.addCurve(to: pt(21.295, 18.771), control1: pt(21.288, 18.777), control2: pt(21.291, 18.774))
                p.addCurve(to: pt(22.07, 17.999), control1: pt(21.616, 18.588), control2: pt(21.884, 18.321))
                p.addLine(to: pt(22.064, 17.999))
                p.addLine(to: pt(22.06, 17.996))
                p.closeSubpath()
            }

            // Lower-left cyan ribbon
            fill(0x00EAD1) { p in
                p.move(to: pt(11.672, 11.998))
                p.addLine(to: pt(6.336, 15.081))
                p.addLine(to: pt(4.892, 15.913))
                p.addLine(to: pt(1.287, 17.996))
                p.addLine(to: pt(1.28, 17.996))
                p.addCurve(to: pt(1.989, 18.734), control1: pt(1.453, 18.299), control2: pt(1.696, 18.551))
                p.addLine(to: pt(2.067, 18.778))
                p.addLine(to: pt(2.083, 18.788))
                p.addLine(to: pt(2.103, 18.8))
                p.addLine(to: pt(6.335, 21.242))
                p.addLine(to: pt(17.006, 15.081))
                p.addLine(to: pt(11.671, 11.999))
                p.closeSubpath()
            }

            // Top vibrant violet facet
            fill(0x7347FF) { p in
                p.move(to: pt(12.74, 0.29))
                p.addCurve(to: pt(12.425, 0.142), control1: pt(12.64, 0.23), control2: pt(12.532, 0.183))
                p.addCurve(to: pt(12.368, 0.12), control1: pt(12.405, 0.136), control2: pt(12.387, 0.126))
                p.addCurve(to: pt(11.668, 0), control1: pt(12.143, 0.041), control2: pt(11.906, 0))
                p.addCurve(to: pt(11, 0.11), control1: pt(11.435, 0), control2: pt(11.211, 0.038))
                p.addLine(to: pt(10.969, 0.12))
                p.addCurve(to: pt(10.597, 0.29), control1: pt(10.84, 0.165), control2: pt(10.715, 0.222))
                p.addLine(to: pt(2.068, 5.222))
                p.addCurve(to: pt(2.062, 5.225), control1: pt(2.068, 5.222), control2: pt(2.065, 5.222))
                p.addCurve(to: pt(1.281, 5.998), control1: pt(1.738, 5.408), control2: pt(1.47, 5.676))
                p.addLine(to: pt(1.287, 5.998))
                p.addLine(to: pt(6.336, 8.916))
                p.addLine(to: pt(17.01, 2.758))
                p.addLine(to: pt(12.74, 0.29))
                p.closeSubpath()
            }

            // Left deep cobalt facet
            fill(0x0423DA) { p in
                p.move(to: pt(1.287, 6.001))
                p.addLine(to: pt(1.28, 6.001))
                p.addCurve(to: pt(1, 7.041), control1: pt(1.096, 6.317), control2: pt(0.999, 6.676))
                p.addLine(to: pt(1, 16.956))
                p.addCurve(to: pt(1.28, 17.999), control1: pt(1, 17.334), control2: pt(1.1, 17.691))
                p.addLine(to: pt(1.287, 17.999))
                p.addLine(to: pt(6.336, 15.081))
                p.addLine(to: pt(6.336, 8.919))
                p.addLine(to: pt(1.286, 6.001))
                p.closeSubpath()
            }
        }
    }
}

/// Clean, vibrant geometric endpoint mark (`< • >`) for Custom OpenAI-compatible providers.
struct CustomEndpointMark: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let dark = colorScheme == .dark
        let bracketColor = dark ? Color(hex: 0xFF8364) : Color(hex: 0xF95738)
        let sparkColor = dark ? Color(hex: 0xFFD060) : Color(hex: 0xFF9F1C)

        Canvas { context, size in
            let s = min(size.width, size.height) / 24.0
            let ox = (size.width - 24 * s) * 0.5
            let oy = (size.height - 24 * s) * 0.5
            func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                CGPoint(x: ox + x * s, y: oy + y * s)
            }

            let stroke = StrokeStyle(lineWidth: 2.35 * s, lineCap: .round, lineJoin: .round)

            // Left chevron `<`
            var left = Path()
            left.move(to: pt(7.6, 6.6))
            left.addLine(to: pt(2.6, 12.0))
            left.addLine(to: pt(7.6, 17.4))
            context.stroke(left, with: .color(bracketColor), style: stroke)

            // Right chevron `>`
            var right = Path()
            right.move(to: pt(16.4, 6.6))
            right.addLine(to: pt(21.4, 12.0))
            right.addLine(to: pt(16.4, 17.4))
            context.stroke(right, with: .color(bracketColor), style: stroke)

            // Tilted kinetic slash / pulse node in center
            var pill = Path()
            pill.move(to: pt(13.6, 6.4))
            pill.addLine(to: pt(10.4, 17.6))
            context.stroke(pill, with: .color(sparkColor), style: StrokeStyle(lineWidth: 2.35 * s, lineCap: .round))
        }
    }
}

/// Crisp, non-glossy brand badge for provider tiles.
struct ProviderBrandBadge: View {
    let kind: ProviderKind
    var size: CGFloat = 34
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let dark = colorScheme == .dark
        let radius = size * 0.28
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)

        ZStack {
            shape.fill(backgroundColor(dark: dark))
            shape.strokeBorder(borderColor(dark: dark), lineWidth: 1)

            switch kind {
            case .deepseek:
                DeepSeekMark()
                    .fill(
                        dark ? Color(hex: 0x7C98FF) : Color(hex: 0x4D6BFE),
                        style: FillStyle(eoFill: true)
                    )
                    .frame(width: size * 0.64, height: size * 0.64)
            case .bailian:
                BailianMark()
                    .frame(width: size * 0.60, height: size * 0.60)
            case .custom:
                CustomEndpointMark()
                    .frame(width: size * 0.62, height: size * 0.62)
            }
        }
        .frame(width: size, height: size)
    }

    private func backgroundColor(dark: Bool) -> Color {
        switch kind {
        case .deepseek:
            return dark ? Color(hex: 0x4D6BFE, opacity: 0.18) : Color(hex: 0xEEF2FF)
        case .bailian:
            return dark ? Color(hex: 0x615CED, opacity: 0.18) : Color(hex: 0xF3F2FF)
        case .custom:
            return dark ? Color(hex: 0xFF6B4A, opacity: 0.18) : Color(hex: 0xFFF2EC)
        }
    }

    private func borderColor(dark: Bool) -> Color {
        switch kind {
        case .deepseek:
            return Color(hex: 0x4D6BFE, opacity: dark ? 0.30 : 0.16)
        case .bailian:
            return Color(hex: 0x615CED, opacity: dark ? 0.30 : 0.15)
        case .custom:
            return Color(hex: 0xF95738, opacity: dark ? 0.30 : 0.16)
        }
    }
}

// MARK: - Bespoke Settings Pane Glyphs

/// Clean, geometric duotone icons for the Settings sidebar and section heroes.
/// Replaces generic SF Symbols (`cpu`, `command`, `slider.horizontal.3`) with a cohesive,
/// crisp modern vector style aligned with Ferry's geometric brand identity.
struct SettingsPaneGlyph: View {
    let pane: SettingsPane
    let primary: Color
    let secondary: Color

    var body: some View {
        Canvas { context, size in
            let s = min(size.width, size.height) / 24.0
            let ox = (size.width - 24 * s) * 0.5
            let oy = (size.height - 24 * s) * 0.5

            @inline(__always)
            func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                CGPoint(x: ox + x * s, y: oy + y * s)
            }

            switch pane {
            case .models:
                drawModelsStack(in: &context, s: s, pt: pt)
            case .shortcut:
                drawCommandKey(in: &context, s: s, pt: pt)
            case .general:
                drawSliders(in: &context, s: s, pt: pt)
            }
        }
    }

    /// Layered isometric model stack: clean upper card + soft lower layer + subtle active dot.
    private func drawModelsStack(
        in context: inout GraphicsContext,
        s: CGFloat,
        pt: (CGFloat, CGFloat) -> CGPoint
    ) {
        // Lower isometric layer (chevron/deck underneath)
        var lower = Path()
        lower.move(to: pt(4.2, 14.2))
        lower.addLine(to: pt(12.0, 18.4))
        lower.addLine(to: pt(19.8, 14.2))
        context.stroke(
            lower,
            with: .color(secondary.opacity(0.95)),
            style: StrokeStyle(lineWidth: 2.35 * s, lineCap: .round, lineJoin: .round)
        )

        // Subtle third deck whisper for layered depth
        var base = Path()
        base.move(to: pt(6.5, 18.0))
        base.addLine(to: pt(12.0, 21.0))
        base.addLine(to: pt(17.5, 18.0))
        context.stroke(
            base,
            with: .color(secondary.opacity(0.65)),
            style: StrokeStyle(lineWidth: 2.1 * s, lineCap: .round, lineJoin: .round)
        )

        // Upper crisp rounded isometric diamond
        let topDiamond = roundedPolygon(
            [pt(12.0, 3.2), pt(20.4, 8.0), pt(12.0, 12.8), pt(3.6, 8.0)],
            cornerRadius: 1.8 * s
        )
        context.fill(topDiamond, with: .color(primary))
    }

    /// Crisp geometric macOS Command `⌘` symbol with balanced duotone center fill.
    private func drawCommandKey(
        in context: inout GraphicsContext,
        s: CGFloat,
        pt: (CGFloat, CGFloat) -> CGPoint
    ) {
        // Subtle center square tint for crisp duotone depth
        let centerRect = CGRect(
            x: pt(8.9, 8.9).x,
            y: pt(8.9, 8.9).y,
            width: 6.2 * s,
            height: 6.2 * s
        )
        context.fill(Path(roundedRect: centerRect, cornerRadius: 1.0 * s), with: .color(secondary.opacity(0.45)))

        let stroke = StrokeStyle(lineWidth: 2.15 * s, lineCap: .round, lineJoin: .round)
        let r = 2.65 * s

        // Continuous balanced ⌘ path: four loops around the center square (8.9..15.1)
        var cmd = Path()
        // Horizontal bars
        cmd.move(to: pt(6.25, 8.9))
        cmd.addLine(to: pt(17.75, 8.9))
        cmd.move(to: pt(6.25, 15.1))
        cmd.addLine(to: pt(17.75, 15.1))
        // Vertical bars
        cmd.move(to: pt(8.9, 6.25))
        cmd.addLine(to: pt(8.9, 17.75))
        cmd.move(to: pt(15.1, 6.25))
        cmd.addLine(to: pt(15.1, 17.75))
        context.stroke(cmd, with: .color(primary), style: stroke)

        // Four corner loops (3/4 circles connecting the bar ends seamlessly)
        let cornerArcs: [(CGPoint, Double, Double)] = [
            (pt(6.25, 6.25), 0, 90),     // Top-left
            (pt(17.75, 6.25), 90, 180),  // Top-right
            (pt(17.75, 17.75), 180, 270), // Bottom-right
            (pt(6.25, 17.75), 270, 0),   // Bottom-left
        ]
        for (center, startDeg, endDeg) in cornerArcs {
            var loop = Path()
            loop.addArc(
                center: center,
                radius: r,
                startAngle: .degrees(startDeg),
                endAngle: .degrees(endDeg),
                clockwise: true
            )
            context.stroke(loop, with: .color(primary), style: stroke)
        }
    }

    /// Minimalist dual pill toggles: modern Swiss-clean controls icon.
    private func drawSliders(
        in context: inout GraphicsContext,
        s: CGFloat,
        pt: (CGFloat, CGFloat) -> CGPoint
    ) {
        let trackH = 6.0 * s
        let trackW = 16.4 * s
        let knobD = 3.8 * s
        let inset = (trackH - knobD) * 0.5

        // Top toggle (switched ON — knob right)
        let topRect = CGRect(x: pt(3.8, 4.1).x, y: pt(3.8, 4.1).y, width: trackW, height: trackH)
        context.fill(Path(roundedRect: topRect, cornerRadius: trackH * 0.5), with: .color(secondary.opacity(0.60)))
        let topKnob = CGRect(
            x: topRect.maxX - knobD - inset,
            y: topRect.minY + inset,
            width: knobD,
            height: knobD
        )
        context.fill(Path(ellipseIn: topKnob), with: .color(primary))

        // Bottom toggle (switched OFF — knob left, crisp outlined pill)
        let botRect = CGRect(x: pt(3.8, 13.9).x, y: pt(3.8, 13.9).y, width: trackW, height: trackH)
        context.stroke(
            Path(roundedRect: botRect.insetBy(dx: 0.75 * s, dy: 0.75 * s), cornerRadius: trackH * 0.5),
            with: .color(primary.opacity(0.86)),
            style: StrokeStyle(lineWidth: 1.55 * s)
        )
        let botKnob = CGRect(
            x: botRect.minX + inset + 0.85 * s,
            y: botRect.minY + inset,
            width: knobD,
            height: knobD
        )
        context.fill(Path(ellipseIn: botKnob), with: .color(primary))
    }

    private func roundedPolygon(_ points: [CGPoint], cornerRadius: CGFloat) -> Path {
        guard points.count >= 3 else { return Path() }
        var p = Path()
        for i in points.indices {
            let prev = points[(i - 1 + points.count) % points.count]
            let curr = points[i]
            let next = points[(i + 1) % points.count]

            let v1 = CGPoint(x: prev.x - curr.x, y: prev.y - curr.y)
            let v2 = CGPoint(x: next.x - curr.x, y: next.y - curr.y)
            let len1 = max(hypot(v1.x, v1.y), 0.001)
            let len2 = max(hypot(v2.x, v2.y), 0.001)
            let r = min(cornerRadius, len1 * 0.4, len2 * 0.4)

            let start = CGPoint(x: curr.x + v1.x / len1 * r, y: curr.y + v1.y / len1 * r)
            let end = CGPoint(x: curr.x + v2.x / len2 * r, y: curr.y + v2.y / len2 * r)

            if i == 0 {
                p.move(to: start)
            } else {
                p.addLine(to: start)
            }
            p.addQuadCurve(to: end, control: curr)
        }
        p.closeSubpath()
        return p
    }
}

/// Crisp modern squircle badge for settings panes (replaces glossy glowing `HueOrb` & noisy `HueTile`).
struct SettingsPaneBadge: View {
    let pane: SettingsPane
    var size: CGFloat = 44
    var filled: Bool = true
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let dark = colorScheme == .dark
        let hue = pane.hue
        let shape = RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)

        ZStack {
            if filled {
                shape.fill(hue.gradient)
                shape.strokeBorder(Color.white.opacity(dark ? 0.16 : 0.28), lineWidth: 0.75)
                SettingsPaneGlyph(
                    pane: pane,
                    primary: .white,
                    secondary: Color.white.opacity(0.72)
                )
                .frame(width: size * 0.58, height: size * 0.58)
            } else {
                shape.fill(hue.bottom.opacity(dark ? 0.18 : 0.11))
                shape.strokeBorder(hue.bottom.opacity(dark ? 0.26 : 0.14), lineWidth: 0.75)
                SettingsPaneGlyph(
                    pane: pane,
                    primary: dark ? hue.top : hue.bottom,
                    secondary: (dark ? hue.top : hue.bottom).opacity(0.60)
                )
                .frame(width: size * 0.58, height: size * 0.58)
            }
        }
        .frame(width: size, height: size)
        .shadow(
            color: filled ? Color.black.opacity(dark ? 0.28 : 0.12) : .clear,
            radius: size * 0.09,
            y: size * 0.05
        )
    }
}
