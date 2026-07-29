import Foundation

/// Detects microphone segments that are just the far side of a call leaking
/// back in through the speakers.
///
/// In two-track capture the system lane already holds a clean copy of whatever
/// the Mac played, so an echo is recognizable without any acoustic processing:
/// it says the same words, at the same moment, as a "Them" segment. That makes
/// this a text problem rather than an audio one — deliberately, because
/// hardware echo cancellation (`setVoiceProcessingEnabled`) can silently
/// produce a dead microphone track when its audio graph isn't fully configured.
///
/// The thresholds are tuned to fail *open*: letting an echo through is a
/// cosmetic flaw, while dropping something the user actually said is data loss.
/// So short utterances are never suppressed (a "yeah" over the other party's
/// "yeah" is a real acknowledgement), and any segment carrying substantial
/// unique words survives as double-talk.
public enum EchoSuppression {
    /// Fraction of the mic segment's words that must also appear in the
    /// time-aligned system audio before it counts as an echo.
    public static let defaultSimilarityThreshold = 0.8
    /// Utterances shorter than this (in distinct words) are always kept.
    public static let defaultMinimumTokenCount = 3
    /// Slack for comparing lane timestamps, which drift by transcription latency.
    public static let defaultOverlapToleranceMs = 1_500

    public static func isEchoOfSystemAudio(
        micText: String,
        micStartMs: Int,
        micEndMs: Int?,
        segments: [ConversationSegment],
        similarityThreshold: Double = defaultSimilarityThreshold,
        minimumTokenCount: Int = defaultMinimumTokenCount,
        overlapToleranceMs: Int = defaultOverlapToleranceMs
    ) -> Bool {
        let micTokens = tokens(in: micText)
        guard micTokens.count >= minimumTokenCount else { return false }

        let micEndMs = micEndMs ?? micStartMs
        var systemTokens: Set<String> = []
        // Only the system lane can be an echo source; comparing the mic lane
        // against itself would suppress the user repeating their own words.
        for segment in segments where segment.speakerID == TwoTrackSpeaker.them.speakerID {
            let segmentEndMs = segment.endMs ?? segment.startMs
            let overlaps = micStartMs <= segmentEndMs + overlapToleranceMs
                && segment.startMs <= micEndMs + overlapToleranceMs
            guard overlaps else { continue }
            // A sentence the far side split across segments can arrive as one
            // mic segment, so pool every overlapping segment's words.
            systemTokens.formUnion(tokens(in: segment.text))
        }
        guard !systemTokens.isEmpty else { return false }

        let shared = micTokens.intersection(systemTokens).count
        return Double(shared) / Double(micTokens.count) >= similarityThreshold
    }

    static func tokens(in text: String) -> Set<String> {
        Set(
            text.lowercased()
                .split { !$0.isLetter && !$0.isNumber }
                .map(String.init)
        )
    }
}
