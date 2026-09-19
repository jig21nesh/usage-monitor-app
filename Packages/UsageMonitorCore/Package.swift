// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "UsageMonitorCore",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "UsageMonitorCore", targets: ["UsageMonitorCore"]),
    ],
    targets: [
        .target(
            name: "UsageMonitorCore",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "UsageMonitorCoreTests",
            dependencies: ["UsageMonitorCore"],
            resources: [.copy("Fixtures")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
