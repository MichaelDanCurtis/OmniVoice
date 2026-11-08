import XCTest
@testable import OmniVoiceCore

final class EchoSuppressionTests: XCTestCase {
    private func them(_ text: String, startMs: Int, endMs: Int?) -> ConversationSegment {
        ConversationSegment(
            id: UUID().uuidString,
            sessionID: "s",
            speakerID: TwoTrackSpeaker.them.speakerID,
            speakerDisplayName: TwoTrackSpeaker.them.displayName,
            startMs: startMs,
            endMs: endMs,
            text: text,
            state: .settled,
            confidence: nil
        )
    }

    private func me(_ text: String, startMs: Int, endMs: Int?) -> ConversationSegment {
        ConversationSegment(
            id: UUID().uuidString,
            sessionID: "s",
            speakerID: TwoTrackSpeaker.me.speakerID,
            speakerDisplayName: TwoTrackSpeaker.me.displayName,
            startMs: startMs,
            endMs: endMs,
            text: text,
            state: .settled,
            confidence: nil
        )
    }

    func testIdenticalOverlappingSpeechIsEcho() {
        // The speakers bled into the mic: same words, same moment.
        let system = [them("So the deadline moved to next Tuesday", startMs: 4_000, endMs: 7_000)]
        XCTAssertTrue(
            EchoSuppression.isEchoOfSystemAudio(
                micText: "So the deadline moved to next Tuesday",
                micStartMs: 4_100,
                micEndMs: 7_100,
                segments: system
            )
        )
    }

    func testNearIdenticalSpeechSurvivesASRVariance() {
        let system = [them("we should ship the beta on Friday afternoon", startMs: 0, endMs: 3_000)]
        // Mic heard the same sentence with one word misrecognized.
        XCTAssertTrue(
            EchoSuppression.isEchoOfSystemAudio(
                micText: "we should ship the beta on Friday afternoons",
                micStartMs: 100,
                micEndMs: 3_100,
                segments: system
            )
        )
    }

    func testSameWordsFarApartInTimeAreNotEcho() {
        // The user genuinely repeated the sentence a minute later.
        let system = [them("So the deadline moved to next Tuesday", startMs: 4_000, endMs: 7_000)]
        XCTAssertFalse(
            EchoSuppression.isEchoOfSystemAudio(
                micText: "So the deadline moved to next Tuesday",
                micStartMs: 64_000,
                micEndMs: 67_000,
                segments: system
            )
        )
    }

    func testDoubleTalkWithSubstantialUniqueWordsSurvives() {
        // User talks over the call: some shared words, but real unique content.
        let system = [them("the deadline moved to next Tuesday", startMs: 4_000, endMs: 7_000)]
        XCTAssertFalse(
            EchoSuppression.isEchoOfSystemAudio(
                micText: "wait that breaks our launch rehearsal and the client review",
                micStartMs: 4_500,
                micEndMs: 7_500,
                segments: system
            )
        )
    }

    func testShortBackchannelIsNeverSuppressed() {
        // "yeah" while the other side also says "yeah" is a real acknowledgement;
        // losing the user's own words is worse than letting an echo through.
        let system = [them("yeah", startMs: 1_000, endMs: 1_500)]
        XCTAssertFalse(
            EchoSuppression.isEchoOfSystemAudio(
                micText: "yeah",
                micStartMs: 1_100,
                micEndMs: 1_600,
                segments: system
            )
        )
    }

    func testEchoIsDetectedAcrossAdjacentSystemSegments() {
        // The far side's sentence was split into two segments; the mic heard it whole.
        let system = [
            them("could you send me", startMs: 2_000, endMs: 3_000),
            them("the updated invoice today", startMs: 3_000, endMs: 4_500),
        ]
        XCTAssertTrue(
            EchoSuppression.isEchoOfSystemAudio(
                micText: "could you send me the updated invoice today",
                micStartMs: 2_100,
                micEndMs: 4_600,
                segments: system
            )
        )
    }

    func testPunctuationAndCasingAreIgnored() {
        let system = [them("Absolutely, that works for me.", startMs: 0, endMs: 2_000)]
        XCTAssertTrue(
            EchoSuppression.isEchoOfSystemAudio(
                micText: "absolutely that works for me",
                micStartMs: 50,
                micEndMs: 2_050,
                segments: system
            )
        )
    }

    func testOwnMicSegmentsAreNeverUsedAsEchoSource() {
        // Comparing "Me" against "Me" would suppress the user repeating themselves.
        let priorOwnSpeech = [me("let me check the calendar", startMs: 1_000, endMs: 3_000)]
        XCTAssertFalse(
            EchoSuppression.isEchoOfSystemAudio(
                micText: "let me check the calendar",
                micStartMs: 1_100,
                micEndMs: 3_100,
                segments: priorOwnSpeech
            )
        )
    }

    func testNoSystemSegmentsMeansNoEcho() {
        XCTAssertFalse(
            EchoSuppression.isEchoOfSystemAudio(
                micText: "anything at all here",
                micStartMs: 0,
                micEndMs: 1_000,
                segments: []
            )
        )
    }

    func testEmptyMicTextIsNotEcho() {
        let system = [them("hello there friend", startMs: 0, endMs: 1_000)]
        XCTAssertFalse(
            EchoSuppression.isEchoOfSystemAudio(micText: "   ", micStartMs: 0, micEndMs: 1_000, segments: system)
        )
    }
}
