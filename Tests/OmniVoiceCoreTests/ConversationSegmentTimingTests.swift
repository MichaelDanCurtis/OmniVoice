import XCTest
@testable import OmniVoiceCore

final class ConversationSegmentTimingTests: XCTestCase {
    func testFinalSegmentStartsAtPreviousSettledEndAndCarriesAudioContext() {
        var timing = ConversationSegmentTiming()

        let first = timing.segment(nowMs: 8_000, isFinal: true)
        let live = timing.segment(nowMs: 9_000, isFinal: false)
        let second = timing.segment(nowMs: 14_000, isFinal: true)

        XCTAssertEqual(first.startMs, 0)
        XCTAssertEqual(first.endMs, 8_000)
        XCTAssertEqual(first.audioStartMs, 0)

        XCTAssertEqual(live.startMs, 6_500)
        XCTAssertNil(live.endMs)
        XCTAssertNil(live.audioStartMs)

        XCTAssertEqual(second.startMs, 8_000)
        XCTAssertEqual(second.endMs, 14_000)
        XCTAssertEqual(second.audioStartMs, 0)
    }
}
