// Draws the AI Billing Meter app icon (a rainbow asterisk seen through a HAL 9000-style
// fisheye lens, with a speedometer overlaid) and writes
// Resources/AppIcon.icns. Run: xcrun swift scripts/make-icon.swift
import AppKit

let root = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().deletingLastPathComponent()

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255, alpha: alpha)
}

/// The rainbow asterisk as seen through a fisheye lens of the given radius: a radial remap that
/// magnifies the centre and compresses toward the rim, so the arms' straight edges bow outward.
/// Six rounded arms, one pointing straight up like a typed "*", coloured red → violet going
/// clockwise from the top, each shaded lighter toward its tip.
func fisheyeAsterisk(lensRadius lensR: CGFloat) -> CGImage? {
    let n = 1024
    let center = CGPoint(x: 512, y: 512)
    guard let src = CGContext(data: nil, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n * 4,
                              space: CGColorSpace(name: CGColorSpace.sRGB)!,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    let rainbow: [(UInt32, UInt32)] = [(0xf26b6b, 0xd93f45), (0xf7a35c, 0xe0742c), (0xf7d35a, 0xe0ac21),
                                       (0x5fd17f, 0x2f9e55), (0x5f9ef7, 0x2f6fd9), (0xa682f7, 0x7a4fd9)]
    for (i, (tipColor, baseColor)) in rainbow.enumerated() {
        // CG rotation is counterclockwise, so arm i sits at -i × 60°.
        let angle = -CGFloat(i) * .pi / 3
        let t = CGAffineTransform(translationX: center.x, y: center.y).rotated(by: angle)
        let arm = CGPath(roundedRect: CGRect(x: -66, y: 0, width: 132, height: 352),
                         cornerWidth: 66, cornerHeight: 66, transform: [t])
        let shade = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                               colors: [color(baseColor), color(tipColor)] as CFArray, locations: [0, 1])!
        src.saveGState()
        src.addPath(arm)
        src.clip()
        src.drawLinearGradient(shade, start: center,
                               end: CGPoint(x: center.x - sin(angle) * 352, y: center.y + cos(angle) * 352),
                               options: [])
        src.restoreGState()
    }
    guard let input = src.data?.assumingMemoryBound(to: UInt8.self),
          let dst = CGContext(data: nil, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n * 4,
                              space: CGColorSpace(name: CGColorSpace.sRGB)!,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
          let output = dst.data?.assumingMemoryBound(to: UInt8.self) else { return nil }
    // Output radius d shows source radius S·(d/R)^1.8, sampled bilinearly. S is larger than the
    // lens, so the whole asterisk fits inside the rim, squeezed toward it like a wide-angle view.
    let r = Double(lensR), sourceRadius = 400.0
    for row in 0..<n {
        for col in 0..<n {
            let dx = Double(col) + 0.5 - 512, dy = Double(row) + 0.5 - 512
            let d = (dx * dx + dy * dy).squareRoot()
            guard d < r, d > 0 else { continue }
            let scale = sourceRadius * pow(d / r, 1.8) / d
            let sx = 512 + dx * scale - 0.5, sy = 512 + dy * scale - 0.5
            let x0 = Int(sx.rounded(.down)), y0 = Int(sy.rounded(.down))
            guard x0 >= 0, y0 >= 0, x0 + 1 < n, y0 + 1 < n else { continue }
            let fx = sx - Double(x0), fy = sy - Double(y0)
            for c in 0..<4 {
                func p(_ x: Int, _ y: Int) -> Double { Double(input[(y * n + x) * 4 + c]) }
                let v = (p(x0, y0) * (1 - fx) + p(x0 + 1, y0) * fx) * (1 - fy)
                    + (p(x0, y0 + 1) * (1 - fx) + p(x0 + 1, y0 + 1) * fx) * fy
                output[(row * n + col) * 4 + c] = UInt8(min(255, v.rounded()))
            }
        }
    }
    return dst.makeImage()
}

/// Rendered once at 1024 and reused for every icon size.
var cachedAsterisk: CGImage?

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

    // HAL 9000-style lens: a metal bezel around dark glass, through which the rainbow asterisk is
    // seen with fisheye distortion, then red glow and reflections on the glass.
    let lensR: CGFloat = 350
    let bezel: CGFloat = 46
    func disc(_ radius: CGFloat) -> CGRect {
        CGRect(x: center.x - radius, y: center.y - radius, width: 2 * radius, height: 2 * radius)
    }
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    func gradient(_ stops: [(UInt32, CGFloat, CGFloat)]) -> CGGradient {
        CGGradient(colorsSpace: space, colors: stops.map { color($0.0, $0.1) } as CFArray,
                   locations: stops.map(\.2))!
    }

    // Bezel: brushed metal ring, light at the top, with a dark groove where the glass is seated.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -6), blur: 18, color: color(0x000000, 0.6))
    ctx.addEllipse(in: disc(lensR + bezel))
    ctx.setFillColor(color(0x2a2724))
    ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addEllipse(in: disc(lensR + bezel))
    ctx.addEllipse(in: disc(lensR))
    ctx.clip(using: .evenOdd)
    ctx.drawLinearGradient(gradient([(0xe9e6e1, 1, 0), (0x8d8882, 1, 0.45), (0x4a4642, 1, 0.7), (0xb5b0a9, 1, 1)]),
                           start: CGPoint(x: 512, y: 512 + lensR + bezel), end: CGPoint(x: 512, y: 512 - lensR - bezel),
                           options: [])
    ctx.restoreGState()
    ctx.addEllipse(in: disc(lensR + 3))
    ctx.setStrokeColor(color(0x0b0a09))
    ctx.setLineWidth(8)
    ctx.strokePath()

    // Glass: near-black, with the asterisk seen through it.
    ctx.saveGState()
    ctx.addEllipse(in: disc(lensR))
    ctx.clip()
    ctx.setFillColor(color(0x070505))
    ctx.fill(disc(lensR))
    if cachedAsterisk == nil { cachedAsterisk = fisheyeAsterisk(lensRadius: lensR) }
    if let warped = cachedAsterisk {
        ctx.draw(warped, in: CGRect(x: 0, y: 0, width: 1024, height: 1024))
    }
    // Darken toward the rim as a curved lens does, and let a red glow rise from the centre.
    ctx.drawRadialGradient(gradient([(0x000000, 0, 0), (0x000000, 0, 0.55), (0x000000, 0.55, 0.88), (0x000000, 0.9, 1)]),
                           startCenter: center, startRadius: 0, endCenter: center, endRadius: lensR, options: [])
    ctx.setBlendMode(.screen)
    ctx.drawRadialGradient(gradient([(0xff3b1f, 0.9, 0), (0xd4180c, 0.55, 0.62), (0x6e0a05, 0.25, 0.8), (0x000000, 0, 1)]),
                           startCenter: center, startRadius: 0, endCenter: center, endRadius: lensR, options: [])
    ctx.setBlendMode(.normal)
    // Reflections: a broad crescent at the top left and a small window glint, a faint rim at the bottom right.
    let crescent = CGMutablePath()
    crescent.addEllipse(in: CGRect(x: center.x - 318, y: center.y - 40, width: 560, height: 380))
    let cut = CGMutablePath()
    cut.addEllipse(in: CGRect(x: center.x - 268, y: center.y - 92, width: 600, height: 400))
    ctx.saveGState()
    ctx.addPath(crescent)
    ctx.addPath(cut)
    ctx.clip(using: .evenOdd)
    ctx.addPath(crescent)
    ctx.clip()
    ctx.drawLinearGradient(gradient([(0xffffff, 0.42, 0), (0xffffff, 0.08, 1)]),
                           start: CGPoint(x: center.x - 260, y: center.y + 300), end: CGPoint(x: center.x + 40, y: center.y),
                           options: [])
    ctx.restoreGState()
    ctx.drawRadialGradient(gradient([(0xffffff, 0.85, 0), (0xffffff, 0, 1)]),
                           startCenter: CGPoint(x: center.x - 196, y: center.y + 236), startRadius: 0,
                           endCenter: CGPoint(x: center.x - 196, y: center.y + 236), endRadius: 34, options: [])
    ctx.addArc(center: center, radius: lensR - 18, startAngle: -.pi * 0.42, endAngle: -.pi * 0.08, clockwise: false)
    ctx.setStrokeColor(color(0xffffff, 0.16))
    ctx.setLineWidth(10)
    ctx.setLineCap(.round)
    ctx.strokePath()
    ctx.restoreGState()

    // Speedometer dial overlaid on the asterisk's centre.
    let r: CGFloat = 231 // 178 × 1.3
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
