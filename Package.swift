// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "ClaudeNotify",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(name: "ClaudeNotify", path: "Sources/ClaudeNotify",
                          swiftSettings: [.swiftLanguageMode(.v5)])
    ]
)
