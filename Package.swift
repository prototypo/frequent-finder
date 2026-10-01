// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FrequentFinder",
    platforms: [.macOS(.v15)],
    targets: [
        .target(name: "FFCore"),
        .executableTarget(name: "ff", dependencies: ["FFCore"]),
        .executableTarget(name: "FrequentFinder", dependencies: ["FFCore"], path: "Sources/FFApp"),
        .testTarget(name: "FFCoreTests", dependencies: ["FFCore"]),
    ],
    swiftLanguageModes: [.v5]
)
