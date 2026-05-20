import Foundation

public enum ConversationSegmentFinalization {
    public static func fallbackSettledRequest(
        from liveRequest: ConversationSegmentCreateRequest?,
        recordingEndMs: Int,
        audioPCMFloat32: Data?,
        audioSampleRate: Int
    ) -> ConversationSegmentCreateRequest? {
        guard let liveRequest, liveRequest.state == .live else {
            return nil
        }

        let text = liveRequest.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            return nil
        }

        let endMs = max(0, recordingEndMs, liveRequest.endMs ?? 0)
        return ConversationSegmentCreateRequest(
            audioStartMs: audioPCMFloat32 == nil ? nil : 0,
            startMs: 0,
            endMs: endMs,
            text: text,
            state: .settled,
            confidence: liveRequest.confidence,
            audioPCMFloat32: audioPCMFloat32,
            audioSampleRate: audioSampleRate
        )
    }
}
