// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ClaudeUsageBar",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "UsageCore"),
        .executableTarget(
            name: "ClaudeUsageBar",
            dependencies: ["UsageCore"]
        ),
        .testTarget(
            name: "UsageCoreTests",
            dependencies: ["UsageCore"]
        ),
    ]
)
