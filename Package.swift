// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FrequentFinder",
    platforms: [.macOS(.v15)],
    targets: [
        .target(name: "FFCore"),
        .testTarget(name: "FFCoreTests", dependencies: ["FFCore"]),
    ],
    swiftLanguageModes: [.v5]
)
