// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FrequentFinder",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "FFCore", targets: ["FFCore"]),
        .executable(name: "ff", targets: ["ff"]),
        .executable(name: "FrequentFinder", targets: ["FrequentFinder"]),
        .executable(name: "FrequentFinderDeck", targets: ["FrequentFinderDeck"]),
    ],
    targets: [
        .target(name: "FFCore"),
        .executableTarget(name: "ff", dependencies: ["FFCore"]),
        .executableTarget(name: "FrequentFinder", dependencies: ["FFCore"], path: "Sources/FFApp"),
        .executableTarget(name: "FrequentFinderDeck", dependencies: ["FFCore"], path: "Sources/FFDeck"),
        .testTarget(name: "FFCoreTests", dependencies: ["FFCore"]),
    ],
    swiftLanguageModes: [.v5]
)
