import XCTest
@testable import OmniVoiceCore

final class TwoTrackConversationTests: XCTestCase {
    func testLaneSpeakersAreStable() {
        // Persisted into transcripts; changing these would relabel old sessions.
        XCTAssertEqual(TwoTrackSpeaker.me.speakerID, "speaker-me")
        XCTAssertEqual(TwoTrackSpeaker.me.displayName, "Me")
        XCTAssertEqual(TwoTrackSpeaker.them.speakerID, "speaker-them")
        XCTAssertEqual(TwoTrackSpeaker.them.displayName, "Them")
    }

    func testSortedInsertKeepsChronologicalOrderAcrossLanes() {
        var segments: [ConversationSegment] = []
        func segment(_ id: String, startMs: Int) -> ConversationSegment {
            ConversationSegment(
                id: id,
                sessionID: "s",
                speakerID: "speaker-me",
                speakerDisplayName: "Me",
                startMs: startMs,
                endMs: startMs + 100,
                text: id,
                state: .settled,
                confidence: nil
            )
        }

        // Lanes finalize out of chronological order: a later mic segment lands
        // before an earlier system segment finishes transcribing.
        ConversationSegmentOrdering.insert(segment("mic-2", startMs: 5_000), into: &segments)
        ConversationSegmentOrdering.insert(segment("sys-1", startMs: 1_000), into: &segments)
        ConversationSegmentOrdering.insert(segment("mic-3", startMs: 9_000), into: &segments)
        ConversationSegmentOrdering.insert(segment("sys-2", startMs: 7_000), into: &segments)

        XCTAssertEqual(segments.map(\.id), ["sys-1", "mic-2", "sys-2", "mic-3"])
    }

    func testSortedInsertIsStableForEqualTimestamps() {
        var segments: [ConversationSegment] = []
        func segment(_ id: String, startMs: Int) -> ConversationSegment {
            ConversationSegment(
                id: id, sessionID: "s", speakerID: "speaker-me", speakerDisplayName: "Me",
                startMs: startMs, endMs: nil, text: id, state: .settled, confidence: nil
            )
        }
        ConversationSegmentOrdering.insert(segment("a", startMs: 100), into: &segments)
        ConversationSegmentOrdering.insert(segment("b", startMs: 100), into: &segments)
        XCTAssertEqual(segments.map(\.id), ["a", "b"])
    }
}
