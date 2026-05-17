import XCTest
@testable import OmniVoiceCore

final class CaptionOverlayLayoutTests: XCTestCase {
    func testLiveOverlayUsesReadableWrappedCaptionLayout() {
        XCTAssertEqual(CaptionOverlayLayout.captionWidth, 620)
        XCTAssertEqual(CaptionOverlayLayout.captionLineLimit, 5)
        XCTAssertLessThan(CaptionOverlayLayout.captionWidth, CaptionOverlayLayout.windowMaxWidth)
    }

    func testStyleLabelIsRenderedBelowWaveform() {
        XCTAssertEqual(
            CaptionOverlayLayout.liveStackOrder,
            [.captionText, .waveformMeter, .styleLabel]
        )
    }
}
