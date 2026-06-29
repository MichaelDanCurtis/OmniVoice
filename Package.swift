// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "OmniVoice",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "OmniVoiceApp", targets: ["OmniVoiceApp"]),
        .library(name: "OmniVoiceCore", targets: ["OmniVoiceCore"]),
    ],
    dependencies: [
        // Sparkle: auto-update framework for Developer ID (non-App Store) distribution.
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
    ],
    targets: [
        .target(name: "OmniVoiceCore"),
        .executableTarget(
            name: "OmniVoiceApp",
            dependencies: [
                "OmniVoiceCore",
                .product(name: "Sparkle", package: "Sparkle"),
            ]
        ),
        .testTarget(
            name: "OmniVoiceCoreTests",
            dependencies: ["OmniVoiceCore"]
        ),
    ]
)
