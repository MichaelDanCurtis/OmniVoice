import Foundation

/// Speaker identities for mic-vs-system two-track conversations.
///
/// Capture topology IS the diarization (the quill method): the microphone track
/// can only be the user, the system-audio track can only be everyone else — so
/// labels are exact by construction, with no speaker-identification model.
/// The raw ids persist into transcripts; keep them stable.
public enum TwoTrackSpeaker: Sendable {
    case me
    case them

    public var speakerID: String {
        switch self {
        case .me: "speaker-me"
        case .them: "speaker-them"
        }
    }

    public var displayName: String {
        switch self {
        case .me: "Me"
        case .them: "Them"
        }
    }
}

/// Ordering for the live transcript when multiple lanes append concurrently.
/// Lanes finalize independently, so arrival order is not chronological order;
/// insertion keeps the array sorted by `startMs` (stable for ties).
public enum ConversationSegmentOrdering {
    public static func insert(_ segment: ConversationSegment, into segments: inout [ConversationSegment]) {
        let index = segments.firstIndex { $0.startMs > segment.startMs } ?? segments.endIndex
        segments.insert(segment, at: index)
    }
}
