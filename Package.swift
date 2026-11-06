// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CodexMacCore",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "CodexMacCore", path: "Core"),
        .testTarget(name: "CoreTests", dependencies: ["CodexMacCore"], path: "Tests")
    ]
)
