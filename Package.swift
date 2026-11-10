// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "RetroEQ",
    platforms: [.macOS(.v15)],
    targets: [
        // Real-time DSP and the Core Audio IOProc live in C so the audio thread never touches Swift runtime/ARC.
        .target(name: "EQDSP"),
        .executableTarget(
            name: "RetroEQ",
            dependencies: ["EQDSP"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
