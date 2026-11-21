import FerryCore
import SwiftUI

/// Crisp 24×24 vector icon system faithfully implementing Lucide (`lucide.dev`) geometry
/// with uniform stroke weight, round caps, and round joins across every Ferry window.
public struct LucideIcon: View {
    public enum Name: Hashable, Sendable {
        case copy
        case check
        case volume2
        case volumeX
        case clipboardPaste
        case circleX
        case x
        case arrowUpDown
        case arrowLeftRight
        case arrowRight
        case scanText
        case pictureInPicture2
        case maximize2
        case settings
        case power
        case history
        case pin
        case rotateCw
        case rotateCcw
        case cornerDownLeft
        case globe
        case languages
        case sparkles
        case spellCheck
        case briefcase
        case graduationCap
        case chevronDown
        case chevronUp
        case chevronsUpDown
        case eye
        case eyeOff
        case square
        case messageSquareText
    }

    public let name: Name
    public var size: CGFloat
    public var strokeWidth: CGFloat
    public var filled: Bool

    public init(_ name: Name, size: CGFloat = 14, strokeWidth: CGFloat = 1.9, filled: Bool = false) {
        self.name = name
        self.size = size
        self.strokeWidth = strokeWidth
        self.filled = filled
    }

    public var body: some View {
        let lineWidth = max(1.0, (strokeWidth / 24.0) * size)
        ZStack {
            if filled, let fillShape = LucideFillShape(name: name) {
                fillShape
                    .fill(.foreground.opacity(name == .square ? 1.0 : 0.24))
            }
            LucideStrokeShape(name: name)
                .stroke(
                    style: StrokeStyle(
                        lineWidth: lineWidth,
                        lineCap: .round,
                        lineJoin: .round
                    )
                )
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

extension TranslationMode {
    var lucideIcon: LucideIcon.Name {
        switch self {
        case .translate: return .languages
        case .polish: return .sparkles
        case .grammar: return .spellCheck
        case .concise: return .briefcase
        case .academic: return .graduationCap
        }
    }
}

// MARK: - Optional Fill Shapes (for active/filled states like pinned or stop)

private struct LucideFillShape: Shape {
    let name: LucideIcon.Name

    init?(name: LucideIcon.Name) {
        switch name {
        case .pin, .volume2, .square:
            self.name = name
        default:
            return nil
        }
    }

    func path(in rect: CGRect) -> Path {
        let g = LucideGrid(rect)
        var p = Path()
        switch name {
        case .pin:
            LucideStrokeShape.addPinBody(to: &p, g: g)
        case .volume2:
            LucideStrokeShape.addSpeakerBody(to: &p, g: g)
        case .square:
            g.addRoundedRect(&p, x: 5, y: 5, width: 14, height: 14, radius: 2)
        default:
            break
        }
        return p
    }
}

// MARK: - 24×24 Coordinate Helper

private struct LucideGrid {
    let scale: CGFloat
    let ox: CGFloat
    let oy: CGFloat

    init(_ rect: CGRect) {
        self.scale = min(rect.width, rect.height) / 24.0
        self.ox = rect.midX - 12.0 * scale
        self.oy = rect.midY - 12.0 * scale
    }

    @inline(__always)
    func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(x: ox + x * scale, y: oy + y * scale)
    }

    @inline(__always)
    func r(_ value: CGFloat) -> CGFloat {
        value * scale
    }

    func addRoundedRect(_ p: inout Path, x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat, radius: CGFloat) {
        let rect = CGRect(x: ox + x * scale, y: oy + y * scale, width: width * scale, height: height * scale)
        p.addRoundedRect(in: rect, cornerSize: CGSize(width: radius * scale, height: radius * scale))
    }

    func addCircle(_ p: inout Path, cx: CGFloat, cy: CGFloat, radius: CGFloat) {
        let rect = CGRect(
            x: ox + (cx - radius) * scale,
            y: oy + (cy - radius) * scale,
            width: radius * 2 * scale,
            height: radius * 2 * scale
        )
        p.addEllipse(in: rect)
    }
}

// MARK: - Lucide 24×24 Vector Paths

private struct LucideStrokeShape: Shape {
    let name: LucideIcon.Name

    func path(in rect: CGRect) -> Path {
        let g = LucideGrid(rect)
        var p = Path()

        switch name {
        case .copy:
            // <rect width="14" height="14" x="8" y="8" rx="2" ry="2"/>
            // <path d="M4 16c-1.1 0-2-.9-2-2V4c0-1.1.9-2 2-2h10c1.1 0 2 .9 2 2"/>
            g.addRoundedRect(&p, x: 8, y: 8, width: 14, height: 14, radius: 2)
            p.move(to: g.pt(4, 16))
            p.addCurve(to: g.pt(2, 14), control1: g.pt(2.9, 16), control2: g.pt(2, 15.1))
            p.addLine(to: g.pt(2, 4))
            p.addCurve(to: g.pt(4, 2), control1: g.pt(2, 2.9), control2: g.pt(2.9, 2))
            p.addLine(to: g.pt(14, 2))
            p.addCurve(to: g.pt(16, 4), control1: g.pt(15.1, 2), control2: g.pt(16, 2.9))

        case .check:
            // <path d="M20 6 9 17l-5-5"/>
            p.move(to: g.pt(20, 6))
            p.addLine(to: g.pt(9, 17))
            p.addLine(to: g.pt(4, 12))

        case .volume2:
            Self.addSpeakerBody(to: &p, g: g)
            // Inner wave: M16 9 a5 5 0 0 1 0 6 (center 12,12 r=5, -36.87°..36.87°)
            var w1 = Path()
            w1.addArc(
                center: g.pt(12, 12),
                radius: g.r(5),
                startAngle: .degrees(-36.87),
                endAngle: .degrees(36.87),
                clockwise: false
            )
            p.addPath(w1)
            // Outer wave: M19.364 18.364 a9 9 0 0 0 0 -12.728 (center 13,12 r=9, -45°..45°)
            var w2 = Path()
            w2.addArc(
                center: g.pt(13, 12),
                radius: g.r(9),
                startAngle: .degrees(-45),
                endAngle: .degrees(45),
                clockwise: false
            )
            p.addPath(w2)

        case .volumeX:
            Self.addSpeakerBody(to: &p, g: g)
            p.move(to: g.pt(22, 9))
            p.addLine(to: g.pt(16, 15))
            p.move(to: g.pt(16, 9))
            p.addLine(to: g.pt(22, 15))

        case .clipboardPaste:
            // Clip
            g.addRoundedRect(&p, x: 8, y: 2, width: 8, height: 4, radius: 1)
            // Board left + bottom
            p.move(to: g.pt(8, 4))
            p.addLine(to: g.pt(6, 4))
            p.addQuadCurve(to: g.pt(4, 6), control: g.pt(4, 4))
            p.addLine(to: g.pt(4, 20))
            p.addQuadCurve(to: g.pt(6, 22), control: g.pt(4, 22))
            p.addLine(to: g.pt(18, 22))
            p.addQuadCurve(to: g.pt(20, 20), control: g.pt(20, 22))
            // Board top-right
            p.move(to: g.pt(16, 4))
            p.addLine(to: g.pt(18, 4))
            p.addQuadCurve(to: g.pt(20, 6), control: g.pt(20, 4))
            p.addLine(to: g.pt(20, 8))
            // Paste arrow
            p.move(to: g.pt(11, 14))
            p.addLine(to: g.pt(21, 14))
            p.move(to: g.pt(17, 10))
            p.addLine(to: g.pt(21, 14))
            p.addLine(to: g.pt(17, 18))

        case .circleX:
            g.addCircle(&p, cx: 12, cy: 12, radius: 10)
            p.move(to: g.pt(15, 9))
            p.addLine(to: g.pt(9, 15))
            p.move(to: g.pt(9, 9))
            p.addLine(to: g.pt(15, 15))

        case .x:
            p.move(to: g.pt(18, 6))
            p.addLine(to: g.pt(6, 18))
            p.move(to: g.pt(6, 6))
            p.addLine(to: g.pt(18, 18))

        case .arrowUpDown:
            p.move(to: g.pt(21, 16))
            p.addLine(to: g.pt(17, 20))
            p.addLine(to: g.pt(13, 16))
            p.move(to: g.pt(17, 20))
            p.addLine(to: g.pt(17, 4))
            p.move(to: g.pt(3, 8))
            p.addLine(to: g.pt(7, 4))
            p.addLine(to: g.pt(11, 8))
            p.move(to: g.pt(7, 4))
            p.addLine(to: g.pt(7, 20))

        case .arrowLeftRight:
            p.move(to: g.pt(8, 3))
            p.addLine(to: g.pt(4, 7))
            p.addLine(to: g.pt(8, 11))
            p.move(to: g.pt(4, 7))
            p.addLine(to: g.pt(20, 7))
            p.move(to: g.pt(16, 21))
            p.addLine(to: g.pt(20, 17))
            p.addLine(to: g.pt(16, 13))
            p.move(to: g.pt(20, 17))
            p.addLine(to: g.pt(4, 17))

        case .arrowRight:
            p.move(to: g.pt(5, 12))
            p.addLine(to: g.pt(19, 12))
            p.move(to: g.pt(12, 5))
            p.addLine(to: g.pt(19, 12))
            p.addLine(to: g.pt(12, 19))

        case .scanText:
            // Four rounded viewfinder corners
            p.move(to: g.pt(3, 7))
            p.addLine(to: g.pt(3, 5))
            p.addQuadCurve(to: g.pt(5, 3), control: g.pt(3, 3))
            p.addLine(to: g.pt(7, 3))

            p.move(to: g.pt(17, 3))
            p.addLine(to: g.pt(19, 3))
            p.addQuadCurve(to: g.pt(21, 5), control: g.pt(21, 3))
            p.addLine(to: g.pt(21, 7))

            p.move(to: g.pt(21, 17))
            p.addLine(to: g.pt(21, 19))
            p.addQuadCurve(to: g.pt(19, 21), control: g.pt(21, 21))
            p.addLine(to: g.pt(17, 21))

            p.move(to: g.pt(7, 21))
            p.addLine(to: g.pt(5, 21))
            p.addQuadCurve(to: g.pt(3, 19), control: g.pt(3, 21))
            p.addLine(to: g.pt(3, 17))

            // Text lines
            p.move(to: g.pt(7, 8))
            p.addLine(to: g.pt(15, 8))
            p.move(to: g.pt(7, 12))
            p.addLine(to: g.pt(17, 12))
            p.move(to: g.pt(7, 16))
            p.addLine(to: g.pt(13, 16))

        case .pictureInPicture2:
            p.move(to: g.pt(21, 9))
            p.addLine(to: g.pt(21, 6))
            p.addQuadCurve(to: g.pt(19, 4), control: g.pt(21, 4))
            p.addLine(to: g.pt(4, 4))
            p.addQuadCurve(to: g.pt(2, 6), control: g.pt(2, 4))
            p.addLine(to: g.pt(2, 16))
            p.addQuadCurve(to: g.pt(4, 18), control: g.pt(2, 18))
            p.addLine(to: g.pt(8, 18))
            g.addRoundedRect(&p, x: 12, y: 13, width: 10, height: 7, radius: 2)

        case .maximize2:
            p.move(to: g.pt(15, 3))
            p.addLine(to: g.pt(21, 3))
            p.addLine(to: g.pt(21, 9))
            p.move(to: g.pt(21, 3))
            p.addLine(to: g.pt(14, 10))

            p.move(to: g.pt(9, 21))
            p.addLine(to: g.pt(3, 21))
            p.addLine(to: g.pt(3, 15))
            p.move(to: g.pt(3, 21))
            p.addLine(to: g.pt(10, 14))

        case .settings:
            // Symmetric 6-tooth Lucide gear outline + center circle (r = 3)
            g.addCircle(&p, cx: 12, cy: 12, radius: 3)
            let outerR: CGFloat = 10.0
            let valleyR: CGFloat = 7.45
            let toothTopHalf: CGFloat = 11.5 * .pi / 180.0
            let toothBaseHalf: CGFloat = 19.5 * .pi / 180.0

            func polar(_ radius: CGFloat, _ angle: CGFloat) -> CGPoint {
                g.pt(12 + radius * cos(angle), 12 + radius * sin(angle))
            }

            var gearVertices: [CGPoint] = []
            for k in 0..<6 {
                let centerAngle = -CGFloat.pi / 2 + CGFloat(k) * (CGFloat.pi / 3)
                gearVertices.append(polar(valleyR, centerAngle - toothBaseHalf))
                gearVertices.append(polar(outerR, centerAngle - toothTopHalf))
                gearVertices.append(polar(outerR, centerAngle + toothTopHalf))
                gearVertices.append(polar(valleyR, centerAngle + toothBaseHalf))
            }
            p.addPath(Self.roundedClosedPolygon(gearVertices, cornerRadius: g.r(1.35)))

        case .power:
            p.move(to: g.pt(12, 2))
            p.addLine(to: g.pt(12, 12))
            var ring = Path()
            ring.addArc(
                center: g.pt(12, 13),
                radius: g.r(8.6),
                startAngle: .degrees(-44),
                endAngle: .degrees(224),
                clockwise: false
            )
            p.addPath(ring)

        case .history:
            // Counter-clockwise arc from 180° (9 o'clock) through bottom, right, top to -138° + tail to (3,8)
            var arc = Path()
            arc.addArc(
                center: g.pt(12, 12),
                radius: g.r(9),
                startAngle: .degrees(180),
                endAngle: .degrees(-138),
                clockwise: true
            )
            arc.addLine(to: g.pt(3, 8))
            p.addPath(arc)
            p.move(to: g.pt(3, 3))
            p.addLine(to: g.pt(3, 8))
            p.addLine(to: g.pt(8, 8))
            // Clock hands
            p.move(to: g.pt(12, 7))
            p.addLine(to: g.pt(12, 12))
            p.addLine(to: g.pt(16, 14))

        case .rotateCw:
            // Clockwise arc from 0° (3 o'clock) through bottom, left, top to 318° (-42°) + tail to (21,8)
            var arc = Path()
            arc.addArc(
                center: g.pt(12, 12),
                radius: g.r(9),
                startAngle: .degrees(0),
                endAngle: .degrees(318),
                clockwise: false
            )
            arc.addLine(to: g.pt(21, 8))
            p.addPath(arc)
            p.move(to: g.pt(21, 3))
            p.addLine(to: g.pt(21, 8))
            p.addLine(to: g.pt(16, 8))

        case .rotateCcw:
            var arc = Path()
            arc.addArc(
                center: g.pt(12, 12),
                radius: g.r(9),
                startAngle: .degrees(180),
                endAngle: .degrees(-138),
                clockwise: true
            )
            arc.addLine(to: g.pt(3, 8))
            p.addPath(arc)
            p.move(to: g.pt(3, 3))
            p.addLine(to: g.pt(3, 8))
            p.addLine(to: g.pt(8, 8))

        case .pin:
            p.move(to: g.pt(12, 17))
            p.addLine(to: g.pt(12, 22))
            Self.addPinBody(to: &p, g: g)

        case .cornerDownLeft:
            p.move(to: g.pt(9, 10))
            p.addLine(to: g.pt(4, 15))
            p.addLine(to: g.pt(9, 20))
            p.move(to: g.pt(20, 4))
            p.addLine(to: g.pt(20, 11))
            p.addQuadCurve(to: g.pt(16, 15), control: g.pt(20, 15))
            p.addLine(to: g.pt(4, 15))

        case .globe:
            g.addCircle(&p, cx: 12, cy: 12, radius: 10)
            p.move(to: g.pt(2, 12))
            p.addLine(to: g.pt(22, 12))
            p.move(to: g.pt(12, 2))
            p.addCurve(to: g.pt(12, 22), control1: g.pt(16.2, 6.2), control2: g.pt(16.2, 17.8))
            p.addCurve(to: g.pt(12, 2), control1: g.pt(7.8, 17.8), control2: g.pt(7.8, 6.2))

        case .languages:
            p.move(to: g.pt(5, 8))
            p.addLine(to: g.pt(11, 14))
            p.move(to: g.pt(4, 14))
            p.addLine(to: g.pt(10, 8))
            p.addLine(to: g.pt(12, 5))
            p.move(to: g.pt(2, 5))
            p.addLine(to: g.pt(14, 5))
            p.move(to: g.pt(7, 2))
            p.addLine(to: g.pt(8, 2))
            p.move(to: g.pt(22, 22))
            p.addLine(to: g.pt(17, 12))
            p.addLine(to: g.pt(12, 22))
            p.move(to: g.pt(14, 18))
            p.addLine(to: g.pt(20, 18))

        case .sparkles:
            // Main 4-point star
            p.move(to: g.pt(10.5, 3))
            p.addQuadCurve(to: g.pt(18.5, 11.5), control: g.pt(11.5, 10.5))
            p.addQuadCurve(to: g.pt(10.5, 20), control: g.pt(11.5, 12.5))
            p.addQuadCurve(to: g.pt(2.5, 11.5), control: g.pt(9.5, 12.5))
            p.addQuadCurve(to: g.pt(10.5, 3), control: g.pt(9.5, 10.5))
            p.closeSubpath()
            // Top-right small cross
            p.move(to: g.pt(19.5, 3))
            p.addLine(to: g.pt(19.5, 7))
            p.move(to: g.pt(17.5, 5))
            p.addLine(to: g.pt(21.5, 5))
            // Bottom-left spark
            p.move(to: g.pt(4.5, 18.5))
            p.addLine(to: g.pt(4.5, 21))
            p.move(to: g.pt(3.25, 19.75))
            p.addLine(to: g.pt(5.75, 19.75))

        case .spellCheck:
            p.move(to: g.pt(6, 16))
            p.addLine(to: g.pt(12, 4))
            p.addLine(to: g.pt(18, 16))
            p.move(to: g.pt(8, 12))
            p.addLine(to: g.pt(16, 12))
            p.move(to: g.pt(16, 20))
            p.addLine(to: g.pt(18, 22))
            p.addLine(to: g.pt(22, 18))

        case .briefcase:
            g.addRoundedRect(&p, x: 2, y: 6, width: 20, height: 14, radius: 2)
            p.move(to: g.pt(16, 20))
            p.addLine(to: g.pt(16, 4))
            p.addQuadCurve(to: g.pt(14, 2), control: g.pt(16, 2))
            p.addLine(to: g.pt(10, 2))
            p.addQuadCurve(to: g.pt(8, 4), control: g.pt(8, 2))
            p.addLine(to: g.pt(8, 20))

        case .graduationCap:
            p.move(to: g.pt(2, 10))
            p.addLine(to: g.pt(12, 5))
            p.addLine(to: g.pt(22, 10))
            p.addLine(to: g.pt(12, 15))
            p.closeSubpath()
            p.move(to: g.pt(22, 10))
            p.addLine(to: g.pt(22, 16))
            p.move(to: g.pt(6, 12))
            p.addLine(to: g.pt(6, 17))
            p.addQuadCurve(to: g.pt(18, 17), control: g.pt(12, 21))
            p.addLine(to: g.pt(18, 12))

        case .chevronDown:
            p.move(to: g.pt(6, 9))
            p.addLine(to: g.pt(12, 15))
            p.addLine(to: g.pt(18, 9))

        case .chevronUp:
            p.move(to: g.pt(18, 15))
            p.addLine(to: g.pt(12, 9))
            p.addLine(to: g.pt(6, 15))

        case .chevronsUpDown:
            p.move(to: g.pt(7, 15))
            p.addLine(to: g.pt(12, 20))
            p.addLine(to: g.pt(17, 15))
            p.move(to: g.pt(7, 9))
            p.addLine(to: g.pt(12, 4))
            p.addLine(to: g.pt(17, 9))

        case .eye:
            p.move(to: g.pt(2, 12))
            p.addCurve(to: g.pt(22, 12), control1: g.pt(5.5, 5), control2: g.pt(18.5, 5))
            p.addCurve(to: g.pt(2, 12), control1: g.pt(18.5, 19), control2: g.pt(5.5, 19))
            g.addCircle(&p, cx: 12, cy: 12, radius: 3)

        case .eyeOff:
            p.move(to: g.pt(10.73, 5.08))
            p.addCurve(to: g.pt(22, 12), control1: g.pt(15.2, 4.6), control2: g.pt(19.4, 7.6))
            p.addCurve(to: g.pt(17.94, 17.94), control1: g.pt(20.9, 14.4), control2: g.pt(19.6, 16.4))
            p.move(to: g.pt(14.12, 18.88))
            p.addCurve(to: g.pt(2, 12), control1: g.pt(9.3, 19.6), control2: g.pt(4.7, 16.5))
            p.addCurve(to: g.pt(6.06, 6.06), control1: g.pt(3.1, 9.6), control2: g.pt(4.4, 7.6))
            p.move(to: g.pt(2, 2))
            p.addLine(to: g.pt(22, 22))

        case .square:
            g.addRoundedRect(&p, x: 5, y: 5, width: 14, height: 14, radius: 2)

        case .messageSquareText:
            p.move(to: g.pt(21, 15))
            p.addQuadCurve(to: g.pt(19, 17), control: g.pt(21, 17))
            p.addLine(to: g.pt(7, 17))
            p.addLine(to: g.pt(3, 21))
            p.addLine(to: g.pt(3, 5))
            p.addQuadCurve(to: g.pt(5, 3), control: g.pt(3, 3))
            p.addLine(to: g.pt(19, 3))
            p.addQuadCurve(to: g.pt(21, 5), control: g.pt(21, 3))
            p.closeSubpath()
            p.move(to: g.pt(7, 8))
            p.addLine(to: g.pt(17, 8))
            p.move(to: g.pt(7, 12))
            p.addLine(to: g.pt(13, 12))
        }

        return p
    }

    static func addSpeakerBody(to p: inout Path, g: LucideGrid) {
        p.move(to: g.pt(11, 5.0))
        p.addQuadCurve(to: g.pt(9.7, 4.4), control: g.pt(11, 3.8))
        p.addLine(to: g.pt(6.4, 7.6))
        p.addQuadCurve(to: g.pt(5.4, 8.0), control: g.pt(6.0, 8.0))
        p.addLine(to: g.pt(3.0, 8.0))
        p.addQuadCurve(to: g.pt(2.0, 9.0), control: g.pt(2.0, 8.0))
        p.addLine(to: g.pt(2.0, 15.0))
        p.addQuadCurve(to: g.pt(3.0, 16.0), control: g.pt(2.0, 16.0))
        p.addLine(to: g.pt(5.4, 16.0))
        p.addQuadCurve(to: g.pt(6.4, 16.4), control: g.pt(6.0, 16.0))
        p.addLine(to: g.pt(9.7, 19.6))
        p.addQuadCurve(to: g.pt(11, 19.0), control: g.pt(11, 20.2))
        p.closeSubpath()
    }

    static func addPinBody(to p: inout Path, g: LucideGrid) {
        p.move(to: g.pt(9, 10.76))
        p.addQuadCurve(to: g.pt(7.9, 12.55), control: g.pt(9, 12.0))
        p.addLine(to: g.pt(6.1, 13.45))
        p.addQuadCurve(to: g.pt(5, 15.24), control: g.pt(5, 14.0))
        p.addLine(to: g.pt(5, 16))
        p.addQuadCurve(to: g.pt(6, 17), control: g.pt(5, 17))
        p.addLine(to: g.pt(18, 17))
        p.addQuadCurve(to: g.pt(19, 16), control: g.pt(19, 17))
        p.addLine(to: g.pt(19, 15.24))
        p.addQuadCurve(to: g.pt(17.9, 13.45), control: g.pt(19, 14.0))
        p.addLine(to: g.pt(16.1, 12.55))
        p.addQuadCurve(to: g.pt(15, 10.76), control: g.pt(15, 12.0))
        p.addLine(to: g.pt(15, 7))
        p.addQuadCurve(to: g.pt(16, 6), control: g.pt(15, 6))
        p.addCurve(to: g.pt(16, 2), control1: g.pt(18.2, 6), control2: g.pt(18.2, 2))
        p.addLine(to: g.pt(8, 2))
        p.addCurve(to: g.pt(8, 6), control1: g.pt(5.8, 2), control2: g.pt(5.8, 6))
        p.addQuadCurve(to: g.pt(9, 7), control: g.pt(9, 6))
        p.closeSubpath()
    }

    private static func roundedClosedPolygon(_ points: [CGPoint], cornerRadius: CGFloat) -> Path {
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
            let r = min(cornerRadius, len1 * 0.42, len2 * 0.42)

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
