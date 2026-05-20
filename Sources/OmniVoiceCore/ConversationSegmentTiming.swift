import Foundation

public struct ConversationSegmentTiming: Equatable, Sendable {
    public struct Segment: Equatable, Sendable {
        public let startMs: Int
        public let endMs: Int?
        public let audioStartMs: Int?
    }

    private var lastSettledEndMs: Int

    public init(lastSettledEndMs: Int = 0) {
        self.lastSettledEndMs = max(0, lastSettledEndMs)
    }

    public mutating func segment(
        nowMs: Int,
        isFinal: Bool,
        liveWindowMs: Int = 2_500,
        audioContextWindowMs: Int = 12_000
    ) -> Segment {
        let clampedNow = max(0, nowMs)
        if isFinal {
            let startMs = min(lastSettledEndMs, clampedNow)
            lastSettledEndMs = clampedNow
            return Segment(
                startMs: startMs,
                endMs: clampedNow,
                audioStartMs: max(0, startMs - audioContextWindowMs)
            )
        }

        return Segment(
            startMs: max(0, clampedNow - liveWindowMs),
            endMs: nil,
            audioStartMs: nil
        )
    }
}
