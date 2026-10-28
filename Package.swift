// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "ClaudeLimits",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "ClaudeLimits", targets: ["ClaudeLimits"]),
        .executable(name: "ClaudeLimitsWidget", targets: ["ClaudeLimitsWidget"]),
    ],
    targets: [
        // Pure logic without AppKit: parsing, request schedule, thresholds, formatting.
        .target(name: "ClaudeLimitsCore"),
        .executableTarget(name: "ClaudeLimits", dependencies: ["ClaudeLimitsCore"]),
        // Desktop widget; build.sh wraps it into ClaudeLimits.app/Contents/PlugIns/*.appex.
        .executableTarget(name: "ClaudeLimitsWidget", dependencies: ["ClaudeLimitsCore"],
                          swiftSettings: [.unsafeFlags(["-application-extension"])],
                          linkerSettings: [.unsafeFlags(["-Xlinker", "-application_extension",
                                                         "-Xlinker", "-e", "-Xlinker", "_NSExtensionMain"])]),
        .testTarget(name: "ClaudeLimitsTests", dependencies: ["ClaudeLimitsCore"]),
    ]
)
