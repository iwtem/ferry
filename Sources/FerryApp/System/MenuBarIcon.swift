import AppKit

/// The 渡 Ferry menu bar glyph: a sailboat over one wave, drawn as a template image
/// so macOS tints it for light/dark menu bars. Geometry lives in a 24×24 design grid;
/// only the area the drawing actually covers (`artBox`) is mapped onto the image, so the
/// boat fills the full menu bar icon height like other status items do.
enum MenuBarIcon {
    /// Tight bounds of the drawing in the 24×24 grid (includes the wave's round caps).
    private static let artBox = CGRect(x: 1.2, y: 2.2, width: 21.6, height: 21.3)

    static func make(height: CGFloat = 18, accessibilityDescription: String) -> NSImage {
        let scale = height / artBox.height
        let size = NSSize(width: (artBox.width * scale).rounded(.up), height: height)

        let image = NSImage(size: size, flipped: true) { rect in
            var transform = AffineTransform(translationByX: -artBox.minX, byY: -artBox.minY)
            transform.append(AffineTransform(scale: scale))
            // Center horizontally if rounding widened the image.
            transform.append(AffineTransform(translationByX: (rect.width - artBox.width * scale) / 2, byY: 0))

            func polygon(_ points: [CGPoint]) -> NSBezierPath {
                let path = NSBezierPath()
                path.move(to: points[0])
                points.dropFirst().forEach { path.line(to: $0) }
                path.close()
                path.transform(using: transform)
                return path
            }

            NSColor.black.setFill()
            NSColor.black.setStroke()

            // Main sail
            polygon([CGPoint(x: 11.6, y: 2.4), CGPoint(x: 11.6, y: 14), CGPoint(x: 2.8, y: 14)]).fill()
            // Jib, slightly lighter so the two sails read as separate shapes
            NSColor.black.withAlphaComponent(0.85).setFill()
            polygon([CGPoint(x: 13.0, y: 4.6), CGPoint(x: 13.0, y: 14), CGPoint(x: 20.6, y: 14)]).fill()
            NSColor.black.setFill()
            // Hull
            polygon([CGPoint(x: 2.2, y: 15.2), CGPoint(x: 21.8, y: 15.2), CGPoint(x: 19.2, y: 18.4), CGPoint(x: 4.8, y: 18.4)]).fill()

            // Wave: four quadratic segments alternating above/below y = 21.2
            let wave = NSBezierPath()
            var x: CGFloat = 2.4
            let y: CGFloat = 21.2
            wave.move(to: CGPoint(x: x, y: y))
            for i in 0..<4 {
                let dy: CGFloat = i.isMultiple(of: 2) ? -1.6 : 1.6
                let start = CGPoint(x: x, y: y)
                let end = CGPoint(x: x + 4.8, y: y)
                let control = CGPoint(x: x + 2.4, y: y + dy)
                // Quadratic → cubic control points for NSBezierPath.
                let c1 = CGPoint(x: start.x + 2 / 3 * (control.x - start.x), y: start.y + 2 / 3 * (control.y - start.y))
                let c2 = CGPoint(x: end.x + 2 / 3 * (control.x - end.x), y: end.y + 2 / 3 * (control.y - end.y))
                wave.curve(to: end, controlPoint1: c1, controlPoint2: c2)
                x += 4.8
            }
            wave.transform(using: transform)
            wave.lineWidth = 2.0 * scale
            wave.lineCapStyle = .round
            wave.stroke()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = accessibilityDescription
        return image
    }
}
