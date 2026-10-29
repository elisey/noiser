// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "noiser",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "noiser",
            path: "Sources/noiser",
            // AppKit delegates and the audio render block share state through atomics;
            // the strict-concurrency checker of mode 6 has no model for that and only adds noise.
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "noiserTests",
            dependencies: ["noiser"],
            path: "Tests/noiserTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
