// Renders the full-bleed 1024×1024 master artwork for the 渡 Ferry app icon (青碧 palette).
// build_app.sh clips this master into the macOS squircle, so the art here is a plain square.
//
// Usage: swift Scripts/render_app_icon.swift Resources/AppIconMaster.png
import AppKit
import CoreGraphics

let outputPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Resources/AppIconMaster.png"
let size = 1024

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

// 青碧 palette
let bgTop = rgb(0x3FD6C6)
let bgBottom = rgb(0x0F97A8)
let sail = rgb(0xFFFFFF)
let jib = rgb(0xFF8A5B)

guard let ctx = CGContext(
    data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpace(name: CGColorSpace.sRGB)!,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else { fatalError("Cannot create bitmap context") }

// Work in the same 100×100, y-down space as the SVG design.
ctx.translateBy(x: 0, y: CGFloat(size))
ctx.scaleBy(x: CGFloat(size) / 100, y: -CGFloat(size) / 100)

// Background gradient (top → bottom)
let gradient = CGGradient(colorsSpace: nil, colors: [bgTop, bgBottom] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(gradient, start: CGPoint(x: 50, y: 0), end: CGPoint(x: 50, y: 100), options: [])

func fill(_ points: [CGPoint], _ color: CGColor) {
    ctx.beginPath()
    ctx.addLines(between: points)
    ctx.closePath()
    ctx.setFillColor(color)
    ctx.fillPath()
}

// Main sail, jib, hull
fill([CGPoint(x: 49, y: 19), CGPoint(x: 49, y: 58), CGPoint(x: 26, y: 58)], sail)
fill([CGPoint(x: 53, y: 29), CGPoint(x: 53, y: 58), CGPoint(x: 71, y: 58)], jib)
fill([CGPoint(x: 23, y: 62), CGPoint(x: 77, y: 62), CGPoint(x: 70, y: 71), CGPoint(x: 30, y: 71)], sail)

// Waves: smooth quadratic chains that alternate above/below the baseline
func wave(startX: CGFloat, y: CGFloat, segments: Int, period: CGFloat, amplitude: CGFloat, width: CGFloat, color: CGColor) {
    ctx.beginPath()
    ctx.move(to: CGPoint(x: startX, y: y))
    var x = startX
    for i in 0..<segments {
        let dy = i.isMultiple(of: 2) ? -amplitude : amplitude
        ctx.addQuadCurve(to: CGPoint(x: x + period, y: y), control: CGPoint(x: x + period / 2, y: y + dy))
        x += period
    }
    ctx.setStrokeColor(color)
    ctx.setLineWidth(width)
    ctx.setLineCap(.round)
    ctx.strokePath()
}
wave(startX: 16, y: 80, segments: 4, period: 17, amplitude: 5, width: 3.5, color: sail)
wave(startX: 24.5, y: 88, segments: 3, period: 17, amplitude: 4, width: 3, color: rgb(0xFFFFFF, 0.4))

guard let image = ctx.makeImage() else { fatalError("Cannot render image") }
let rep = NSBitmapImageRep(cgImage: image)
guard let png = rep.representation(using: .png, properties: [:]) else { fatalError("Cannot encode PNG") }
try png.write(to: URL(fileURLWithPath: outputPath))
print("Wrote \(outputPath)")
