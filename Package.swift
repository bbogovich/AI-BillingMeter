// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ClaudeMon",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "ClaudeMon", targets: ["ClaudeMon"]),
    ],
    targets: [
        // Pure logic: transcript parsing, pricing, aggregation, plan-limit client.
        .target(name: "ClaudeMonCore"),
        // SwiftUI menu-bar app.
        .executableTarget(name: "ClaudeMon", dependencies: ["ClaudeMonCore"]),
        // Terminal report using the same core, for scripting and cross-checking the app.
        .executableTarget(name: "claudemon-report", dependencies: ["ClaudeMonCore"]),
        .testTarget(name: "ClaudeMonCoreTests", dependencies: ["ClaudeMonCore"]),
    ],
    swiftLanguageModes: [.v5]
)
