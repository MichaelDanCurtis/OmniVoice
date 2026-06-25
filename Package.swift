// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "OmniVoice",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "OmniVoiceApp", targets: ["OmniVoiceApp"]),
        .library(name: "OmniVoiceCore", targets: ["OmniVoiceCore"]),
    ],
    targets: [
        .target(name: "OmniVoiceCore"),
        .executableTarget(
            name: "OmniVoiceApp",
            dependencies: ["OmniVoiceCore"]
        ),
        .testTarget(
            name: "OmniVoiceCoreTests",
            dependencies: ["OmniVoiceCore"]
        ),
        .testTarget(
            name: "OmniVoiceAppTests",
            dependencies: ["OmniVoiceApp"]
        ),
    ]
)
