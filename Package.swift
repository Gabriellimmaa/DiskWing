// swift-tools-version: 6.0
import PackageDescription
import Foundation

let updaterEnabled = ProcessInfo.processInfo.environment["DISKWING_ENABLE_UPDATER"] == "1"

let package = Package(
    name: "DiskWing",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "CacheSSDCore", targets: ["CacheSSDCore"]),
        .executable(name: "CacheSSD", targets: ["CacheSSDApp"]),
        .executable(name: "CacheSSDHelper", targets: ["CacheSSDHelper"])
    ],
    dependencies: updaterEnabled ? [.package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.1")] : [],
    targets: [
        .systemLibrary(name: "CSQLite", path: "Sources/CSQLite"),
        .target(name: "CacheSSDCore", dependencies: ["CSQLite"], resources: [.process("Resources")]),
        .executableTarget(name: "CacheSSDApp", dependencies: [.target(name: "CacheSSDCore")] + (updaterEnabled ? [.product(name: "Sparkle", package: "Sparkle")] : []), swiftSettings: updaterEnabled ? [.define("DISKWING_UPDATER")] : [], linkerSettings: updaterEnabled ? [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])] : []),
        .executableTarget(name: "CacheSSDHelper", dependencies: ["CacheSSDCore"]),
        .testTarget(name: "CacheSSDCoreTests", dependencies: ["CacheSSDCore"])
    ],
    swiftLanguageModes: [.v5]
)
