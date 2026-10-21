// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AIBillingMeter",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "AIBillingMeter", targets: ["AIBillingMeter"]),
        // Linked by the Xcode project's app, tool and test targets (AIBillingMeter.xcodeproj).
        .library(name: "BillingMeterCore", targets: ["BillingMeterCore"]),
    ],
    targets: [
        // Pure logic: transcript parsing, pricing, aggregation, plan-limit client.
        .target(name: "BillingMeterCore"),
        // SwiftUI menu-bar app.
        .executableTarget(name: "AIBillingMeter", dependencies: ["BillingMeterCore"]),
        // Terminal report using the same core, for scripting and cross-checking the app.
        .executableTarget(name: "billing-meter", dependencies: ["BillingMeterCore"]),
        .testTarget(name: "BillingMeterCoreTests", dependencies: ["BillingMeterCore"]),
    ],
    swiftLanguageModes: [.v5]
)
