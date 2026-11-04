import XCTest
@testable import OmniVoiceCore

final class SpeechActivitySummaryTests: XCTestCase {
    func testEmptyCaptureDoesNotContainSpeech() {
        let summary = SpeechActivitySummary()

        XCTAssertFalse(summary.containsLikelySpeech())
        XCTAssertEqual(summary.averageLevel, 0)
        XCTAssertEqual(summary.activeBufferRatio, 0)
    }

    func testQuietNoiseDoesNotContainSpeech() {
        var summary = SpeechActivitySummary()

        for _ in 0..<80 {
            summary.observe(level: 0.0005)
        }

        XCTAssertFalse(summary.containsLikelySpeech())
    }

    func testSustainedSpeechLevelContainsSpeech() {
        var summary = SpeechActivitySummary()

        for _ in 0..<20 {
            summary.observe(level: 0.0005)
        }
        for _ in 0..<10 {
            summary.observe(level: 0.006)
        }

        XCTAssertTrue(summary.containsLikelySpeech())
    }

    func testShortPeakContainsSpeech() {
        var summary = SpeechActivitySummary()

        for _ in 0..<30 {
            summary.observe(level: 0.0003)
        }
        summary.observe(level: 0.03)

        XCTAssertTrue(summary.containsLikelySpeech())
        XCTAssertEqual(summary.peakLevel, 0.03, accuracy: 0.0001)
    }
}
