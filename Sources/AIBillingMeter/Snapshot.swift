import AppKit
import BillingMeterCore
import SwiftUI

/// `AI Billing Meter --snapshot <dir>` renders the popover for each period, in light and dark,
/// to PNG files and exits. Used to check layout without opening the menu bar. Plan limits
/// are sample values so the Keychain is never touched.
@MainActor
enum Snapshot {
    static var outputDirectory: URL? {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count else { return nil }
        return URL(fileURLWithPath: args[i + 1], isDirectory: true)
    }

    static func run(to dir: URL) async {
        let model = AppModel(snapshot: true)
        await model.refreshTranscripts()
        let reset = Date().addingTimeInterval(2.5 * 3600)
        model.setPlanStatusForSnapshot(PlanStatus(
            plan: Plan(subscriptionType: "max", rateLimitTier: "default_claude_max_5x"),
            limits: [
                PlanLimit(id: "session#0", title: "Session (5 h)", group: "session", percentUsed: 42,
                          resetsAt: reset, severity: "normal"),
                PlanLimit(id: "weekly_all#1", title: "Weekly · all models", group: "weekly", percentUsed: 76,
                          resetsAt: Date().addingTimeInterval(4 * 86_400), severity: "normal"),
            ],
            fetchedAt: Date()))
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let defaults = UserDefaults.standard
        let saved = defaults.string(forKey: "selectedPeriod")
        for scheme in [ColorScheme.light, .dark] {
            for period in ReportPeriod.allCases {
                defaults.set(period.rawValue, forKey: "selectedPeriod")
                let view = MenuContentView(model: model)
                    .environment(\.colorScheme, scheme)
                    .background(scheme == .dark ? Color(white: 0.16) : Color(white: 0.96))
                let renderer = ImageRenderer(content: view)
                renderer.scale = 2
                if let img = renderer.nsImage, let tiff = img.tiffRepresentation,
                   let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                    try? png.write(to: dir.appendingPathComponent("\(period.rawValue)-\(scheme == .dark ? "dark" : "light").png"))
                }
            }
        }
        defaults.set(saved, forKey: "selectedPeriod")
        exit(0)
    }
}
