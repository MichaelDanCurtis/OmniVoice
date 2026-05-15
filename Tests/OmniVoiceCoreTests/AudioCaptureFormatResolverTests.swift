import XCTest
@testable import OmniVoiceCore

final class AudioCaptureFormatResolverTests: XCTestCase {
    func testSelectedDeviceSampleRateWinsOverStaleNodeSampleRate() {
        let sampleRate = AudioCaptureFormatResolver.sampleRate(
            selectedDeviceSampleRate: 48_000,
            nodeSampleRate: 96_000
        )

        XCTAssertEqual(sampleRate, 48_000)
    }

    func testNodeSampleRateIsUsedWhenDeviceRateIsUnavailable() {
        let sampleRate = AudioCaptureFormatResolver.sampleRate(
            selectedDeviceSampleRate: nil,
            nodeSampleRate: 96_000
        )

        XCTAssertEqual(sampleRate, 96_000)
    }

    func testFallsBackToSixteenKilohertzWhenRatesAreInvalid() {
        let sampleRate = AudioCaptureFormatResolver.sampleRate(
            selectedDeviceSampleRate: 0,
            nodeSampleRate: 0
        )

        XCTAssertEqual(sampleRate, 16_000)
    }
}
