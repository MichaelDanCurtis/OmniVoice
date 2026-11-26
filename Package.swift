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
        // FluidAudio: CoreML / Apple Neural Engine Parakeet TDT & Sortformer diarization.
        .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.18.4"),
        // MLX Swift LM: in-process Apple Silicon Metal LLM inference (Qwen3 1.7B/4B 4-bit).
        .package(url: "https://github.com/ml-explore/mlx-swift-lm", from: "3.32.3"),
        .package(url: "https://github.com/huggingface/swift-huggingface", from: "0.9.0"),
        .package(url: "https://github.com/huggingface/swift-transformers", from: "1.3.0"),
    ],
    targets: [
        .target(name: "OmniVoiceCore"),
        .executableTarget(
            name: "OmniVoiceApp",
            dependencies: [
                "OmniVoiceCore",
                .product(name: "Sparkle", package: "Sparkle"),
                .product(name: "FluidAudio", package: "FluidAudio"),
                .product(name: "MLXLLM", package: "mlx-swift-lm"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
                .product(name: "MLXHuggingFace", package: "mlx-swift-lm"),
                .product(name: "HuggingFace", package: "swift-huggingface"),
                .product(name: "Tokenizers", package: "swift-transformers"),
            ]
        ),
        .testTarget(
            name: "OmniVoiceCoreTests",
            dependencies: ["OmniVoiceCore"]
        ),
    ]
)
