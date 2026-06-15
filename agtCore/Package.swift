// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "agtCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "agtCore", targets: ["agtCore"]),
    ],
    targets: [
        .target(name: "agtCore"),
        .testTarget(name: "agtCoreTests", dependencies: ["agtCore"]),
    ],
    swiftLanguageModes: [.v6]
)
