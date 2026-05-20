import XCTest
@testable import OmniVoiceCore

final class CaptionOverlayLayoutTests: XCTestCase {
    func testLiveOverlayUsesReadableWrappedCaptionLayout() {
        XCTAssertEqual(CaptionOverlayLayout.captionWidth, 620)
        XCTAssertEqual(CaptionOverlayLayout.captionLineLimit, 5)
        XCTAssertLessThan(CaptionOverlayLayout.captionWidth, CaptionOverlayLayout.windowMaxWidth)
        XCTAssertGreaterThanOrEqual(CaptionOverlayLayout.haloBleedPaddingHorizontal, 40)
        XCTAssertGreaterThanOrEqual(CaptionOverlayLayout.haloBleedPaddingVertical, 24)
    }

    func testTranslationStatusIsRenderedAboveCaptionWhenPresent() {
        XCTAssertEqual(
            CaptionOverlayLayout.liveStackOrder,
            [.translationStatus, .captionText, .waveformMeter, .styleLabel]
        )
    }
}
