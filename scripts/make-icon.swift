// Draws the ClaudeMon app icon (orange asterisk with a speedometer overlaid) and writes
// Resources/AppIcon.icns. Run: xcrun swift scripts/make-icon.swift
import AppKit

let root = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().deletingLastPathComponent()

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255, alpha: alpha)
}

func drawIcon(in ctx: CGContext, size s: CGFloat) {
    ctx.saveGState()
    ctx.scaleBy(x: s / 1024, y: s / 1024)

    // macOS icon grid: 824 pt rounded square centred on a 1024 canvas.
    let plate = CGRect(x: 100, y: 100, width: 824, height: 824)
    let platePath = CGPath(roundedRect: plate, cornerWidth: 185, cornerHeight: 185, transform: nil)

    // Drop shadow under the plate.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: color(0x000000, 0.35))
    ctx.addPath(platePath)
    ctx.setFillColor(color(0x1d1b19))
    ctx.fillPath()
    ctx.restoreGState()

    // Plate: warm charcoal gradient.
    ctx.saveGState()
    ctx.addPath(platePath)
    ctx.clip()
    let bg = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                        colors: [color(0x34302c), color(0x161413)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(bg, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])

    let center = CGPoint(x: 512, y: 512)

    // Orange asterisk: six rounded arms, one pointing straight up like a typed "*".
    let orange = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                            colors: [color(0xf08a4b), color(0xd9622b)] as CFArray, locations: [0, 1])!
    let arm = CGMutablePath()
    for i in 0..<6 {
        let angle = CGFloat(i) * .pi / 3
        let t = CGAffineTransform(translationX: center.x, y: center.y).rotated(by: angle)
        arm.addRoundedRect(in: CGRect(x: -66, y: 0, width: 132, height: 352),
                           cornerWidth: 66, cornerHeight: 66, transform: t)
    }
    ctx.saveGState()
    ctx.addPath(arm)
    ctx.clip()
    ctx.drawLinearGradient(orange, start: CGPoint(x: 512, y: 880), end: CGPoint(x: 512, y: 140), options: [])
    ctx.restoreGState()

    // Speedometer dial overlaid on the asterisk's centre.
    let r: CGFloat = 178
    let k = r / 225 // dial details were laid out for r = 225
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 24, color: color(0x000000, 0.45))
    ctx.addEllipse(in: CGRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r))
    ctx.setFillColor(color(0x1f1c1a))
    ctx.fillPath()
    ctx.restoreGState()
    ctx.addEllipse(in: CGRect(x: center.x - r + 9 * k, y: center.y - r + 9 * k, width: 2 * r - 18 * k, height: 2 * r - 18 * k))
    ctx.setStrokeColor(color(0xf3efe9))
    ctx.setLineWidth(18 * k)
    ctx.strokePath()

    // Gauge sweeps 240°, from lower-left (210°) clockwise to lower-right (-30°).
    let start: CGFloat = 210 * .pi / 180, end: CGFloat = -30 * .pi / 180
    let sweep = start - end
    let bands: [(CGFloat, CGFloat, UInt32)] = [(0, 0.55, 0x3fbf6a), (0.55, 0.8, 0xf2a93b), (0.8, 1, 0xe5484d)]
    ctx.setLineCap(.butt)
    ctx.setLineWidth(30 * k)
    for (a, b, c) in bands {
        ctx.addArc(center: center, radius: r - 62 * k, startAngle: start - sweep * a,
                   endAngle: start - sweep * b, clockwise: true)
        ctx.setStrokeColor(color(c))
        ctx.strokePath()
    }

    // Tick marks.
    ctx.setStrokeColor(color(0xf3efe9))
    ctx.setLineCap(.round)
    for i in 0...8 {
        let a = start - sweep * CGFloat(i) / 8
        let major = i % 2 == 0
        let inner = r - (major ? 128 : 112) * k, outer = r - 92 * k
        ctx.setLineWidth((major ? 14 : 8) * k)
        ctx.move(to: CGPoint(x: center.x + cos(a) * inner, y: center.y + sin(a) * inner))
        ctx.addLine(to: CGPoint(x: center.x + cos(a) * outer, y: center.y + sin(a) * outer))
        ctx.strokePath()
    }

    // Needle at ~70%, tapered, with hub.
    let na = start - sweep * 0.7
    let tip = CGPoint(x: center.x + cos(na) * (r - 70 * k), y: center.y + sin(na) * (r - 70 * k))
    let perp = na + .pi / 2
    let needle = CGMutablePath()
    needle.move(to: tip)
    needle.addLine(to: CGPoint(x: center.x + cos(perp) * 16 * k, y: center.y + sin(perp) * 16 * k))
    needle.addLine(to: CGPoint(x: center.x - cos(na) * 40 * k, y: center.y - sin(na) * 40 * k))
    needle.addLine(to: CGPoint(x: center.x - cos(perp) * 16 * k, y: center.y - sin(perp) * 16 * k))
    needle.closeSubpath()
    ctx.addPath(needle)
    ctx.setFillColor(color(0xf08a4b))
    ctx.fillPath()
    ctx.addEllipse(in: CGRect(x: center.x - 30 * k, y: center.y - 30 * k, width: 60 * k, height: 60 * k))
    ctx.setFillColor(color(0xf3efe9))
    ctx.fillPath()

    ctx.restoreGState() // plate clip
    ctx.restoreGState()
}

func png(size: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!.cgContext
    drawIcon(in: ctx, size: CGFloat(size))
    return rep.representation(using: .png, properties: [:])!
}

let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try png(size: base).write(to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try png(size: base * 2).write(to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
let out = root.appendingPathComponent("Resources/AppIcon.icns")
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", iconset.path, "-o", out.path]
try p.run()
p.waitUntilExit()
try png(size: 1024).write(to: root.appendingPathComponent("Resources/AppIcon-1024.png"))
print(p.terminationStatus == 0 ? "Wrote \(out.path)" : "iconutil failed")
