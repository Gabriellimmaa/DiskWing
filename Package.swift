// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DiskWing",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "CacheSSDCore", targets: ["CacheSSDCore"]),
        .executable(name: "CacheSSD", targets: ["CacheSSDApp"]),
        .executable(name: "CacheSSDHelper", targets: ["CacheSSDHelper"])
    ],
    targets: [
        .target(name: "CacheSSDCore"),
        .executableTarget(name: "CacheSSDApp", dependencies: ["CacheSSDCore"]),
        .executableTarget(name: "CacheSSDHelper", dependencies: ["CacheSSDCore"]),
        .testTarget(name: "CacheSSDCoreTests", dependencies: ["CacheSSDCore"])
    ],
    swiftLanguageModes: [.v5]
)
