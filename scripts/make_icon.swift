// Draws the app icon: three lanes seen from the driver's seat, the right lane lit with a turn arrow.
// Run: swift scripts/make_icon.swift Baxi/Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png
import AppKit

let size = 1024.0
let out = CommandLine.arguments.dropFirst().first ?? "icon-1024.png"
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext

// Background: the Drive card green, lighter at the top.
let green = CGColor(red: 0.07, green: 0.33, blue: 0.22, alpha: 1)
let light = CGColor(red: 0.13, green: 0.50, blue: 0.34, alpha: 1)
ctx.drawLinearGradient(CGGradient(colorsSpace: nil, colors: [green, light] as CFArray, locations: [0, 1])!,
                       start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: size), options: [])

// The road in perspective: a trapezoid narrowing toward the horizon.
let road = CGMutablePath()
road.move(to: CGPoint(x: 90, y: 0)); road.addLine(to: CGPoint(x: 934, y: 0))
road.addLine(to: CGPoint(x: 640, y: 700)); road.addLine(to: CGPoint(x: 384, y: 700)); road.closeSubpath()
ctx.addPath(road); ctx.setFillColor(CGColor(gray: 0.12, alpha: 1)); ctx.fillPath()

// The right lane, lit.
let lit = CGMutablePath()
lit.move(to: CGPoint(x: 653, y: 0)); lit.addLine(to: CGPoint(x: 934, y: 0))
lit.addLine(to: CGPoint(x: 640, y: 700)); lit.addLine(to: CGPoint(x: 555, y: 700)); lit.closeSubpath()
ctx.addPath(lit); ctx.setFillColor(CGColor(red: 1, green: 0.85, blue: 0.25, alpha: 1)); ctx.fillPath()

// Dashed lane lines.
ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.9)); ctx.setLineCap(.round)
for (bottomX, topX) in [(371.0, 469.0)] {
    for i in 0..<5 {
        let t0 = Double(i) / 5 + 0.03, t1 = t0 + 0.11
        ctx.setLineWidth(26 * (1 - t0 * 0.7))
        ctx.move(to: CGPoint(x: bottomX + (topX - bottomX) * t0, y: 700 * t0))
        ctx.addLine(to: CGPoint(x: bottomX + (topX - bottomX) * t1, y: 700 * t1))
        ctx.strokePath()
    }
}

// Turn arrow in the lit lane.
let arrow = CGMutablePath()
arrow.move(to: CGPoint(x: 700, y: 50)); arrow.addLine(to: CGPoint(x: 700, y: 210))
arrow.addQuadCurve(to: CGPoint(x: 745, y: 290), control: CGPoint(x: 700, y: 290))
ctx.addPath(arrow); ctx.setStrokeColor(CGColor(gray: 0.12, alpha: 1)); ctx.setLineWidth(46); ctx.setLineCap(.butt); ctx.strokePath()
let head = CGMutablePath()
head.move(to: CGPoint(x: 805, y: 290)); head.addLine(to: CGPoint(x: 742, y: 345)); head.addLine(to: CGPoint(x: 742, y: 235)); head.closeSubpath()
ctx.addPath(head); ctx.setFillColor(CGColor(gray: 0.12, alpha: 1)); ctx.fillPath()

// A speech mark above the horizon: Baxi says it early.
let bubble = CGRect(x: 392, y: 770, width: 240, height: 160)
ctx.addPath(CGPath(roundedRect: bubble, cornerWidth: 70, cornerHeight: 70, transform: nil))
ctx.setFillColor(CGColor(gray: 1, alpha: 1)); ctx.fillPath()
let tail = CGMutablePath()
tail.move(to: CGPoint(x: 470, y: 780)); tail.addLine(to: CGPoint(x: 440, y: 725)); tail.addLine(to: CGPoint(x: 530, y: 780)); tail.closeSubpath()
ctx.addPath(tail); ctx.fillPath()
ctx.setFillColor(green)
for x in [452.0, 512.0, 572.0] { ctx.fillEllipse(in: CGRect(x: x - 22, y: 828, width: 44, height: 44)) }

NSGraphicsContext.current = nil
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
