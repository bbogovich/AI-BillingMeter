import AppKit
import SwiftUI

/// Colours from the validated data-viz reference palette, stepped separately for light
/// and dark. Model families map to fixed categorical slots so a colour always means the
/// same family, whatever is on screen.
enum Theme {
    static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return NSColor(hex: isDark ? dark : light)
        })
    }

    static let familyOrder = ["Opus", "Sonnet", "Haiku", "Fable", "Mythos", "Other"]

    static let familyColors: [Color] = [
        dynamic(light: 0x2a78d6, dark: 0x3987e5), // blue
        dynamic(light: 0xeb6834, dark: 0xd95926), // orange
        dynamic(light: 0x1baf7a, dark: 0x199e70), // aqua
        dynamic(light: 0xeda100, dark: 0xc98500), // yellow
        dynamic(light: 0xe87ba4, dark: 0xd55181), // magenta
        dynamic(light: 0x6250d6, dark: 0x9085e9), // violet
    ]

    static func color(forFamily family: String) -> Color {
        familyColors[familyOrder.firstIndex(of: family) ?? familyOrder.count - 1]
    }

    // Status colours: reserved for limit severity, always paired with a label/icon.
    static let good = Color(nsColor: NSColor(hex: 0x0ca30c))
    static let warning = Color(nsColor: NSColor(hex: 0xfab219))
    static let critical = Color(nsColor: NSColor(hex: 0xd03b3b))

    static func status(forPercentUsed p: Double) -> (Color, String) {
        switch p {
        case ..<70: (good, "checkmark.circle.fill")
        case ..<90: (warning, "exclamationmark.triangle.fill")
        default: (critical, "xmark.octagon.fill")
        }
    }
}

extension NSColor {
    convenience init(hex: UInt32) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xff) / 255,
                  green: CGFloat((hex >> 8) & 0xff) / 255,
                  blue: CGFloat(hex & 0xff) / 255, alpha: 1)
    }
}

enum Format {
    static func tokens(_ n: Int) -> String {
        let d = Double(n)
        switch abs(d) {
        case 1_000_000_000...: return String(format: "%.2fB", d / 1_000_000_000)
        case 1_000_000...: return String(format: "%.1fM", d / 1_000_000)
        case 1_000...: return String(format: "%.1fK", d / 1_000)
        default: return "\(n)"
        }
    }

    static func usd(_ v: Double) -> String {
        v.formatted(.currency(code: "USD").precision(.fractionLength(v >= 1000 ? 0 : 2)))
    }

    static func percent(_ p: Double) -> String { "\(Int(p.rounded()))%" }

    static func relative(_ date: Date, now: Date = Date()) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f.localizedString(for: date, relativeTo: now)
    }

    static func resetText(_ date: Date?) -> String {
        guard let date else { return "" }
        let s = date.timeIntervalSinceNow
        if s <= 0 { return "resetting" }
        let h = Int(s) / 3600, m = (Int(s) % 3600) / 60
        let span = h >= 24 ? "\(h / 24)d \(h % 24)h" : h > 0 ? "\(h)h \(m)m" : "\(m)m"
        return "resets in \(span) · \(date.formatted(.dateTime.weekday(.abbreviated).hour().minute()))"
    }
}
