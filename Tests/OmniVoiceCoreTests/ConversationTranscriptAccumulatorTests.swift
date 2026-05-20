import XCTest
@testable import OmniVoiceCore

final class ConversationTranscriptAccumulatorTests: XCTestCase {
    func testIgnoresTransientListeningUpdate() {
        var accumulator = ConversationTranscriptAccumulator()

        let decision = accumulator.ingest(TranscriptUpdate(text: "listening", isFinal: false))

        XCTAssertEqual(decision, .ignore)
    }

    func testIgnoresRepeatedPartialText() {
        var accumulator = ConversationTranscriptAccumulator()

        _ = accumulator.ingest(TranscriptUpdate(text: "how many users", isFinal: false))
        let decision = accumulator.ingest(TranscriptUpdate(text: "how many users", isFinal: false))

        XCTAssertEqual(decision, .ignore)
    }

    func testEmitsFinalEvenWhenItMatchesLastPartial() {
        var accumulator = ConversationTranscriptAccumulator()

        _ = accumulator.ingest(TranscriptUpdate(text: "how many users", isFinal: false))
        let decision = accumulator.ingest(TranscriptUpdate(text: "how many users", isFinal: true))

        XCTAssertEqual(decision, .segment(text: "how many users", isFinal: true))
    }

    func testEmitsFinalListeningText() {
        var accumulator = ConversationTranscriptAccumulator()

        let decision = accumulator.ingest(TranscriptUpdate(text: "listening", isFinal: true))

        XCTAssertEqual(decision, .segment(text: "listening", isFinal: true))
    }

    func testTrimsAcceptedTranscriptText() {
        var accumulator = ConversationTranscriptAccumulator()

        let decision = accumulator.ingest(TranscriptUpdate(text: "  how many users  ", isFinal: false))

        XCTAssertEqual(decision, .segment(text: "how many users", isFinal: false))
    }
}
