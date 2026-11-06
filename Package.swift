// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CodexMacCore",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "CodexMacCore", path: ".",
                exclude: ["Widgets", "Tests", "Config", "Scripts", "README.md", "VERSION", "project.yml",
                          "App/Application.swift", "App/Monitor.swift", "App/Panel.swift", "App/Settings.swift",
                          "App/Views.swift", "App/Assets.xcassets"],
                sources: ["Core", "App/CodexClient.swift"]),
        .testTarget(name: "CoreTests", dependencies: ["CodexMacCore"], path: "Tests")
    ]
)
