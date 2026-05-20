import XCTest
@testable import OmniVoiceCore

final class DiarizationProviderResolutionTests: XCTestCase {
    func testEffectiveProviderKeepsPreferredProviderBeforeStatusLoads() {
        XCTAssertEqual(
            DiarizationProviderResolution.effectiveProviderID(
                preferred: "mlx-sortformer-streaming-fp32",
                knownProvider: nil
            ),
            "mlx-sortformer-streaming-fp32"
        )
    }

    func testEffectiveProviderFallsBackOnlyWhenKnownProviderIsUnavailable() {
        let unavailable = EngineProviderInfo(
            id: "mlx-sortformer-streaming-fp32",
            label: "MLX Sortformer Streaming FP32",
            available: false,
            reason: "missing model"
        )

        XCTAssertEqual(
            DiarizationProviderResolution.effectiveProviderID(
                preferred: "mlx-sortformer-streaming-fp32",
                knownProvider: unavailable
            ),
            "none"
        )
    }

    func testEffectiveProviderRejectsOffAndUnsupportedProviders() {
        XCTAssertEqual(
            DiarizationProviderResolution.effectiveProviderID(
                preferred: "none",
                knownProvider: nil
            ),
            "none"
        )
        XCTAssertEqual(
            DiarizationProviderResolution.effectiveProviderID(
                preferred: "local-heuristic",
                knownProvider: nil
            ),
            "none"
        )
    }

    func testLiveConversationStreamFollowsEnabledDiarizationProvider() {
        XCTAssertTrue(
            DiarizationProviderResolution.usesLiveConversationStream(
                preferred: "mlx-sortformer-streaming-fp32",
                knownProvider: nil
            )
        )

        XCTAssertFalse(
            DiarizationProviderResolution.usesLiveConversationStream(
                preferred: "none",
                knownProvider: nil
            )
        )
    }
}
